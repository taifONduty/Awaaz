begin;
do $$ begin
  if not exists(select 1 from pg_catalog.pg_roles where rolname='awaaz_evidence') then
    create role awaaz_evidence nologin noinherit;
  elsif exists(select 1 from pg_catalog.pg_roles where rolname='awaaz_evidence'
    and (rolsuper or rolbypassrls or rolcreatedb or rolcreaterole or rolreplication or rolinherit)) then
    raise exception 'Existing awaaz_evidence role has unsafe privileges';
  end if;
end $$;
alter role awaaz_evidence set search_path='';
alter role awaaz_evidence set statement_timeout='30s';
alter role awaaz_evidence set lock_timeout='4s';
alter role awaaz_evidence set idle_in_transaction_session_timeout='15s';
grant usage on schema awaaz_private to awaaz_evidence;

create table awaaz_private.road_graphs (
  graph_version text primary key check(graph_version ~ '^dhaka-gh11\.1-[0-9a-f]{20}-[0-9a-f]{12}$'),
  metadata jsonb not null,
  expected_edges integer not null check(expected_edges between 1000 and 1000000),
  imported_edges integer not null default 0 check(imported_edges>=0 and imported_edges<=expected_edges),
  ready boolean not null default false,
  evidence_epoch bigint not null default 0 check(evidence_epoch>=0),
  created_at timestamptz not null default now()
);
create table awaaz_private.road_edges (
  graph_version text not null references awaaz_private.road_graphs(graph_version),
  edge_id integer not null check(edge_id between 0 and 10000000),
  forward_key integer not null,
  reverse_key integer not null,
  car_forward boolean not null, car_reverse boolean not null,
  foot_forward boolean not null, foot_reverse boolean not null,
  length_metres double precision not null check(length_metres>0 and length_metres<=100000),
  geometry extensions.geometry(LineString,4326) not null,
  location extensions.geography(LineString,4326) generated always as (geometry::extensions.geography) stored,
  primary key(graph_version,edge_id),
  check(forward_key=edge_id*2 and reverse_key=edge_id*2+1),
  check(car_forward or car_reverse or foot_forward or foot_reverse),
  check(extensions.st_isvalid(geometry) and extensions.st_npoints(geometry) between 2 and 10000
    and extensions.st_length(geometry::extensions.geography)>0
    and extensions.st_xmin(geometry::extensions.box3d)>=90 and extensions.st_xmax(geometry::extensions.box3d)<=90.7
    and extensions.st_ymin(geometry::extensions.box3d)>=23.5 and extensions.st_ymax(geometry::extensions.box3d)<=24.3)
);
create index road_edges_nearby on awaaz_private.road_edges using gist(location);
create table awaaz_private.road_publications (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid not null references auth.users(id) on delete cascade,
  client_request_id uuid not null,
  report_id uuid not null unique,
  event_id uuid not null unique,
  review_id uuid not null,
  graph_version text not null,
  edge_id integer not null,
  payload_hash text not null check(payload_hash ~ '^[0-9a-f]{64}$'),
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  unique(actor_id,client_request_id),
  foreign key(graph_version,edge_id) references awaaz_private.road_edges(graph_version,edge_id)
);
alter table awaaz_private.road_graphs enable row level security;
alter table awaaz_private.road_edges enable row level security;
alter table awaaz_private.road_publications enable row level security;
revoke all on awaaz_private.road_graphs,awaaz_private.road_edges,awaaz_private.road_publications
  from public,anon,authenticated,service_role,awaaz_api,awaaz_evidence;

