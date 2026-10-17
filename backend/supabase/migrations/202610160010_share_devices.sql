begin;

-- One immutable device binding per consent. The native client creates a
-- 256-bit random secret; only its domain-separated SHA-256 digest is stored.
-- Revoking a binding cannot be undone. A different device needs a new share.
create table awaaz_private.trip_share_devices (
  share_id uuid primary key references awaaz_private.trip_shares(id) on delete cascade,
  credential_hash text unique check(credential_hash ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default clock_timestamp(),
  revoked_at timestamptz,
  check(credential_hash is not null or revoked_at is not null)
);
revoke all on awaaz_private.trip_share_devices from public,anon,authenticated,service_role,awaaz_api,awaaz_evidence;

create function awaaz_private.share_device_control(p_id uuid) returns jsonb
language sql stable security definer set search_path='' as $$
  select jsonb_build_object('shareId',s.id,'expiresAt',s.expires_at,'serverTime',statement_timestamp(),
    'sequence',s.sequence,'status',case
      when s.ended_at is not null then 'stopped'
      when s.expires_at<=statement_timestamp() then 'expired'
      when d.revoked_at is not null then 'revoked'
      when d.share_id is null then 'unbound'
      when not exists(select 1 from awaaz_private.trip_share_grants g
        where g.share_id=s.id and awaaz_private.share_grant_live(g)) then 'revoked'
      else 'active' end)
    from awaaz_private.trip_shares s left join awaaz_private.trip_share_devices d on d.share_id=s.id
    where s.id=p_id;
$$;

create function awaaz_private.share_device_owner(p_actor uuid,p_id uuid,p_op text,p_hash text default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_share awaaz_private.trip_shares; v_device awaaz_private.trip_share_devices; v_now timestamptz;
begin
  if p_actor is null or not exists(select 1 from auth.users where id=p_actor) then
    raise exception using errcode='P0001',message='unauthenticated'; end if;
  perform awaaz_private.require_profile(p_actor);
  if p_op not in ('bind','revoke','state') or p_id is null then
    raise exception using errcode='P0001',message='invalid_request'; end if;
  if p_op='bind' and (p_hash is null or p_hash !~ '^[0-9a-f]{64}$') then
    raise exception using errcode='P0001',message='invalid_request'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_actor::text,0));
  select * into v_share from awaaz_private.trip_shares where id=p_id and owner_id=p_actor for update;
  if not found then raise exception using errcode='P0001',message='not_found'; end if;
  select * into v_device from awaaz_private.trip_share_devices where share_id=p_id;
  if p_op='state' then return awaaz_private.share_device_control(p_id); end if;
  v_now:=clock_timestamp();
  if p_op='revoke' then
    -- A tombstone also blocks a delayed first bind from undoing revocation.
    insert into awaaz_private.trip_share_devices(share_id,revoked_at) values(p_id,v_now)
      on conflict(share_id) do update set revoked_at=coalesce(awaaz_private.trip_share_devices.revoked_at,excluded.revoked_at);
    return awaaz_private.share_device_control(p_id);
  end if;
  if v_device.share_id is not null then
    if v_device.credential_hash is distinct from p_hash then
      raise exception using errcode='P0001',message='device_already_bound'; end if;
    -- Identical retries return terminal receipts; they never renew a lease.
    return awaaz_private.share_device_control(p_id);
  end if;
  if v_share.ended_at is not null or v_share.expires_at<=v_now or not exists(
    select 1 from awaaz_private.trip_share_grants g where g.share_id=p_id and awaaz_private.share_grant_live(g)) then
    raise exception using errcode='P0001',message='share_unavailable'; end if;
  insert into awaaz_private.trip_share_devices(share_id,credential_hash) values(p_id,p_hash);
  return awaaz_private.share_device_control(p_id);
exception when unique_violation then
  raise exception using errcode='P0001',message='device_already_bound';
end $$;

-- Binding chooses one publisher for this consent. JWT clients may reconcile an
-- identical already-accepted point, but cannot race a native device with a new
-- sample. Owner device revocation restores foreground publishing, permanently.
alter function awaaz_private.sharing_command(uuid,text,jsonb) rename to sharing_command_before_devices;
revoke all on function awaaz_private.sharing_command_before_devices(uuid,text,jsonb)
  from public,anon,authenticated,service_role,awaaz_api,awaaz_evidence;
