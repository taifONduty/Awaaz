begin;

-- A membership that was revoked and reaccepted is a new consent context.
alter table public.circle_members add column consent_epoch uuid not null default gen_random_uuid();
create function awaaz_private.rotate_membership_consent() returns trigger
language plpgsql set search_path='' as $$
begin
  if new.revoked_at is distinct from old.revoked_at or new.joined_at is distinct from old.joined_at then
    new.consent_epoch:=gen_random_uuid();
  else new.consent_epoch:=old.consent_epoch; end if;
  return new;
end $$;
create trigger circle_members_consent before update on public.circle_members
  for each row execute function awaaz_private.rotate_membership_consent();

create table awaaz_private.trip_shares (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  client_request_id uuid not null,
  payload_hash text not null check(payload_hash ~ '^[0-9a-f]{64}$'),
  circle_id uuid references public.circles(id) on delete set null,
  created_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null,
  ended_at timestamptz,
  sequence integer not null default 0 check(sequence between 0 and 2147483646),
  last_captured_at timestamptz,
  last_accepted_at timestamptz,
  unique(owner_id,client_request_id),
  check(expires_at>=created_at+interval '5 minutes' and expires_at<=created_at+interval '2 hours'),
  check(ended_at is null or ended_at>=created_at)
);
create index trip_shares_owner_active on awaaz_private.trip_shares(owner_id,expires_at) where ended_at is null;
create table awaaz_private.trip_share_grants (
  share_id uuid not null references awaaz_private.trip_shares(id) on delete cascade,
  circle_id uuid not null references public.circles(id) on delete cascade,
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  owner_epoch uuid not null,
  recipient_epoch uuid not null,
  revoked_at timestamptz,
  primary key(share_id,recipient_id)
);
create index trip_grants_incoming on awaaz_private.trip_share_grants(recipient_id,share_id) where revoked_at is null;
create index trip_grants_circle on awaaz_private.trip_share_grants(circle_id) where revoked_at is null;
create table awaaz_private.trip_share_positions (
  share_id uuid primary key references awaaz_private.trip_shares(id) on delete cascade,
  sequence integer not null check(sequence between 1 and 2147483646),
  payload_hash text not null check(payload_hash ~ '^[0-9a-f]{64}$'),
  latitude double precision not null check(latitude between 23.62 and 24.02),
  longitude double precision not null check(longitude between 90.20 and 90.58),
  accuracy_metres double precision not null check(accuracy_metres between 1 and 100),
  captured_at timestamptz not null,
  accepted_at timestamptz not null,
  purge_at timestamptz not null,
  check(captured_at>=accepted_at-interval '30 seconds' and captured_at<=accepted_at+interval '5 seconds'),
  check(purge_at<=accepted_at+interval '90 seconds')
);
create index trip_positions_expiry on awaaz_private.trip_share_positions(purge_at);
alter table awaaz_private.trip_shares enable row level security;
alter table awaaz_private.trip_share_grants enable row level security;
alter table awaaz_private.trip_share_positions enable row level security;
revoke all on awaaz_private.trip_shares,awaaz_private.trip_share_grants,awaaz_private.trip_share_positions
  from public,anon,authenticated,service_role,awaaz_api,awaaz_evidence;
alter table awaaz_private.account_quotas drop constraint account_quotas_kind_check;
alter table awaaz_private.account_quotas add constraint account_quotas_kind_check
  check(kind in ('report','circle','invite','block','share'));

create function awaaz_private.share_grant_live(p_grant awaaz_private.trip_share_grants) returns boolean
language sql stable set search_path='' as $$
  select p_grant.revoked_at is null and exists(
    select 1 from awaaz_private.trip_shares s
    join public.circles c on c.id=s.circle_id and c.id=p_grant.circle_id
    join public.circle_members a on a.circle_id=c.id and a.user_id=s.owner_id
    join public.circle_members b on b.circle_id=c.id and b.user_id=p_grant.recipient_id
    where s.id=p_grant.share_id and s.ended_at is null and s.expires_at>statement_timestamp()
      and c.closed_at is null and a.revoked_at is null and b.revoked_at is null
      and a.consent_epoch=p_grant.owner_epoch and b.consent_epoch=p_grant.recipient_epoch
      and not awaaz_private.blocked_pair(s.owner_id,p_grant.recipient_id));
