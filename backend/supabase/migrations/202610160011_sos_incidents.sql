begin;

-- Receiving help requests is a separate decision from joining a Circle.
create table awaaz_private.sos_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  allowed boolean not null default false,
  version integer not null default 0 check(version between 0 and 2147483646),
  consent_epoch uuid not null default gen_random_uuid(),
  changed_at timestamptz not null default clock_timestamp()
);
-- A cancellation can win before a delayed create reaches the server. Retain
-- only the owner/nonce tombstone, so that old intent cannot later activate.
create table awaaz_private.sos_request_cancellations (
  owner_id uuid not null references auth.users(id) on delete cascade,
  client_request_id uuid not null,
  cancelled_at timestamptz not null default clock_timestamp(),
  primary key(owner_id,client_request_id)
);
alter table public.incidents add column circle_id uuid references public.circles(id) on delete set null;
alter table public.incidents add column payload_hash text not null default repeat('0',64) check(payload_hash ~ '^[0-9a-f]{64}$');
alter table public.incidents alter column payload_hash drop default;
alter table public.incidents add column expires_at timestamptz not null default clock_timestamp()+interval '1 hour';
alter table public.incidents add column version integer not null default 1 check(version between 1 and 2147483646);
alter table public.incidents add column mode text not null default 'silent' check(mode in ('silent','audible'));
alter table public.incidents add column share_location boolean not null default false;
alter table public.incidents add column sequence integer not null default 0 check(sequence between 0 and 2147483646);
alter table public.incidents add column last_position_accepted_at timestamptz;
alter table public.incidents drop constraint incidents_status_check;
alter table public.incidents add constraint incidents_status_check check(status in ('active','ended','cancelled','expired'));
create unique index incidents_one_active_owner on public.incidents(owner_id) where status='active';
create index incidents_expiry on public.incidents(expires_at) where status='active';
create index incidents_retention_expiry on public.incidents(expires_at);

create table awaaz_private.sos_grants (
  incident_id uuid not null references public.incidents(id) on delete cascade,
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  circle_id uuid not null references public.circles(id) on delete cascade,
  owner_epoch uuid not null,
  recipient_epoch uuid not null,
  preference_epoch uuid not null,
  revoked_at timestamptz,
  response text check(response in ('seen','contacting','helping','unavailable')),
  response_version integer not null default 0 check(response_version between 0 and 2147483646),
  responded_at timestamptz,
  primary key(incident_id,recipient_id)
);
create index sos_incoming on awaaz_private.sos_grants(recipient_id,incident_id) where revoked_at is null;
create index sos_grants_circle on awaaz_private.sos_grants(circle_id) where revoked_at is null;
create table awaaz_private.sos_positions (
  incident_id uuid primary key references public.incidents(id) on delete cascade,
  sequence integer not null check(sequence between 1 and 2147483646),
  payload_hash text not null check(payload_hash ~ '^[0-9a-f]{64}$'),
  latitude double precision not null check(latitude between 23.62 and 24.02),
  longitude double precision not null check(longitude between 90.20 and 90.58),
  accuracy_metres double precision not null check(accuracy_metres between 1 and 100),
  captured_at timestamptz not null,
  accepted_at timestamptz not null,
  purge_at timestamptz not null,
  check(captured_at between accepted_at-interval '30 seconds' and accepted_at+interval '5 seconds'),
  check(purge_at<=accepted_at+interval '90 seconds')
);
create index sos_positions_expiry on awaaz_private.sos_positions(purge_at);
alter table public.notification_outbox add column kind text not null default 'request' check(kind in ('request','resolved','cancelled'));
alter table public.notification_outbox add column incident_version integer not null default 1 check(incident_version>0);
alter table public.notification_outbox add column expires_at timestamptz not null default clock_timestamp()+interval '2 minutes';
alter table public.notification_outbox add column cancelled_at timestamptz;
alter table public.notification_outbox add column lease_until timestamptz;
alter table public.notification_outbox add column lease_token uuid;
alter table public.notification_outbox add column provider_accepted_at timestamptz;
alter table public.notification_outbox add column provider_reference text check(length(provider_reference)<=200);
alter table public.notification_outbox drop constraint notification_outbox_status_check;
alter table public.notification_outbox add constraint notification_outbox_status_check
  check(status in ('queued','sending','provider_accepted','failed','cancelled','expired','unknown'));
