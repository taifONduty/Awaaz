begin;
-- Retains only retry identity/hash after a private payload is deleted. Retention
-- and account erasure must include this ledger; no text or coordinates live here.
create table awaaz_private.report_commands (
  actor_id uuid not null references auth.users(id) on delete cascade,
  client_request_id uuid not null,
  report_id uuid not null unique,
  payload_hash text not null check(payload_hash ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now(),
  primary key(actor_id,client_request_id)
);
alter table awaaz_private.report_commands enable row level security;
revoke all on awaaz_private.report_commands from public,anon,authenticated,service_role,awaaz_api;
insert into awaaz_private.report_commands(actor_id,client_request_id,report_id,payload_hash,created_at)
  select owner_id,client_request_id,id,payload_hash,created_at from public.report_submissions;
insert into awaaz_private.account_quotas(actor_id,kind,day,used)
  select owner_id,'report',(created_at at time zone 'UTC')::date,count(*)::integer
  from public.report_submissions group by owner_id,(created_at at time zone 'UTC')::date
  on conflict(actor_id,kind,day) do update set used=greatest(awaaz_private.account_quotas.used,excluded.used);
create index report_submissions_cursor on public.report_submissions(owner_id,created_at desc,id desc);

create function awaaz_private.report_json(p_report public.report_submissions) returns jsonb
language sql stable set search_path='' as $$
  select jsonb_build_object('id',p_report.id,'category',p_report.category,'description',p_report.description,
    'latitude',extensions.st_y(p_report.location::extensions.geometry),
    'longitude',extensions.st_x(p_report.location::extensions.geometry),
    'observedAt',p_report.observed_at,'createdAt',p_report.created_at,'status',p_report.status);
$$;

create function awaaz_private.community_command(p_actor uuid,p_op text,p_data jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_report public.report_submissions;
  v_command awaaz_private.report_commands;
  v_id uuid;
  v_request uuid;
  v_hash text;
  v_category text;
  v_description text;
  v_lat double precision;
  v_lon double precision;
  v_observed timestamptz;
  v_limit integer;
  v_before_time timestamptz;
  v_before_id uuid;
  v_items jsonb;
  v_next jsonb;
  v_south double precision;
  v_west double precision;
  v_north double precision;
  v_east double precision;
begin
  perform awaaz_private.require_profile(p_actor);
  if p_op='create_report' then
    if not exists(select 1 from auth.users where id=p_actor and phone_confirmed_at is not null) then
      raise exception using errcode='P0001',message='verification_required';
    end if;
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_actor::text,0));
    v_request:=(p_data->>'clientRequestId')::uuid; v_hash:=p_data->>'payloadHash';
    if v_request is null or v_hash is null or v_hash !~ '^[0-9a-f]{64}$' then raise exception using errcode='P0001',message='invalid_request'; end if;
    select * into v_command from awaaz_private.report_commands where actor_id=p_actor and client_request_id=v_request;
    if found then
      if v_command.payload_hash<>v_hash then raise exception using errcode='P0001',message='idempotency_conflict'; end if;
      select * into v_report from public.report_submissions where id=v_command.report_id and owner_id=p_actor;
      return jsonb_build_object('id',v_command.report_id,'status',coalesce(v_report.status,'withdrawn'),'replayed',true);
    end if;
    v_category:=p_data->>'category'; v_description:=btrim(p_data->>'description');
    v_lat:=(p_data->>'latitude')::double precision; v_lon:=(p_data->>'longitude')::double precision;
    v_observed:=(p_data->>'observedAt')::timestamptz;
    if v_category is null or v_category not in ('obstruction','lighting','theft','harassment','accident','other')
      or v_description is null or char_length(v_description) not between 10 and 700 or v_observed is null
      or v_observed>now()+interval '5 minutes' or v_observed<now()-interval '72 hours' then
      raise exception using errcode='P0001',message='invalid_report';
    end if;
    if v_lat is null or v_lon is null or not(v_lat between 23.62 and 24.02 and v_lon between 90.20 and 90.58) then
      raise exception using errcode='P0001',message='outside_pilot';
    end if;
    perform awaaz_private.take_quota(p_actor,'report',20);
    insert into public.report_submissions(owner_id,client_request_id,category,description,location,observed_at,payload_hash)
      values(p_actor,v_request,v_category,v_description,
        extensions.st_setsrid(extensions.st_makepoint(v_lon,v_lat),4326)::extensions.geography,v_observed,v_hash)
      returning * into v_report;
    insert into awaaz_private.report_commands(actor_id,client_request_id,report_id,payload_hash)
      values(p_actor,v_request,v_report.id,v_hash);
    return jsonb_build_object('id',v_report.id,'status',v_report.status,'replayed',false);
  elsif p_op='list_own_reports' then
    v_limit:=(p_data->>'limit')::integer;
    if v_limit is null or v_limit not between 1 and 100 then raise exception using errcode='P0001',message='invalid_request'; end if;
    v_before_time:=(p_data->'before'->>'createdAt')::timestamptz;
    v_before_id:=(p_data->'before'->>'id')::uuid;
    if (v_before_time is null)<>(v_before_id is null) then raise exception using errcode='P0001',message='invalid_cursor'; end if;
    select coalesce(jsonb_agg(x.item order by x.created_at desc,x.id desc),'[]'::jsonb) into v_items from (
      select r.id,r.created_at,awaaz_private.report_json(r) item from public.report_submissions r
      where r.owner_id=p_actor and (v_before_time is null or (r.created_at,r.id)<(v_before_time,v_before_id))
      order by r.created_at desc,r.id desc limit v_limit+1
    ) x;
    v_next:='null'::jsonb;
    if jsonb_array_length(v_items)>v_limit then
      v_next:=jsonb_build_object('createdAt',v_items->(v_limit-1)->>'createdAt','id',v_items->(v_limit-1)->>'id');
      v_items:=v_items-v_limit;
    end if;
    return jsonb_build_object('items',v_items,'next',v_next);
  elsif p_op='withdraw_report' then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_actor::text,0));
    v_id:=(p_data->>'id')::uuid;
    select * into v_command from awaaz_private.report_commands where actor_id=p_actor and report_id=v_id;
    if not found then raise exception using errcode='P0001',message='not_found'; end if;
    -- FK cascade removes any published event in the same transaction. Derived
    -- risk-overlay invalidation belongs to the upcoming snapshot publisher.
    delete from public.report_submissions where id=v_id and owner_id=p_actor;
    return jsonb_build_object('id',v_id,'status','withdrawn');
  elsif p_op='list_published_events' then
    v_limit:=(p_data->>'limit')::integer;
    v_south:=(p_data->>'south')::double precision; v_west:=(p_data->>'west')::double precision;
    v_north:=(p_data->>'north')::double precision; v_east:=(p_data->>'east')::double precision;
    if v_limit is null or v_limit not between 1 and 100 or v_south is null or v_west is null or v_north is null or v_east is null
      or not(v_south>=-90 and v_north<=90 and v_west>=-180 and v_east<=180
        and v_south<v_north and v_west<v_east and v_north-v_south<=0.6 and v_east-v_west<=0.6) then
      raise exception using errcode='P0001',message='invalid_bounds';
    end if;
    select coalesce(jsonb_agg(x.item order by x.published_at desc,x.id),'[]'::jsonb) into v_items from (
      select e.id,e.published_at,jsonb_build_object('id',e.id,'category',e.category,'roadSegmentId',e.road_segment_id,
        'summary',e.public_summary,'latitude',round(extensions.st_y(e.centroid::extensions.geometry)::numeric,3),
        'longitude',round(extensions.st_x(e.centroid::extensions.geometry)::numeric,3),
        'observedAt',e.observed_at,'expiresAt',e.expires_at,'publishedAt',e.published_at) item
      from public.road_events e where e.expires_at>now() and e.published_at<=now()
        and e.centroid operator(extensions.&&) extensions.st_makeenvelope(v_west,v_south,v_east,v_north,4326)::extensions.geography
      order by e.published_at desc,e.id limit v_limit
    ) x;
    return jsonb_build_object('items',v_items);
  end if;
  raise exception using errcode='P0001',message='invalid_request';
end $$;
revoke all on function awaaz_private.report_json(public.report_submissions),
  awaaz_private.community_command(uuid,text,jsonb) from public,anon,authenticated,service_role,awaaz_api;
grant execute on function awaaz_private.community_command(uuid,text,jsonb) to awaaz_api;
-- Payload removal goes through the API operation, preserving retry tombstones.
revoke delete on public.report_submissions from authenticated;
revoke all on public.profiles,public.report_submissions,public.road_events,
  public.risk_snapshots,public.edge_risk,public.incidents,public.notification_outbox from awaaz_api;
commit;