$$;
create function awaaz_private.share_control(p_owner uuid,p_share uuid) returns jsonb
language sql stable set search_path='' as $$
  select jsonb_build_object('id',s.id,'circleId',s.circle_id,'startedAt',s.created_at,'expiresAt',s.expires_at,
    'status',case when s.ended_at is not null then 'stopped' when s.expires_at<=statement_timestamp() then 'expired' else 'active' end,
    'sequence',s.sequence,'recipients',coalesce((select jsonb_agg(jsonb_build_object('userId',g.recipient_id,
      'active',awaaz_private.share_grant_live(g)) order by g.recipient_id)
      from awaaz_private.trip_share_grants g where g.share_id=s.id),'[]'::jsonb))
    from awaaz_private.trip_shares s where s.id=p_share and s.owner_id=p_owner;
$$;
create function awaaz_private.share_view(p_actor uuid,p_share uuid) returns jsonb
language sql stable set search_path='' as $$
  -- Authorization and coordinate selection deliberately share one snapshot.
  select jsonb_build_object('id',s.id,'ownerId',s.owner_id,'ownerName',owner.display_name,
    'expiresAt',s.expires_at,'serverTime',statement_timestamp(),
    'lastUpdatedAt',coalesce(p.captured_at,s.last_captured_at),'freshness',case when p.share_id is null and s.sequence=0 then 'waiting'
      when p.purge_at>statement_timestamp() then 'fresh' else 'stale' end,
    'location',case when p.purge_at>statement_timestamp() then jsonb_build_object('latitude',p.latitude,
      'longitude',p.longitude,'accuracyMetres',p.accuracy_metres,'capturedAt',p.captured_at,'expiresAt',p.purge_at) end)
    from awaaz_private.trip_shares s join public.profiles owner on owner.id=s.owner_id
    left join awaaz_private.trip_share_positions p on p.share_id=s.id
    where s.id=p_share and s.ended_at is null and s.expires_at>statement_timestamp() and
      ((s.owner_id=p_actor and exists(select 1 from awaaz_private.trip_share_grants g
          where g.share_id=s.id and awaaz_private.share_grant_live(g)))
       or exists(select 1 from awaaz_private.trip_share_grants g where g.share_id=s.id
          and g.recipient_id=p_actor and awaaz_private.share_grant_live(g)));
$$;

-- These triggers only revoke grants. They never lock a session after a grant,
-- preserving the account -> circle -> session -> grant mutation ordering.
create function awaaz_private.revoke_membership_shares() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if new.consent_epoch is distinct from old.consent_epoch then
    update awaaz_private.trip_share_grants g set revoked_at=coalesce(g.revoked_at,clock_timestamp())
      from awaaz_private.trip_shares s where s.id=g.share_id and g.circle_id=old.circle_id
        and (g.recipient_id=old.user_id or s.owner_id=old.user_id) and g.revoked_at is null;
  end if;
  return new;
end $$;
create trigger circle_members_revoke_shares after update on public.circle_members
  for each row execute function awaaz_private.revoke_membership_shares();
create function awaaz_private.revoke_closed_circle_shares() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if new.closed_at is not null then
    update awaaz_private.trip_share_grants set revoked_at=coalesce(revoked_at,clock_timestamp())
      where circle_id=new.id and revoked_at is null;
  end if;
  return new;
end $$;
create trigger circles_revoke_shares after update of closed_at on public.circles
  for each row execute function awaaz_private.revoke_closed_circle_shares();
create function awaaz_private.revoke_blocked_shares() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if new.blocked then
    update awaaz_private.trip_share_grants g set revoked_at=coalesce(g.revoked_at,clock_timestamp())
      from awaaz_private.trip_shares s where s.id=g.share_id and g.revoked_at is null and
        ((s.owner_id=new.blocker_id and g.recipient_id=new.target_id)
          or (s.owner_id=new.target_id and g.recipient_id=new.blocker_id));
  end if;
  return new;
end $$;
create trigger contact_blocks_revoke_shares after insert or update of blocked on awaaz_private.user_block_settings
  for each row execute function awaaz_private.revoke_blocked_shares();