create index sos_jobs_incident on public.notification_outbox(incident_id,recipient_id);
create index sos_jobs_expiry on public.notification_outbox(expires_at) where status in ('queued','sending');
create index sos_jobs_retention on public.notification_outbox(created_at);
alter table awaaz_private.sos_preferences enable row level security;
alter table awaaz_private.sos_grants enable row level security;
alter table awaaz_private.sos_positions enable row level security;
alter table awaaz_private.sos_request_cancellations enable row level security;
revoke all on public.incidents,public.notification_outbox,awaaz_private.sos_preferences,
  awaaz_private.sos_grants,awaaz_private.sos_positions,awaaz_private.sos_request_cancellations
  from public,anon,authenticated,service_role,awaaz_api,awaaz_evidence;
alter table awaaz_private.account_quotas drop constraint account_quotas_kind_check;
alter table awaaz_private.account_quotas add constraint account_quotas_kind_check
  check(kind in ('report','circle','invite','block','share','sos','sos_preference','sos_cancel'));

create function awaaz_private.sos_grant_live(p_grant awaaz_private.sos_grants) returns boolean
language sql stable set search_path='' as $$
  select p_grant.revoked_at is null and exists(
    select 1 from public.incidents i
    join public.circles c on c.id=i.circle_id and c.id=p_grant.circle_id
    join public.circle_members a on a.circle_id=c.id and a.user_id=i.owner_id
    join public.circle_members b on b.circle_id=c.id and b.user_id=p_grant.recipient_id
    join awaaz_private.sos_preferences pref on pref.user_id=b.user_id
    join public.profiles owner_profile on owner_profile.id=i.owner_id and owner_profile.adult_attested
    join auth.users owner_auth on owner_auth.id=i.owner_id and owner_auth.phone_confirmed_at is not null
    join public.profiles recipient_profile on recipient_profile.id=b.user_id and recipient_profile.adult_attested
    join auth.users recipient_auth on recipient_auth.id=b.user_id and recipient_auth.phone_confirmed_at is not null
    where i.id=p_grant.incident_id and i.expires_at>statement_timestamp() and c.closed_at is null
      and a.revoked_at is null and b.revoked_at is null and a.consent_epoch=p_grant.owner_epoch
      and b.consent_epoch=p_grant.recipient_epoch and pref.allowed and pref.consent_epoch=p_grant.preference_epoch
      and not awaaz_private.blocked_pair(i.owner_id,p_grant.recipient_id));
$$;
create function awaaz_private.sos_cancel_jobs(p_incident uuid,p_recipient uuid default null) returns void
language sql set search_path='' as $$
  update public.notification_outbox set cancelled_at=coalesce(cancelled_at,clock_timestamp()),
    status=case when status='queued' then 'cancelled' when status='sending' then 'unknown' else status end
    where incident_id=p_incident and (p_recipient is null or recipient_id=p_recipient) and cancelled_at is null;
$$;
create function awaaz_private.sos_grant_changed() returns trigger
language plpgsql security definer set search_path='' as $$
declare v_id uuid; v_recipient uuid;
begin
  if tg_op='UPDATE' and not(old.revoked_at is null and new.revoked_at is not null) then return new; end if;
  v_id:=old.incident_id; v_recipient:=old.recipient_id;
  -- Never lock an incident after a grant: mutations keep account -> incident -> grant ordering.
  if not exists(select 1 from awaaz_private.sos_grants g where g.incident_id=v_id and awaaz_private.sos_grant_live(g)) then
    delete from awaaz_private.sos_positions where incident_id=v_id;
  end if;
  perform awaaz_private.sos_cancel_jobs(v_id,v_recipient);
  if tg_op='DELETE' then return old; end if;
  return new;
end $$;
create trigger sos_grant_revoked after update of revoked_at or delete on awaaz_private.sos_grants
  for each row execute function awaaz_private.sos_grant_changed();
