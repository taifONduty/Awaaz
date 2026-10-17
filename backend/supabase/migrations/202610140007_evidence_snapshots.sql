begin;
-- Coarse public coordinates are enforced on every writer, including a future
-- service-role task. Clients cannot bypass API rounding through PostgREST.
revoke select(centroid) on public.road_events from authenticated;
create function awaaz_private.coarsen_event_location() returns trigger
language plpgsql set search_path='' as $$ begin
  new.centroid:=extensions.st_setsrid(extensions.st_makepoint(
    round(extensions.st_x(new.centroid::extensions.geometry)::numeric,3)::double precision,
    round(extensions.st_y(new.centroid::extensions.geometry)::numeric,3)::double precision),4326)::extensions.geography;
  return new;
end $$;
revoke all on function awaaz_private.coarsen_event_location() from public,anon,authenticated,service_role,awaaz_api,awaaz_evidence;
create trigger event_location_coarse before insert or update of centroid on public.road_events
  for each row execute function awaaz_private.coarsen_event_location();
update public.road_events set centroid=centroid;

alter table public.risk_snapshots add column evidence_epoch bigint not null default -1 check(evidence_epoch>=-1);
alter table public.risk_snapshots add column graph_metadata_digest text check(graph_metadata_digest ~ '^[0-9a-f]{64}$');
alter table public.risk_snapshots add column registered_edge_count integer not null default 0 check(registered_edge_count>=0);
alter table public.risk_snapshots add column evidenced_edge_count integer not null default 0 check(evidenced_edge_count between 0 and registered_edge_count);
-- Temporal groups are deliberately not described as independent incidents.
alter table public.edge_risk rename column independent_event_count to event_cluster_count;
alter table public.edge_risk add column incident_signal double precision check(incident_signal between 0 and 1);
alter table public.edge_risk add column environment_signal double precision check(environment_signal between 0 and 1);
alter table public.edge_risk add column categories jsonb not null default '{}'::jsonb check(jsonb_typeof(categories)='object');
alter table public.edge_risk add column last_observed_at timestamptz;
create index snapshots_graph_epoch_time on public.risk_snapshots(graph_version,evidence_epoch,created_at desc);

create function awaaz_private.snapshot_is_current(p_id uuid) returns boolean
language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.risk_snapshots s join awaaz_private.road_graphs g on g.graph_version=s.graph_version
    where s.id=p_id and g.ready and s.scoring_version='reviewed-decay-v1'
      and s.evidence_epoch=g.evidence_epoch and s.expires_at>statement_timestamp()
      and s.graph_metadata_digest=pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(g.metadata::text,'UTF8')),'hex'));
$$;
revoke all on function awaaz_private.snapshot_is_current(uuid) from public,anon,authenticated,service_role,awaaz_api,awaaz_evidence;
create function awaaz_private.current_snapshot_ids() returns uuid[]
language sql stable security definer set search_path='' as $$
  select coalesce(array_agg(s.id),'{}'::uuid[]) from public.risk_snapshots s
    join awaaz_private.road_graphs g on g.graph_version=s.graph_version
    where g.ready and s.scoring_version='reviewed-decay-v1' and s.evidence_epoch=g.evidence_epoch
      and s.expires_at>statement_timestamp()
      and s.graph_metadata_digest=pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(g.metadata::text,'UTF8')),'hex');
$$;
revoke all on function awaaz_private.current_snapshot_ids() from public,anon,authenticated,service_role,awaaz_api,awaaz_evidence;
grant execute on function awaaz_private.current_snapshot_ids() to authenticated;
create index snapshots_live_expiry on public.risk_snapshots(expires_at);
drop policy snapshots_visible on public.risk_snapshots;
drop policy edge_risk_visible on public.edge_risk;
-- InitPlan computes eligible IDs once, avoiding one private lookup per edge.
create policy snapshots_visible on public.risk_snapshots for select to authenticated using (id=any((select awaaz_private.current_snapshot_ids())::uuid[]));
create policy edge_risk_visible on public.edge_risk for select to authenticated using (snapshot_id=any((select awaaz_private.current_snapshot_ids())::uuid[]));