create function awaaz_private.sharing_command(p_actor uuid,p_op text,p_data jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
  if p_op='position' and p_actor is not null then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_actor::text,0));
    if exists(select 1 from awaaz_private.trip_shares s join awaaz_private.trip_share_devices d on d.share_id=s.id
      where s.id=(p_data->>'shareId')::uuid and s.owner_id=p_actor and s.ended_at is null
        and s.expires_at>clock_timestamp() and d.revoked_at is null
        and s.sequence<(p_data->>'sequence')::integer
        and exists(select 1 from awaaz_private.trip_share_grants g where g.share_id=s.id and awaaz_private.share_grant_live(g))) then
      raise exception using errcode='P0001',message='native_publisher_active';
    end if;
  end if;
  return awaaz_private.sharing_command_before_devices(p_actor,p_op,p_data);
end $$;
revoke all on function awaaz_private.sharing_command(uuid,text,jsonb)
  from public,anon,authenticated,service_role,awaaz_api,awaaz_evidence;
grant execute on function awaaz_private.sharing_command(uuid,text,jsonb) to awaaz_api;

create function awaaz_private.share_device_command(p_hash text,p_id uuid,p_op text,p_data jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_owner uuid; v_share awaaz_private.trip_shares; v_device awaaz_private.trip_share_devices; v_now timestamptz; v_result jsonb;
begin
  if p_hash is null or p_hash !~ '^[0-9a-f]{64}$' or p_id is null then
    raise exception using errcode='P0001',message='unauthenticated'; end if;
  select s.owner_id into v_owner from awaaz_private.trip_shares s
    join awaaz_private.trip_share_devices d on d.share_id=s.id
    where s.id=p_id and d.credential_hash=p_hash;
  if not found then raise exception using errcode='P0001',message='unauthenticated'; end if;
  if p_op not in ('state','position','stop') then
    raise exception using errcode='P0001',message='invalid_request'; end if;
  -- State authentication and minimal receipt selection share one snapshot.
  if p_op='state' then
    select awaaz_private.share_device_control(s.id) into v_result from awaaz_private.trip_shares s
      join awaaz_private.trip_share_devices d on d.share_id=s.id
      where s.id=p_id and d.credential_hash=p_hash;
    if v_result is null then raise exception using errcode='P0001',message='unauthenticated'; end if;
    return v_result;
  end if;
  -- Same account -> session -> dependent-row order as owner uploads and stop.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_owner::text,0));
  select * into v_share from awaaz_private.trip_shares where id=p_id for update;
  if not found then raise exception using errcode='P0001',message='unauthenticated'; end if;
  select * into v_device from awaaz_private.trip_share_devices where share_id=p_id and credential_hash=p_hash;
  if not found then raise exception using errcode='P0001',message='unauthenticated'; end if;
  v_now:=clock_timestamp();
  if p_op='stop' and (v_share.ended_at is not null or v_share.expires_at<=v_now) then
    return awaaz_private.share_device_control(p_id);
  end if;
  if v_device.revoked_at is not null then
    raise exception using errcode='P0001',message='device_revoked'; end if;
  if p_op='stop' then
    -- Erasure remains possible after profile access changes; it grants no read.
    update awaaz_private.trip_shares set ended_at=coalesce(ended_at,v_now),circle_id=null,
      last_captured_at=null,last_accepted_at=null where id=p_id;
    delete from awaaz_private.trip_share_positions where share_id=p_id;
    delete from awaaz_private.trip_share_grants where share_id=p_id;
    return awaaz_private.share_device_control(p_id);
  end if;
  -- Reuse all existing membership/epoch/block/expiry, precision, time, sequence
  -- and replay rules. The actor and target are resolved here, never by HTTP.
  return awaaz_private.sharing_command_before_devices(v_owner,'position',p_data||jsonb_build_object('shareId',p_id));
end $$;

revoke all on function awaaz_private.share_device_control(uuid),
  awaaz_private.share_device_owner(uuid,uuid,text,text),awaaz_private.share_device_command(text,uuid,text,jsonb)
  from public,anon,authenticated,service_role,awaaz_api,awaaz_evidence;
grant execute on function awaaz_private.share_device_owner(uuid,uuid,text,text),
  awaaz_private.share_device_command(text,uuid,text,jsonb) to awaaz_api;
commit;