create function awaaz_private.sos_access_changed() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if tg_table_name='circle_members' then
    if new.consent_epoch is distinct from old.consent_epoch then
      update awaaz_private.sos_grants g set revoked_at=clock_timestamp() from public.incidents i
        where i.id=g.incident_id and g.circle_id=old.circle_id and g.revoked_at is null
          and (g.recipient_id=old.user_id or i.owner_id=old.user_id);
    end if;
  elsif tg_table_name='circles' then
    if new.closed_at is not null then update awaaz_private.sos_grants set revoked_at=clock_timestamp()
      where circle_id=new.id and revoked_at is null; end if;
  elsif tg_table_name='sos_preferences' then
    if new.consent_epoch is distinct from old.consent_epoch then
      update awaaz_private.sos_grants set revoked_at=clock_timestamp() where recipient_id=new.user_id and revoked_at is null;
    end if;
  elsif new.blocked then
    update awaaz_private.sos_grants g set revoked_at=clock_timestamp() from public.incidents i
      where i.id=g.incident_id and g.revoked_at is null and
        ((i.owner_id=new.blocker_id and g.recipient_id=new.target_id) or (i.owner_id=new.target_id and g.recipient_id=new.blocker_id));
  end if;
  return new;
end $$;
create trigger circle_members_revoke_sos after update on public.circle_members for each row execute function awaaz_private.sos_access_changed();
create trigger circles_revoke_sos after update of closed_at on public.circles for each row execute function awaaz_private.sos_access_changed();
create trigger preferences_revoke_sos after update on awaaz_private.sos_preferences for each row execute function awaaz_private.sos_access_changed();
create trigger blocks_revoke_sos after insert or update of blocked on awaaz_private.user_block_settings for each row execute function awaaz_private.sos_access_changed();

create function awaaz_private.sos_control(p_owner uuid,p_id uuid) returns jsonb
language sql stable set search_path='' as $$
  select jsonb_build_object('id',i.id,'circleId',i.circle_id,'startedAt',i.started_at,'expiresAt',i.expires_at,
    'serverTime',statement_timestamp(),'status',case when i.status='active' and i.expires_at<=statement_timestamp() then 'expired' else i.status end,
    'version',i.version,'mode',i.mode,'shareLocation',i.share_location,'sequence',i.sequence,
    'recipients',coalesce((select jsonb_agg(jsonb_build_object('userId',g.recipient_id,'active',awaaz_private.sos_grant_live(g),
      'response',g.response,'responseVersion',g.response_version,'respondedAt',g.responded_at,
      'delivery',coalesce((select jsonb_agg(jsonb_build_object('kind',j.kind,'status',case
        when j.expires_at<=statement_timestamp() and j.status='queued' then 'expired'
        when j.expires_at<=statement_timestamp() and j.status='sending' then 'unknown' else j.status end,'attempts',j.attempts,
        'providerAcceptedAt',j.provider_accepted_at,'cancelledAt',j.cancelled_at) order by j.created_at,j.id)
        from public.notification_outbox j where j.incident_id=i.id and j.recipient_id=g.recipient_id),'[]'::jsonb)) order by g.recipient_id)
      from awaaz_private.sos_grants g where g.incident_id=i.id and i.expires_at>statement_timestamp()-interval '24 hours'),'[]'::jsonb))
    from public.incidents i where i.id=p_id and i.owner_id=p_owner;
$$;
create function awaaz_private.sos_view(p_actor uuid,p_id uuid) returns jsonb
language sql stable set search_path='' as $$
  select jsonb_build_object('id',i.id,'ownerId',i.owner_id,'ownerName',p.display_name,'startedAt',i.started_at,
    'expiresAt',i.expires_at,'serverTime',statement_timestamp(),'status',i.status,'version',i.version,
    'response',g.response,'responseVersion',g.response_version,'respondedAt',g.responded_at,
    'location',case when i.status='active' and i.share_location and loc.purge_at>statement_timestamp() then
      jsonb_build_object('latitude',loc.latitude,'longitude',loc.longitude,'accuracyMetres',loc.accuracy_metres,
        'capturedAt',loc.captured_at,'expiresAt',loc.purge_at) end)
    from public.incidents i join public.profiles p on p.id=i.owner_id
    join awaaz_private.sos_grants g on g.incident_id=i.id and g.recipient_id=p_actor
    left join awaaz_private.sos_positions loc on loc.incident_id=i.id
    where i.id=p_id and awaaz_private.sos_grant_live(g);