create function awaaz_private.build_evidence_snapshot(p_version text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  v_graph awaaz_private.road_graphs; v_snapshot public.risk_snapshots;
  v_now timestamptz:=clock_timestamp(); v_expiry timestamptz; v_count integer;
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('snapshotbuild:'||p_version,0));
  -- Publication/removal cannot commit its epoch update while this build holds
  -- the graph lock. Once it commits, that update immediately invalidates us.
  select * into v_graph from awaaz_private.road_graphs where graph_version=p_version and ready for share;
  if not found then raise exception using errcode='P0001',message='graph_not_ready'; end if;
  select * into v_snapshot from public.risk_snapshots s where s.graph_version=p_version
    and s.evidence_epoch=v_graph.evidence_epoch and s.scoring_version='reviewed-decay-v1'
    and s.expires_at>v_now+interval '30 seconds' and s.created_at>=v_now-interval '30 seconds'
    and awaaz_private.snapshot_is_current(s.id) order by s.created_at desc,s.id desc limit 1;
  if found then return jsonb_build_object('id',v_snapshot.id,'replayed',true); end if;
  select least(v_now+interval '2 minutes',min(least(e.expires_at,a.evidence_expires_at,p.expires_at))) into v_expiry
    from awaaz_private.road_publications p join public.road_events e on e.id=p.event_id and e.submission_id=p.report_id
    join public.report_submissions r on r.id=p.report_id and r.status='reviewed'
    join awaaz_private.report_reviews a on a.id=p.review_id and a.report_id=r.id and a.decision='approve'
    where p.graph_version=p_version and e.category=r.category and e.observed_at=r.observed_at
      and e.road_segment_id=p_version||':'||p.edge_id::text
      and least(e.expires_at,a.evidence_expires_at,p.expires_at)>v_now;
  -- Empty aggregates have no earliest expiry; the snapshot is explicitly all
  -- unknown. An empty snapshot is not an all-safe classification.
  v_expiry:=coalesce(v_expiry,v_now+interval '2 minutes');
  insert into public.risk_snapshots(graph_version,scoring_version,created_at,expires_at,evidence_epoch,graph_metadata_digest,registered_edge_count)
    values(p_version,'reviewed-decay-v1',v_now,v_expiry,v_graph.evidence_epoch,
      pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(v_graph.metadata::text,'UTF8')),'hex'),v_graph.imported_edges)
    returning * into v_snapshot;
  with eligible as (
    select p.edge_id,e.category,e.observed_at,r.owner_id,e.id event_id,
      exp(-ln(2.0)*greatest(0,extract(epoch from v_now-e.observed_at)) /
        case e.category when 'accident' then 1800 when 'lighting' then 21600 when 'obstruction' then 10800 else 3600 end) weight
    from awaaz_private.road_publications p join public.road_events e on e.id=p.event_id and e.submission_id=p.report_id
    join public.report_submissions r on r.id=p.report_id and r.status='reviewed'
    join awaaz_private.report_reviews a on a.id=p.review_id and a.report_id=r.id and a.decision='approve'
    where p.graph_version=p_version and e.category=r.category and e.observed_at=r.observed_at
      and e.road_segment_id=p_version||':'||p.edge_id::text
      and least(e.expires_at,a.evidence_expires_at,p.expires_at)>v_now
  ), bounded as (
    -- Across categories/events on an edge, one contributor has <=1 total
    -- influence. Duplicate submissions cannot manufacture corroboration.
    select *,weight/greatest(1,sum(weight) over(partition by edge_id,owner_id)) capped_weight,
      lag(observed_at) over(partition by edge_id,category order by observed_at,owner_id,event_id) previous_time from eligible
  ), clustered as (
    select *,sum(case when previous_time is null then 1 when category in ('lighting','obstruction') then 0
      when observed_at-previous_time>interval '30 minutes' then 1 else 0 end)
      over(partition by edge_id,category order by observed_at,owner_id,event_id rows unbounded preceding) cluster_id from bounded
  ), clusters as (
    -- Multiple witnesses of one temporal group contribute its strongest capped
    -- observation, rather than a sum of potentially correlated accounts.
    select edge_id,category,cluster_id,max(capped_weight) weight,max(observed_at) last_seen
      from clustered group by edge_id,category,cluster_id
  ), category_totals as (
    select edge_id,category,count(*)::integer clusters,sum(weight) weight,max(last_seen) last_seen
      from clusters group by edge_id,category
  ), totals as (
    select edge_id,sum(clusters)::integer clusters,least(4,sum(weight)) weight,
      case when count(*) filter(where category in ('theft','harassment','accident'))>0
        then least(4,sum(weight) filter(where category in ('theft','harassment','accident'))) else null end incident,
      case when count(*) filter(where category in ('lighting','obstruction','other'))>0
        then least(4,sum(weight) filter(where category in ('lighting','obstruction','other'))) else null end environment,
      jsonb_object_agg(category,jsonb_build_object('clusters',clusters,'lastObservedAt',last_seen) order by category) categories,
      max(last_seen) last_seen from category_totals group by edge_id
  ) insert into public.edge_risk(snapshot_id,edge_id,risk_signal,uncertainty,confidence,event_cluster_count,incident_signal,environment_signal,categories,last_observed_at)
    select v_snapshot.id,g.edge_id::text,case when t.clusters is null then null else t.weight/(1+t.weight) end,
      1,0,coalesce(t.clusters,0),case when t.incident is null then null else t.incident/(1+t.incident) end,
      case when t.environment is null then null else t.environment/(1+t.environment) end,coalesce(t.categories,'{}'::jsonb),t.last_seen
    from awaaz_private.road_edges g join totals t on t.edge_id=g.edge_id where g.graph_version=p_version;
  select count(*)::integer into v_count from public.edge_risk where snapshot_id=v_snapshot.id and event_cluster_count>0;
  update public.risk_snapshots set evidenced_edge_count=v_count where id=v_snapshot.id;
  return jsonb_build_object('id',v_snapshot.id,'replayed',false);