create function awaaz_private.sharing_command(p_actor uuid,p_op text,p_data jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_share awaaz_private.trip_shares;
  v_point awaaz_private.trip_share_positions;
  v_id uuid:=(p_data->>'shareId')::uuid;
  v_owner uuid;
  v_circle uuid;
  v_recipient uuid;
  v_recipients uuid[];
  v_actor uuid;
  v_owner_epoch uuid;
  v_request uuid;
  v_hash text;
  v_seconds integer;
  v_sequence integer;
  v_captured timestamptz;
  v_now timestamptz;
  v_after uuid;
  v_limit integer;
  v_result jsonb;
begin
  if p_actor is null or not exists(select 1 from auth.users where id=p_actor) then
    raise exception using errcode='P0001',message='unauthenticated';
  end if;
  perform awaaz_private.require_profile(p_actor);
  if p_op='create' then
    if jsonb_typeof(p_data->'recipientIds') is distinct from 'array' then
      raise exception using errcode='P0001',message='invalid_request'; end if;
    select array_agg(value::uuid order by value::uuid) into v_recipients
      from jsonb_array_elements_text(p_data->'recipientIds');
    v_seconds:=(p_data->>'durationSeconds')::integer;
    v_circle:=(p_data->>'circleId')::uuid; v_request:=(p_data->>'clientRequestId')::uuid;
    v_hash:=p_data->>'payloadHash';
    if v_circle is null or v_request is null or v_hash is null or v_hash!~'^[0-9a-f]{64}$'
      or v_seconds is null or v_seconds not between 300 and 7200
      or coalesce(cardinality(v_recipients),0) not between 1 and 10
      or (select count(distinct x) from unnest(v_recipients) x)<>cardinality(v_recipients)
      or p_actor=any(v_recipients) then raise exception using errcode='P0001',message='invalid_request'; end if;
    for v_actor in select distinct x from unnest(array_append(v_recipients,p_actor)) x order by x loop
      perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_actor::text,0));
    end loop;
    select * into v_share from awaaz_private.trip_shares where owner_id=p_actor and client_request_id=v_request;
    if found then
      if v_share.payload_hash<>v_hash then raise exception using errcode='P0001',message='idempotency_conflict'; end if;
      return awaaz_private.share_control(p_actor,v_share.id)||jsonb_build_object('replayed',true);
    end if;
    perform 1 from public.circles where id=v_circle and closed_at is null for update;
    if not found then raise exception using errcode='P0001',message='not_found'; end if;
    select consent_epoch into v_owner_epoch from public.circle_members
      where circle_id=v_circle and user_id=p_actor and revoked_at is null;
    if not found then raise exception using errcode='P0001',message='not_found'; end if;
    foreach v_recipient in array v_recipients loop
      if not exists(select 1 from public.circle_members where circle_id=v_circle and user_id=v_recipient
        and revoked_at is null) or awaaz_private.blocked_pair(p_actor,v_recipient) then
        raise exception using errcode='P0001',message='share_recipient_unavailable'; end if;
    end loop;
    v_now:=clock_timestamp();
    if exists(select 1 from awaaz_private.trip_shares where owner_id=p_actor and ended_at is null and expires_at>v_now) then
      raise exception using errcode='P0001',message='share_already_active'; end if;
    perform awaaz_private.take_quota(p_actor,'share',20);
    insert into awaaz_private.trip_shares(owner_id,client_request_id,payload_hash,circle_id,created_at,expires_at)
      values(p_actor,v_request,v_hash,v_circle,v_now,v_now+v_seconds*interval '1 second') returning * into v_share;
    insert into awaaz_private.trip_share_grants(share_id,circle_id,recipient_id,owner_epoch,recipient_epoch)
      select v_share.id,v_circle,m.user_id,v_owner_epoch,m.consent_epoch from public.circle_members m
        where m.circle_id=v_circle and m.user_id=any(v_recipients) and m.revoked_at is null;
    return awaaz_private.share_control(p_actor,v_share.id)||jsonb_build_object('replayed',false);
  elsif p_op='current' then
    select id into v_id from awaaz_private.trip_shares where owner_id=p_actor and ended_at is null
      and expires_at>statement_timestamp() order by created_at desc limit 1;
    return jsonb_build_object('share',awaaz_private.share_control(p_actor,v_id));
  elsif p_op='request' then
    select id into v_id from awaaz_private.trip_shares where owner_id=p_actor
      and client_request_id=(p_data->>'clientRequestId')::uuid;
    if not found then raise exception using errcode='P0001',message='not_found'; end if;
    return awaaz_private.share_control(p_actor,v_id);
  elsif p_op='view' then
    v_result:=awaaz_private.share_view(p_actor,v_id);
    if v_result is null then raise exception using errcode='P0001',message='not_found'; end if;
    return v_result;
  elsif p_op='incoming' then
    v_limit:=coalesce((p_data->>'limit')::integer,30); v_after:=(p_data->>'after')::uuid;
    if v_limit not between 1 and 50 then raise exception using errcode='P0001',message='invalid_request'; end if;
    with page as materialized (
      select s.id,s.expires_at,p.display_name from awaaz_private.trip_share_grants g
        join awaaz_private.trip_shares s on s.id=g.share_id join public.profiles p on p.id=s.owner_id
        where g.recipient_id=p_actor and awaaz_private.share_grant_live(g)
          and (v_after is null or s.id>v_after) order by s.id limit v_limit+1
    ), visible as (select * from page order by id limit v_limit)
    select jsonb_build_object('items',coalesce((select jsonb_agg(jsonb_build_object('id',id,
      'ownerName',display_name,'expiresAt',expires_at) order by id) from visible),'[]'::jsonb),
      'nextCursor',case when (select count(*) from page)>v_limit then (select id from visible order by id desc limit 1) end)
      into v_result;
    return v_result;
  elsif p_op not in ('position','stop','revoke') or v_id is null then
    raise exception using errcode='P0001',message='invalid_request';
  end if;

  select owner_id into v_owner from awaaz_private.trip_shares where id=v_id;
  if not found then raise exception using errcode='P0001',message='not_found'; end if;
  v_recipient:=(p_data->>'recipientId')::uuid;
  if (p_op<>'revoke' and v_owner<>p_actor) or
    (p_op='revoke' and (v_recipient is null or (v_owner<>p_actor and v_recipient<>p_actor))) then
    raise exception using errcode='P0001',message='not_found'; end if;
  for v_actor in select distinct x from unnest(array[p_actor,v_owner]) x order by x loop
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_actor::text,0));
  end loop;
  select * into v_share from awaaz_private.trip_shares where id=v_id for update;
  v_now:=clock_timestamp();
  if p_op='stop' then
    update awaaz_private.trip_shares set ended_at=coalesce(ended_at,v_now),circle_id=null,
      last_captured_at=null,last_accepted_at=null where id=v_id;
    delete from awaaz_private.trip_share_positions where share_id=v_id;
    delete from awaaz_private.trip_share_grants where share_id=v_id;
    return awaaz_private.share_control(p_actor,v_id);
  elsif p_op='revoke' then
    update awaaz_private.trip_share_grants set revoked_at=coalesce(revoked_at,v_now)
      where share_id=v_id and recipient_id=v_recipient;
    if not found then raise exception using errcode='P0001',message='not_found'; end if;
    if not exists(select 1 from awaaz_private.trip_share_grants g where g.share_id=v_id and awaaz_private.share_grant_live(g)) then
      delete from awaaz_private.trip_share_positions where share_id=v_id;
    end if;
    return jsonb_build_object('shareId',v_id,'userId',v_recipient,'status','revoked');
  end if;
  if v_share.ended_at is not null or v_share.expires_at<=v_now or
    not exists(select 1 from awaaz_private.trip_share_grants g where g.share_id=v_id and awaaz_private.share_grant_live(g)) then
    raise exception using errcode='P0001',message='share_unavailable'; end if;
  v_sequence:=(p_data->>'sequence')::integer; v_hash:=p_data->>'payloadHash';
  v_captured:=(p_data->>'capturedAt')::timestamptz;
  if v_sequence is null or v_sequence not between 1 and 2147483646 or v_hash is null or v_hash!~'^[0-9a-f]{64}$' then
    raise exception using errcode='P0001',message='invalid_request'; end if;
  if v_sequence<=v_share.sequence then
    select * into v_point from awaaz_private.trip_share_positions where share_id=v_id;
    if v_sequence=v_share.sequence and found and v_point.payload_hash=v_hash and v_point.purge_at>v_now then
      return jsonb_build_object('shareId',v_id,'sequence',v_sequence,'acceptedAt',v_point.accepted_at,
        'expiresAt',v_point.purge_at,'replayed',true);
    end if;
    raise exception using errcode='P0001',message='stale_position';
  end if;
  if v_captured is null or v_captured<v_now-interval '30 seconds' or v_captured>v_now+interval '5 seconds'
    or (v_share.last_captured_at is not null and v_captured<=v_share.last_captured_at) then
    raise exception using errcode='P0001',message='stale_position'; end if;
  if v_share.last_accepted_at>v_now-interval '5 seconds' then
    raise exception using errcode='P0001',message='rate_limited'; end if;
  insert into awaaz_private.trip_share_positions(share_id,sequence,payload_hash,latitude,longitude,
    accuracy_metres,captured_at,accepted_at,purge_at) values(v_id,v_sequence,v_hash,
    (p_data->>'latitude')::double precision,(p_data->>'longitude')::double precision,
    (p_data->>'accuracyMetres')::double precision,v_captured,v_now,least(v_captured+interval '90 seconds',v_now+interval '90 seconds',v_share.expires_at))
    on conflict(share_id) do update set sequence=excluded.sequence,payload_hash=excluded.payload_hash,
      latitude=excluded.latitude,longitude=excluded.longitude,accuracy_metres=excluded.accuracy_metres,
      captured_at=excluded.captured_at,accepted_at=excluded.accepted_at,purge_at=excluded.purge_at;
  update awaaz_private.trip_shares set sequence=v_sequence,last_captured_at=v_captured,last_accepted_at=v_now where id=v_id;
  return jsonb_build_object('shareId',v_id,'sequence',v_sequence,'acceptedAt',v_now,
    'expiresAt',least(v_captured+interval '90 seconds',v_now+interval '90 seconds',v_share.expires_at),'replayed',false);