$$;
create function awaaz_private.sos_finish(p_id uuid,p_status text) returns void
language plpgsql set search_path='' as $$
declare v_incident public.incidents; v_now timestamptz:=clock_timestamp();
begin
  select * into v_incident from public.incidents where id=p_id for update;
  if not found or v_incident.status<>'active' then return; end if;
  if p_status not in ('ended','cancelled','expired') then raise exception using errcode='P0001',message='invalid_request'; end if;
  update public.incidents set status=p_status,ended_at=v_now,version=version+1,share_location=false where id=p_id;
  delete from awaaz_private.sos_positions where incident_id=p_id;
  perform awaaz_private.sos_cancel_jobs(p_id);
  -- Notify only people who may have received the request or explicitly responded.
  -- Queued, never-sent requests can simply be cancelled. Provider acceptance is not delivery.
  if p_status<>'expired' then
    insert into public.notification_outbox(incident_id,recipient_id,idempotency_key,channel,kind,incident_version,expires_at)
      select p_id,g.recipient_id,p_id::text||':'||g.recipient_id::text||':'||p_status||':v1','push',
        case when p_status='ended' then 'resolved' else 'cancelled' end,v_incident.version+1,least(v_incident.expires_at,v_now+interval '2 minutes')
      from awaaz_private.sos_grants g where g.incident_id=p_id and awaaz_private.sos_grant_live(g)
        and (g.response is not null or exists(select 1 from public.notification_outbox j where j.incident_id=p_id
          and j.recipient_id=g.recipient_id and j.kind='request' and (j.status in ('sending','unknown','provider_accepted') or j.provider_accepted_at is not null)))
      on conflict(idempotency_key) do nothing;
  end if;
end $$;