end $$;
revoke all on function awaaz_private.build_evidence_snapshot(text) from public,anon,authenticated,service_role,awaaz_api,awaaz_evidence;
grant execute on function awaaz_private.build_evidence_snapshot(text) to awaaz_evidence;

-- Export sparse evidence only. Unlisted edges have an explicit unknown default.
-- Caller checks the metadata on every page and once more after the final page.
create function awaaz_private.read_evidence_snapshot(p_id uuid,p_after integer default -1) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_snapshot public.risk_snapshots; v_graph awaaz_private.road_graphs; v_items jsonb; v_next integer:=null;
begin
  if p_after is null or p_after not between -1 and 10000000 then raise exception using errcode='P0001',message='invalid_request'; end if;
  select * into v_snapshot from public.risk_snapshots where id=p_id;
  if not found then raise exception using errcode='P0001',message='snapshot_unavailable'; end if;
  select * into v_graph from awaaz_private.road_graphs where graph_version=v_snapshot.graph_version and ready for share;
  if not found or v_snapshot.scoring_version<>'reviewed-decay-v1' or v_snapshot.evidence_epoch<>v_graph.evidence_epoch
    or v_snapshot.expires_at<=clock_timestamp()
    or v_snapshot.graph_metadata_digest is distinct from pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(v_graph.metadata::text,'UTF8')),'hex') then
    raise exception using errcode='P0001',message='snapshot_unavailable';
  end if;
  select coalesce(jsonb_agg(x.item order by x.edge_id),'[]'::jsonb) into v_items from (
    select g.edge_id,jsonb_build_object('edgeId',g.edge_id,'forwardKey',g.forward_key,'reverseKey',g.reverse_key,
      'carForward',g.car_forward,'carReverse',g.car_reverse,'footForward',g.foot_forward,'footReverse',g.foot_reverse,
      'evidenceIndex',r.risk_signal,'incidentIndex',r.incident_signal,'environmentIndex',r.environment_signal,
      'confidence',r.confidence,'uncertainty',r.uncertainty,'eventClusterCount',r.event_cluster_count,
      'categories',r.categories,'lastObservedAt',r.last_observed_at) item
    from public.edge_risk r join awaaz_private.road_edges g on g.graph_version=v_snapshot.graph_version and g.edge_id=r.edge_id::integer
    where r.snapshot_id=p_id and r.event_cluster_count>0 and g.edge_id>p_after order by g.edge_id limit 501
  ) x;
  if jsonb_array_length(v_items)>500 then v_next:=(v_items->499->>'edgeId')::integer; v_items:=v_items-500; end if;
  return jsonb_build_object('metadata',jsonb_build_object('id',v_snapshot.id,'graphVersion',v_snapshot.graph_version,
    'scoringVersion',v_snapshot.scoring_version,'createdAt',v_snapshot.created_at,'expiresAt',v_snapshot.expires_at,
    'evidenceEpoch',v_snapshot.evidence_epoch::text,'graphMetadataDigest',v_snapshot.graph_metadata_digest,
    'registeredEdgeCount',v_snapshot.registered_edge_count,'evidencedEdgeCount',v_snapshot.evidenced_edge_count,
    'sourceGraphFiles',v_graph.metadata->'sourceGraphFiles',
    'safetyCoverage',null,'source','openstreetmap','license','ODbL-1.0','attribution','© OpenStreetMap contributors',
    'unknownDefault',jsonb_build_object('evidenceIndex',null,'confidence',0,'uncertainty',1,'eventClusterCount',0)),
    'items',v_items,'nextEdgeId',v_next);