end $$;

-- No arbitrary SQL/IDs/retention override can be supplied through this grant.
create function awaaz_private.cleanup_trip_sharing() returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_points integer; v_grants integer; v_ids uuid[];
begin
  -- Lock sessions before positions/grants, matching uploads and stop. Locking
  -- a point first and later its session would deadlock against an uploader.
  select array_agg(id) into v_ids from (select s.id from awaaz_private.trip_shares s
    left join awaaz_private.trip_share_positions p on p.share_id=s.id
    where (p.share_id is not null and (p.purge_at<=statement_timestamp() or s.ended_at is not null
      or s.expires_at<=statement_timestamp() or not exists(select 1 from awaaz_private.trip_share_grants g
        where g.share_id=s.id and awaaz_private.share_grant_live(g))))
      or ((s.ended_at is not null or s.expires_at<=statement_timestamp()) and
        (s.circle_id is not null or s.last_captured_at is not null or s.last_accepted_at is not null
          or exists(select 1 from awaaz_private.trip_share_grants g where g.share_id=s.id)))
    order by coalesce(p.purge_at,s.expires_at),s.id limit 500 for update of s skip locked) q;
  delete from awaaz_private.trip_share_positions p using awaaz_private.trip_shares s
    where p.share_id=s.id and s.id=any(v_ids) and (p.purge_at<=statement_timestamp()
      or s.ended_at is not null or s.expires_at<=statement_timestamp()
      or not exists(select 1 from awaaz_private.trip_share_grants g where g.share_id=s.id and awaaz_private.share_grant_live(g)));
  get diagnostics v_points=row_count;
  delete from awaaz_private.trip_share_grants g using awaaz_private.trip_shares s
    where g.share_id=s.id and s.id=any(v_ids) and (s.ended_at is not null or s.expires_at<=statement_timestamp());
  get diagnostics v_grants=row_count;
  update awaaz_private.trip_shares set circle_id=null,last_captured_at=null,last_accepted_at=null
    where id=any(v_ids) and (ended_at is not null or expires_at<=statement_timestamp());
  return jsonb_build_object('positionsDeleted',v_points,'grantsDeleted',v_grants);
end $$;

revoke all on function awaaz_private.rotate_membership_consent(),awaaz_private.share_grant_live(awaaz_private.trip_share_grants),
  awaaz_private.share_control(uuid,uuid),awaaz_private.share_view(uuid,uuid),awaaz_private.revoke_membership_shares(),
  awaaz_private.revoke_closed_circle_shares(),awaaz_private.revoke_blocked_shares(),
  awaaz_private.sharing_command(uuid,text,jsonb),awaaz_private.cleanup_trip_sharing()
  from public,anon,authenticated,service_role,awaaz_api,awaaz_evidence;
grant execute on function awaaz_private.sharing_command(uuid,text,jsonb),awaaz_private.cleanup_trip_sharing() to awaaz_api;
commit;