create function awaaz_private.sos_command(p_actor uuid,p_op text,p_data jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_pref awaaz_private.sos_preferences;
  v_inc public.incidents;
  v_grant awaaz_private.sos_grants;
  v_point awaaz_private.sos_positions;
  v_id uuid:=(p_data->>'incidentId')::uuid;
  v_circle uuid:=(p_data->>'circleId')::uuid;
  v_request uuid:=(p_data->>'clientRequestId')::uuid;
  v_ids uuid[]; v_user uuid; v_owner uuid; v_epoch uuid; v_hash text:=p_data->>'payloadHash';
  v_expected integer; v_allowed boolean; v_response text; v_sequence integer; v_captured timestamptz;
  v_now timestamptz; v_result jsonb; v_limit integer; v_after uuid;
begin
  if p_actor is null or not exists(select 1 from auth.users where id=p_actor) then
    raise exception using errcode='P0001',message='unauthenticated'; end if;
  perform awaaz_private.require_profile(p_actor);
  if p_op in ('get_preference','set_preference') then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_actor::text,0));
    if p_op='set_preference' then
      if jsonb_typeof(p_data->'allowed') is distinct from 'boolean' then raise exception using errcode='P0001',message='invalid_request'; end if;
      v_expected:=(p_data->>'expectedVersion')::integer; v_allowed:=(p_data->>'allowed')::boolean;
      if v_expected is null or v_expected not between 0 and 2147483645 then raise exception using errcode='P0001',message='invalid_request'; end if;
      insert into awaaz_private.sos_preferences(user_id) values(p_actor) on conflict do nothing;
      select * into v_pref from awaaz_private.sos_preferences where user_id=p_actor for update;
      if v_pref.allowed=v_allowed and v_pref.version=v_expected+1 then
        return jsonb_build_object('allowed',v_pref.allowed,'version',v_pref.version,'replayed',true); end if;
      if v_pref.version<>v_expected then raise exception using errcode='P0001',message='sos_preference_changed'; end if;
      perform awaaz_private.take_quota(p_actor,'sos_preference',100);
      update awaaz_private.sos_preferences set allowed=v_allowed,version=version+1,
        consent_epoch=case when allowed is distinct from v_allowed then gen_random_uuid() else consent_epoch end,changed_at=clock_timestamp()
        where user_id=p_actor returning * into v_pref;
      return jsonb_build_object('allowed',v_pref.allowed,'version',v_pref.version,'replayed',false);
    end if;
    select * into v_pref from awaaz_private.sos_preferences where user_id=p_actor;
    return jsonb_build_object('allowed',coalesce(v_pref.allowed,false),'version',coalesce(v_pref.version,0));
  elsif p_op='eligible' then
    if not exists(select 1 from public.circles c join public.circle_members m on m.circle_id=c.id
      where c.id=v_circle and c.closed_at is null and m.user_id=p_actor and m.revoked_at is null) then
      raise exception using errcode='P0001',message='not_found'; end if;
    select jsonb_build_object('items',coalesce(jsonb_agg(jsonb_build_object('userId',m.user_id,'displayName',p.display_name) order by m.user_id),'[]'::jsonb)) into v_result
      from public.circle_members m join public.profiles p on p.id=m.user_id and p.adult_attested
      join auth.users u on u.id=m.user_id and u.phone_confirmed_at is not null
      join awaaz_private.sos_preferences pref on pref.user_id=m.user_id and pref.allowed
      where m.circle_id=v_circle and m.user_id<>p_actor and m.revoked_at is null and not awaaz_private.blocked_pair(p_actor,m.user_id)
        and exists(select 1 from public.circles c join public.circle_members a on a.circle_id=c.id
          where c.id=v_circle and c.closed_at is null and a.user_id=p_actor and a.revoked_at is null);
    return v_result;
  elsif p_op='cancel_request' then
    if v_request is null then raise exception using errcode='P0001',message='invalid_request'; end if;
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_actor::text,0));
    select * into v_inc from public.incidents where owner_id=p_actor and client_request_id=v_request for update;
    if found then
      v_id:=v_inc.id;
      perform awaaz_private.sos_finish(v_id,case when v_inc.expires_at<=clock_timestamp() then 'expired' else 'cancelled' end);
    elsif not exists(select 1 from awaaz_private.sos_request_cancellations where owner_id=p_actor and client_request_id=v_request) then
      perform awaaz_private.take_quota(p_actor,'sos_cancel',20);
      insert into awaaz_private.sos_request_cancellations(owner_id,client_request_id) values(p_actor,v_request);
    end if;
    select status into v_response from public.incidents where id=v_id;
    return jsonb_build_object('clientRequestId',v_request,'incidentId',v_id,'incidentStatus',v_response,'status','cancelled');
  elsif p_op='create' then
    if jsonb_typeof(p_data->'recipientIds') is distinct from 'array' or jsonb_typeof(p_data->'shareLocation') is distinct from 'boolean' then
      raise exception using errcode='P0001',message='invalid_request'; end if;
    select array_agg(value::uuid order by value::uuid) into v_ids from jsonb_array_elements_text(p_data->'recipientIds');
    if v_circle is null or v_request is null or v_hash is null or v_hash!~'^[0-9a-f]{64}$'
      or (p_data->>'mode') is null or (p_data->>'mode') not in ('silent','audible')
      or coalesce(cardinality(v_ids),0) not between 1 and 10 or p_actor=any(v_ids)
      or (select count(distinct x) from unnest(v_ids) x)<>cardinality(v_ids) then
      raise exception using errcode='P0001',message='invalid_request'; end if;
    for v_user in select distinct x from unnest(array_append(v_ids,p_actor)) x order by x loop
      perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_user::text,0)); end loop;
    if exists(select 1 from awaaz_private.sos_request_cancellations where owner_id=p_actor and client_request_id=v_request) then
      raise exception using errcode='P0001',message='incident_unavailable'; end if;
    select * into v_inc from public.incidents where owner_id=p_actor and client_request_id=v_request;
    if found then
      if v_inc.payload_hash<>v_hash then raise exception using errcode='P0001',message='idempotency_conflict'; end if;
      return awaaz_private.sos_control(p_actor,v_inc.id)||jsonb_build_object('replayed',true);
    end if;
    perform 1 from public.circles where id=v_circle and closed_at is null for update;
    if not found then raise exception using errcode='P0001',message='not_found'; end if;
    select consent_epoch into v_epoch from public.circle_members where circle_id=v_circle and user_id=p_actor and revoked_at is null;
    if not found then raise exception using errcode='P0001',message='not_found'; end if;
    foreach v_user in array v_ids loop
      if not exists(select 1 from public.circle_members m join awaaz_private.sos_preferences pref on pref.user_id=m.user_id and pref.allowed
        join public.profiles p on p.id=m.user_id and p.adult_attested join auth.users u on u.id=m.user_id and u.phone_confirmed_at is not null
        where m.circle_id=v_circle and m.user_id=v_user and m.revoked_at is null) or awaaz_private.blocked_pair(p_actor,v_user) then
        raise exception using errcode='P0001',message='sos_recipient_unavailable'; end if;
    end loop;
    v_now:=clock_timestamp();
    for v_id in select id from public.incidents where owner_id=p_actor and status='active' and expires_at<=v_now for update loop
      perform awaaz_private.sos_finish(v_id,'expired'); end loop;
    if exists(select 1 from public.incidents where owner_id=p_actor and status='active') then
      raise exception using errcode='P0001',message='incident_already_active'; end if;
    perform awaaz_private.take_quota(p_actor,'sos',20);
    insert into public.incidents(owner_id,client_request_id,circle_id,payload_hash,started_at,expires_at,mode,share_location)
      values(p_actor,v_request,v_circle,v_hash,v_now,v_now+interval '1 hour',p_data->>'mode',(p_data->>'shareLocation')::boolean) returning * into v_inc;
    insert into awaaz_private.sos_grants(incident_id,recipient_id,circle_id,owner_epoch,recipient_epoch,preference_epoch)
      select v_inc.id,m.user_id,v_circle,v_epoch,m.consent_epoch,pref.consent_epoch from public.circle_members m
      join awaaz_private.sos_preferences pref on pref.user_id=m.user_id where m.circle_id=v_circle and m.user_id=any(v_ids);
    insert into public.notification_outbox(incident_id,recipient_id,idempotency_key,channel,expires_at)
      select v_inc.id,x,v_inc.id::text||':'||x::text||':request:v1','push',v_now+interval '2 minutes' from unnest(v_ids) x;
    return awaaz_private.sos_control(p_actor,v_inc.id)||jsonb_build_object('replayed',false);
  elsif p_op='current' then
    select id into v_id from public.incidents where owner_id=p_actor and status='active' and expires_at>statement_timestamp() limit 1;
    return jsonb_build_object('incident',awaaz_private.sos_control(p_actor,v_id));
  elsif p_op='request' then
    select id into v_id from public.incidents where owner_id=p_actor and client_request_id=v_request;
    if not found then raise exception using errcode='P0001',message='not_found'; end if;
    return awaaz_private.sos_control(p_actor,v_id);
  elsif p_op='view' then
    v_result:=awaaz_private.sos_view(p_actor,v_id);
    if v_result is null then raise exception using errcode='P0001',message='not_found'; end if;
    return v_result;
  elsif p_op='incoming' then
    v_limit:=coalesce((p_data->>'limit')::integer,30); v_after:=(p_data->>'after')::uuid;
    if v_limit not between 1 and 50 then raise exception using errcode='P0001',message='invalid_request'; end if;
    with page as materialized (select i.id,i.status,i.expires_at,p.display_name from awaaz_private.sos_grants g
      join public.incidents i on i.id=g.incident_id join public.profiles p on p.id=i.owner_id
      where g.recipient_id=p_actor and awaaz_private.sos_grant_live(g) and (v_after is null or i.id>v_after) order by i.id limit v_limit+1),
    visible as(select * from page order by id limit v_limit)
    select jsonb_build_object('items',coalesce((select jsonb_agg(jsonb_build_object('id',id,'status',status,'ownerName',display_name,'expiresAt',expires_at) order by id) from visible),'[]'::jsonb),
      'nextCursor',case when (select count(*) from page)>v_limit then (select id from visible order by id desc limit 1) end) into v_result;
    return v_result;
  end if;
  if p_op not in ('end','response','decline','position') or v_id is null then raise exception using errcode='P0001',message='invalid_request'; end if;
  select owner_id into v_owner from public.incidents where id=v_id;
  if not found or (p_op in ('end','position') and v_owner<>p_actor) then raise exception using errcode='P0001',message='not_found'; end if;
  for v_user in select distinct x from unnest(array[p_actor,v_owner]) x order by x loop
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_user::text,0)); end loop;
  select * into v_inc from public.incidents where id=v_id for update;
  v_now:=clock_timestamp();
  if p_op='end' then
    if (p_data->>'outcome') is null or (p_data->>'outcome') not in ('resolved','cancelled') then raise exception using errcode='P0001',message='invalid_request'; end if;
    perform awaaz_private.sos_finish(v_id,case when v_inc.expires_at<=v_now then 'expired' when p_data->>'outcome'='resolved' then 'ended' else 'cancelled' end);
    return awaaz_private.sos_control(p_actor,v_id);
  elsif p_op in ('response','decline') then
    select * into v_grant from awaaz_private.sos_grants where incident_id=v_id and recipient_id=p_actor for update;
    if not found then raise exception using errcode='P0001',message='not_found'; end if;
    if p_op='decline' then
      update awaaz_private.sos_grants set revoked_at=coalesce(revoked_at,v_now) where incident_id=v_id and recipient_id=p_actor;
      return jsonb_build_object('incidentId',v_id,'status','revoked');
    end if;
    if v_inc.status<>'active' or not awaaz_private.sos_grant_live(v_grant) then raise exception using errcode='P0001',message='not_found'; end if;
    v_response:=p_data->>'response'; v_expected:=(p_data->>'expectedVersion')::integer;
    if v_response is null or v_response not in ('seen','contacting','helping','unavailable') or v_expected is null or v_expected not between 0 and 2147483645 then
      raise exception using errcode='P0001',message='invalid_request'; end if;
    if v_grant.response=v_response and v_grant.response_version=v_expected+1 then
      return jsonb_build_object('incidentId',v_id,'response',v_grant.response,'version',v_grant.response_version,'respondedAt',v_grant.responded_at,'replayed',true); end if;
    if v_grant.response_version<>v_expected then raise exception using errcode='P0001',message='sos_response_changed'; end if;
    update awaaz_private.sos_grants set response=v_response,response_version=response_version+1,responded_at=v_now
      where incident_id=v_id and recipient_id=p_actor returning * into v_grant;
    perform awaaz_private.sos_cancel_jobs(v_id,p_actor);
    return jsonb_build_object('incidentId',v_id,'response',v_grant.response,'version',v_grant.response_version,'respondedAt',v_grant.responded_at,'replayed',false);
  end if;
  if v_inc.status<>'active' or v_inc.expires_at<=v_now or not v_inc.share_location or
    not exists(select 1 from awaaz_private.sos_grants g where g.incident_id=v_id and awaaz_private.sos_grant_live(g)) then
    raise exception using errcode='P0001',message='incident_unavailable'; end if;
  v_sequence:=(p_data->>'sequence')::integer; v_captured:=(p_data->>'capturedAt')::timestamptz;
  if v_sequence is null or v_sequence not between 1 and 2147483646 or v_hash is null or v_hash!~'^[0-9a-f]{64}$' then raise exception using errcode='P0001',message='invalid_request'; end if;
  select * into v_point from awaaz_private.sos_positions where incident_id=v_id;
  if v_sequence=v_inc.sequence and v_point.sequence=v_sequence and v_point.payload_hash=v_hash then
    return jsonb_build_object('incidentId',v_id,'sequence',v_sequence,'acceptedAt',v_point.accepted_at,'expiresAt',v_point.purge_at,'replayed',true); end if;
  if v_sequence<>v_inc.sequence+1 then raise exception using errcode='P0001',message='stale_position'; end if;
  if v_captured is null or v_captured<v_now-interval '30 seconds' or v_captured>v_now+interval '5 seconds' then raise exception using errcode='P0001',message='stale_position'; end if;
  if v_point.captured_at is not null and v_captured<=v_point.captured_at then raise exception using errcode='P0001',message='stale_position'; end if;
  if v_inc.last_position_accepted_at is not null and v_inc.last_position_accepted_at>v_now-interval '5 seconds' then raise exception using errcode='P0001',message='rate_limited'; end if;
  insert into awaaz_private.sos_positions(incident_id,sequence,payload_hash,latitude,longitude,accuracy_metres,captured_at,accepted_at,purge_at)
    values(v_id,v_sequence,v_hash,(p_data->>'latitude')::double precision,(p_data->>'longitude')::double precision,(p_data->>'accuracyMetres')::double precision,v_captured,v_now,least(v_inc.expires_at,v_now+interval '90 seconds'))
    on conflict(incident_id) do update set sequence=excluded.sequence,payload_hash=excluded.payload_hash,latitude=excluded.latitude,longitude=excluded.longitude,
      accuracy_metres=excluded.accuracy_metres,captured_at=excluded.captured_at,accepted_at=excluded.accepted_at,purge_at=excluded.purge_at;
  update public.incidents set sequence=v_sequence,last_position_accepted_at=v_now where id=v_id;
  return jsonb_build_object('incidentId',v_id,'sequence',v_sequence,'acceptedAt',v_now,'expiresAt',least(v_inc.expires_at,v_now+interval '90 seconds'),'replayed',false);