end $$;
revoke all on function awaaz_private.read_evidence_snapshot(uuid,integer) from public,anon,authenticated,service_role,awaaz_api,awaaz_evidence;
grant execute on function awaaz_private.read_evidence_snapshot(uuid,integer) to awaaz_api,awaaz_evidence;

create function awaaz_private.current_evidence_snapshot(p_version text) returns jsonb
language sql security definer set search_path='' as $$
  select coalesce((select jsonb_build_object('id',s.id) from public.risk_snapshots s where s.graph_version=p_version
    and awaaz_private.snapshot_is_current(s.id) order by s.created_at desc,s.id desc limit 1),'null'::jsonb);
$$;
revoke all on function awaaz_private.current_evidence_snapshot(text) from public,anon,authenticated,service_role,awaaz_api,awaaz_evidence;
grant execute on function awaaz_private.current_evidence_snapshot(text) to awaaz_api,awaaz_evidence;

create function awaaz_private.read_evidence_edge(p_id uuid,p_edge integer) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_page jsonb; v_item jsonb;
begin
  v_page:=awaaz_private.read_evidence_snapshot(p_id,10000000);
  select jsonb_build_object('edgeId',g.edge_id,'forwardKey',g.forward_key,'reverseKey',g.reverse_key,
    'carForward',g.car_forward,'carReverse',g.car_reverse,'footForward',g.foot_forward,'footReverse',g.foot_reverse,
    'evidenceIndex',r.risk_signal,'incidentIndex',r.incident_signal,'environmentIndex',r.environment_signal,
    'confidence',coalesce(r.confidence,0),'uncertainty',coalesce(r.uncertainty,1),'eventClusterCount',coalesce(r.event_cluster_count,0),
    'categories',coalesce(r.categories,'{}'::jsonb),'lastObservedAt',r.last_observed_at) into v_item
    from awaaz_private.road_edges g left join public.edge_risk r on r.snapshot_id=p_id and r.edge_id=g.edge_id::text
    where g.graph_version=v_page->'metadata'->>'graphVersion' and g.edge_id=p_edge;
  if v_item is null then raise exception using errcode='P0001',message='edge_unavailable'; end if;
  return jsonb_build_object('metadata',v_page->'metadata','edge',v_item);
end $$;
revoke all on function awaaz_private.read_evidence_edge(uuid,integer) from public,anon,authenticated,service_role,awaaz_api,awaaz_evidence;
grant execute on function awaaz_private.read_evidence_edge(uuid,integer) to awaaz_api,awaaz_evidence;

-- Sparse rows plus bounded cleanup prevent creating a complete-city copy every
-- minute. The metadata's null default is authoritative for unobserved edges.
create function awaaz_private.prune_evidence_snapshots() returns integer
language plpgsql security definer set search_path='' as $$ declare v_count integer;
begin
  with expired as (select id from public.risk_snapshots where expires_at<clock_timestamp()-interval '5 minutes'
    order by expires_at,id limit 1000 for update skip locked)
    delete from public.risk_snapshots s using expired e where s.id=e.id;
  get diagnostics v_count=row_count;
  return v_count;
end $$;
revoke all on function awaaz_private.prune_evidence_snapshots() from public,anon,authenticated,service_role,awaaz_api,awaaz_evidence;
grant execute on function awaaz_private.prune_evidence_snapshots() to awaaz_evidence;
commit;