-- Import is a trusted offline operator capability, isolated from consumer API
-- credentials. The importer verifies artifact/engine/input hashes before RPCs.
-- Calls run in one transaction; partial imports can never become ready.
create function awaaz_private.graph_import(p_op text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  v_version text:=p_data->>'graphVersion'; v_graph awaaz_private.road_graphs;
  v_meta jsonb; v_count integer; v_expected integer;
begin
  if v_version is null or v_version!~'^dhaka-gh11\.1-[0-9a-f]{20}-[0-9a-f]{12}$' then
    raise exception using errcode='P0001',message='invalid_graph';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('graph:'||v_version,0));
  if p_op='begin' then
    v_meta:=p_data->'metadata'; v_expected:=(v_meta->>'edgeCount')::integer;
    if v_meta is null or v_meta->>'graphVersion' is distinct from v_version or v_expected is null
      or v_expected not between 1000 and 1000000 or v_meta->>'format' is distinct from 'awaaz-gh-edges-v1'
      or v_meta->>'engineSha256' is distinct from '8462f758d9ea49edaded557cec5c687a0a24f004ec371cd4daaeb0534824ea33'
      or coalesce(v_meta->>'extractSha256','')!~'^[0-9a-f]{64}$' or coalesce(v_meta->>'configSha256','')!~'^[0-9a-f]{64}$'
      or coalesce(v_meta->>'edgesSha256','')!~'^[0-9a-f]{64}$'
      or v_version <> 'dhaka-gh11.1-'||left(v_meta->>'extractSha256',20)||'-'||left(v_meta->>'configSha256',12)
      or (v_meta->>'sourceTimestamp')::timestamptz is null or (v_meta->>'importDate')::timestamptz is null
      or (v_meta->>'sourceTimestamp')::timestamptz>(v_meta->>'importDate')::timestamptz then
      raise exception using errcode='P0001',message='invalid_graph';
    end if;
    select * into v_graph from awaaz_private.road_graphs where graph_version=v_version for update;
    if found then
      if v_graph.metadata<>v_meta then raise exception using errcode='P0001',message='graph_conflict'; end if;
      return jsonb_build_object('ready',v_graph.ready,'replayed',true);
    end if;
    insert into awaaz_private.road_graphs(graph_version,metadata,expected_edges) values(v_version,v_meta,v_expected);
    return jsonb_build_object('ready',false,'replayed',false);
  end if;
  select * into v_graph from awaaz_private.road_graphs where graph_version=v_version for update;
  if not found then raise exception using errcode='P0001',message='graph_not_ready'; end if;
  if v_graph.ready then raise exception using errcode='P0001',message='graph_immutable'; end if;
  if p_op='append' then
    if jsonb_typeof(p_data->'edges') is distinct from 'array' or jsonb_array_length(p_data->'edges') not between 1 and 500 then
      raise exception using errcode='P0001',message='invalid_graph';
    end if;
    if v_graph.imported_edges+jsonb_array_length(p_data->'edges')>v_graph.expected_edges then
      raise exception using errcode='P0001',message='graph_incomplete';
    end if;
    insert into awaaz_private.road_edges(graph_version,edge_id,forward_key,reverse_key,car_forward,car_reverse,foot_forward,foot_reverse,length_metres,geometry)
      select v_version,(x->>'edgeId')::integer,(x->>'forwardKey')::integer,(x->>'reverseKey')::integer,
        (x->>'carForward')::boolean,(x->>'carReverse')::boolean,(x->>'footForward')::boolean,(x->>'footReverse')::boolean,
        (x->>'lengthMetres')::double precision,extensions.st_setsrid(extensions.st_geomfromgeojson(x->'geometry'),4326)
      from jsonb_array_elements(p_data->'edges') x;
    update awaaz_private.road_graphs set imported_edges=imported_edges+jsonb_array_length(p_data->'edges') where graph_version=v_version;
    return jsonb_build_object('appended',jsonb_array_length(p_data->'edges'));
  elsif p_op='finalize' then
    select count(*)::integer into v_count from awaaz_private.road_edges where graph_version=v_version;
    if v_count<>v_graph.expected_edges or v_graph.imported_edges<>v_graph.expected_edges then raise exception using errcode='P0001',message='graph_incomplete'; end if;
    update awaaz_private.road_graphs set ready=true where graph_version=v_version;
    return jsonb_build_object('ready',true,'edges',v_count);
  end if;
  raise exception using errcode='P0001',message='invalid_request';