end $$;

create function awaaz_private.cleanup_sos() returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_inc public.incidents; v_now timestamptz:=clock_timestamp(); v_points integer:=0; v_grants integer:=0; v_n integer;
begin
  -- Parent first, without account locks. SKIP LOCKED keeps cleanup from blocking
  -- commands. Candidates disappear after cleanup, rather than scanning old tombstones forever.
  for v_inc in with candidates as materialized (
    (select incident_id from awaaz_private.sos_positions where purge_at<=v_now order by purge_at limit 500)
    union (select g.incident_id from awaaz_private.sos_grants g join public.incidents old on old.id=g.incident_id where old.expires_at<=v_now-interval '24 hours' order by old.expires_at,g.incident_id limit 500)
    union (select incident_id from public.notification_outbox where expires_at<=v_now and status in ('queued','sending') order by expires_at limit 500)
    union (select incident_id from public.notification_outbox where created_at<=v_now-interval '7 days' order by created_at limit 500))
    select i.* from public.incidents i join candidates c on c.incident_id=i.id
    order by i.id limit 500 for update of i skip locked loop
    delete from awaaz_private.sos_grants where incident_id=v_inc.id and v_inc.expires_at<=v_now-interval '24 hours';
    get diagnostics v_n=row_count; v_grants:=v_grants+v_n;
    delete from awaaz_private.sos_positions where incident_id=v_inc.id and (purge_at<=v_now or v_inc.status<>'active' or v_inc.expires_at<=v_now);
    get diagnostics v_n=row_count; v_points:=v_points+v_n;
    update public.notification_outbox set status=case when status='sending' then 'unknown' else 'expired' end
      where incident_id=v_inc.id and expires_at<=v_now and status in ('queued','sending');
    delete from public.notification_outbox where incident_id=v_inc.id and created_at<=v_now-interval '7 days';
  end loop;
  return jsonb_build_object('positionsDeleted',v_points,'grantsDeleted',v_grants);
end $$;
revoke all on function awaaz_private.sos_grant_live(awaaz_private.sos_grants),awaaz_private.sos_cancel_jobs(uuid,uuid),
  awaaz_private.sos_grant_changed(),awaaz_private.sos_access_changed(),awaaz_private.sos_control(uuid,uuid),
  awaaz_private.sos_view(uuid,uuid),awaaz_private.sos_finish(uuid,text),awaaz_private.sos_command(uuid,text,jsonb),
  awaaz_private.cleanup_sos() from public,anon,authenticated,service_role,awaaz_api,awaaz_evidence;
grant execute on function awaaz_private.sos_command(uuid,text,jsonb),awaaz_private.cleanup_sos() to awaaz_api;
commit;