end $$;
revoke all on function awaaz_private.graph_import(text,jsonb) from public,anon,authenticated,service_role,awaaz_api,awaaz_evidence;
grant execute on function awaaz_private.graph_import(text,jsonb) to awaaz_evidence;

create function awaaz_private.require_moderator(p_actor uuid) returns void
language plpgsql set search_path='' as $$ begin
  perform 1 from awaaz_private.moderators where user_id=p_actor and enabled for share;
  if not found then raise exception using errcode='P0001',message='moderator_required'; end if;
  perform awaaz_private.require_profile(p_actor);
  perform 1 from auth.users where id=p_actor and phone_confirmed_at is not null for share;
  if not found then raise exception using errcode='P0001',message='verification_required'; end if;
end $$;
revoke all on function awaaz_private.require_moderator(uuid) from public,anon,authenticated,service_role,awaaz_api,awaaz_evidence;

alter function awaaz_private.moderation_command(uuid,text,jsonb) rename to moderation_command_v1;
revoke all on function awaaz_private.moderation_command_v1(uuid,text,jsonb) from public,anon,authenticated,service_role,awaaz_api,awaaz_evidence;
create function awaaz_private.moderation_command(p_actor uuid,p_op text,p_data jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  v_version text; v_id uuid; v_report public.report_submissions;
  v_review awaaz_private.report_reviews; v_edge awaaz_private.road_edges;
  v_publication awaaz_private.road_publications; v_request uuid; v_hash text;
  v_items jsonb; v_event uuid; v_summary text; v_replayed boolean:=false; v_status text;
begin
  if p_op not in ('road_candidates','publish') then
    return awaaz_private.moderation_command_v1(p_actor,p_op,p_data);
  end if;
  perform awaaz_private.require_moderator(p_actor);
  v_id:=(p_data->>'reportId')::uuid; v_version:=p_data->>'graphVersion';
  if v_id is null or v_version is null then raise exception using errcode='P0001',message='invalid_request'; end if;
  if p_op='publish' then
    v_request:=(p_data->>'clientRequestId')::uuid; v_hash:=p_data->>'payloadHash';
    if v_request is null or v_hash is null or v_hash!~'^[0-9a-f]{64}$' or (p_data->>'edgeId')::integer is null then
      raise exception using errcode='P0001',message='invalid_request';
    end if;
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('moderation:'||p_actor::text,0));
    select * into v_publication from awaaz_private.road_publications where actor_id=p_actor and client_request_id=v_request;
    if found then
      if v_publication.payload_hash<>v_hash or v_publication.report_id<>v_id or v_publication.graph_version<>v_version
        or v_publication.edge_id<>(p_data->>'edgeId')::integer then raise exception using errcode='P0001',message='idempotency_conflict'; end if;
      v_replayed:=true;
    end if;
  end if;
  if not v_replayed then
    perform 1 from awaaz_private.road_graphs where graph_version=v_version and ready;
    if not found then raise exception using errcode='P0001',message='graph_not_ready'; end if;
    select * into v_report from public.report_submissions where id=v_id for update;
    if not found then raise exception using errcode='P0001',message='not_found'; end if;
    if v_report.owner_id=p_actor then raise exception using errcode='P0001',message='self_review_forbidden'; end if;
    if p_op='road_candidates' then
      if v_report.status='rejected' then raise exception using errcode='P0001',message='report_not_approved'; end if;
      select coalesce(jsonb_agg(x.item order by x.distance,x.edge_id),'[]'::jsonb) into v_items from (
        select e.edge_id,extensions.st_distance(e.location,v_report.location) distance,
          jsonb_build_object('edgeId',e.edge_id,'distanceMetres',round(extensions.st_distance(e.location,v_report.location)::numeric,2),
            'lengthMetres',e.length_metres,'carForward',e.car_forward,'carReverse',e.car_reverse,
            'footForward',e.foot_forward,'footReverse',e.foot_reverse,'geometry',extensions.st_asgeojson(e.geometry)::jsonb) item
        from awaaz_private.road_edges e where e.graph_version=v_version and extensions.st_dwithin(e.location,v_report.location,35)
        order by distance,e.edge_id limit 5
      ) x;
      return jsonb_build_object('graphVersion',v_version,'requiresHumanSelection',true,'items',v_items);
    end if;
    select * into v_review from awaaz_private.report_reviews where report_id=v_id and decision='approve';
    if not found or v_report.status<>'reviewed' then raise exception using errcode='P0001',message='report_not_approved'; end if;
    if v_review.evidence_expires_at<=now() then raise exception using errcode='P0001',message='stale_report'; end if;
    if exists(select 1 from awaaz_private.road_publications where report_id=v_id) then
      raise exception using errcode='P0001',message='already_published';
    end if;
    select * into v_edge from awaaz_private.road_edges where graph_version=v_version and edge_id=(p_data->>'edgeId')::integer;
    if not found or not extensions.st_dwithin(v_edge.location,v_report.location,35) then
      raise exception using errcode='P0001',message='edge_not_near_report';
    end if;
    -- Public text is fixed vocabulary, never an edited private accusation.
    v_summary:=case v_report.category when 'lighting' then 'Reviewed report of poor lighting nearby.'
      when 'obstruction' then 'Reviewed report of a road obstruction nearby.'
      when 'theft' then 'Reviewed report of theft nearby.' when 'harassment' then 'Reviewed report of harassment nearby.'
      when 'accident' then 'Reviewed report of an accident nearby.' else 'Reviewed road condition report nearby.' end;
    insert into public.road_events(submission_id,category,road_segment_id,centroid,public_summary,observed_at,expires_at)
      values(v_id,v_report.category,v_version||':'||v_edge.edge_id::text,
        extensions.st_transform(extensions.st_closestpoint(extensions.st_transform(v_edge.geometry,32646),
          extensions.st_transform(v_report.location::extensions.geometry,32646)),4326)::extensions.geography,
        v_summary,v_report.observed_at,v_review.evidence_expires_at) returning id into v_event;
    insert into awaaz_private.road_publications(actor_id,client_request_id,report_id,event_id,review_id,graph_version,edge_id,payload_hash,expires_at)
      values(p_actor,v_request,v_id,v_event,v_review.id,v_version,v_edge.edge_id,v_hash,v_review.evidence_expires_at) returning * into v_publication;
    update awaaz_private.road_graphs set evidence_epoch=evidence_epoch+1 where graph_version=v_version;
  end if;
  v_status:=case when not exists(select 1 from public.road_events where id=v_publication.event_id) then 'withdrawn'
    when v_publication.expires_at<=now() then 'expired' else 'published' end;
  return jsonb_build_object('id',v_publication.id,'reportId',v_publication.report_id,'eventId',v_publication.event_id,
    'graphVersion',v_publication.graph_version,'edgeId',v_publication.edge_id,'expiresAt',v_publication.expires_at,
    'publishedAt',v_publication.created_at,'status',v_status,'replayed',v_replayed);
end $$;
revoke all on function awaaz_private.moderation_command(uuid,text,jsonb) from public,anon,authenticated,service_role,awaaz_api,awaaz_evidence;
grant execute on function awaaz_private.moderation_command(uuid,text,jsonb) to awaaz_api;

-- Invalidate a future evidence overlay transactionally when withdrawal/account
-- erasure removes an event. Expiry also bounds every future snapshot lifetime.
create function awaaz_private.invalidate_road_evidence() returns trigger
language plpgsql security definer set search_path='' as $$ begin
  update awaaz_private.road_graphs g set evidence_epoch=evidence_epoch+1
    from awaaz_private.road_publications p where p.event_id=old.id and g.graph_version=p.graph_version;
  return old;
end $$;
revoke all on function awaaz_private.invalidate_road_evidence() from public,anon,authenticated,service_role,awaaz_api,awaaz_evidence;
create trigger road_evidence_changed after update or delete on public.road_events for each row execute function awaaz_private.invalidate_road_evidence();
commit;
