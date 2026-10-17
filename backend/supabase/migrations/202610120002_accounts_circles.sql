-- New backend access boundary. Apply after the first foundation migration.
begin;
create schema if not exists awaaz_private;
do $$ begin
  if not exists(select 1 from pg_catalog.pg_roles where rolname='awaaz_api') then
    create role awaaz_api nologin noinherit;
  elsif exists(select 1 from pg_catalog.pg_roles where rolname='awaaz_api'
    and (rolsuper or rolbypassrls or rolcreatedb or rolcreaterole or rolreplication or rolinherit)) then
    raise exception 'Existing awaaz_api role has unsafe privileges; provision an isolated restricted role';
  end if;
end $$;
alter role awaaz_api set search_path='';
alter role awaaz_api set statement_timeout='8s';
alter role awaaz_api set lock_timeout='4s';
alter role awaaz_api set idle_in_transaction_session_timeout='15s';
grant usage on schema awaaz_private to awaaz_api,authenticated;

create table public.circles (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  client_request_id uuid not null,
  payload_hash text not null check(payload_hash ~ '^[0-9a-f]{64}$'),
  name text not null check(char_length(btrim(name)) between 1 and 80),
  created_at timestamptz not null default now(),
  closed_at timestamptz,
  unique(owner_id,client_request_id),
  check(closed_at is null or closed_at>=created_at)
);
create table public.circle_members (
  circle_id uuid not null references public.circles(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null check(role in ('owner','member')),
  joined_at timestamptz not null default now(),
  revoked_at timestamptz,
  primary key(circle_id,user_id),
  check(revoked_at is null or revoked_at>=joined_at)
);
create unique index circle_one_owner on public.circle_members(circle_id) where role='owner';
create index circle_member_active on public.circle_members(user_id,circle_id) where revoked_at is null;
create table public.circle_invites (
  id uuid primary key default gen_random_uuid(),
  circle_id uuid not null references public.circles(id) on delete cascade,
  inviter_id uuid not null references public.profiles(id) on delete cascade,
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  client_request_id uuid not null,
  payload_hash text not null check(payload_hash ~ '^[0-9a-f]{64}$'),
  token_hash text not null check(token_hash ~ '^[0-9a-f]{64}$'),
  status text not null default 'pending' check(status in ('pending','accepted','revoked')),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  accepted_at timestamptz,
  revoked_at timestamptz,
  unique(inviter_id,client_request_id),
  check(inviter_id<>recipient_id),
  check(expires_at>created_at and expires_at<=created_at+interval '7 days'),
  check(status<>'accepted' or accepted_at is not null),
  check((status='revoked')=(revoked_at is not null))
);
create unique index circle_one_pending_invite on public.circle_invites(circle_id,recipient_id) where status='pending';
create index circle_invite_inbox on public.circle_invites(recipient_id,created_at desc) where status='pending';

create table awaaz_private.account_quotas (
  actor_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check(kind in ('report','circle','invite')),
  day date not null,
  used integer not null check(used>0),
  primary key(actor_id,kind,day)
);
alter table awaaz_private.account_quotas enable row level security;
revoke all on awaaz_private.account_quotas from public,anon,authenticated,service_role,awaaz_api;

create function awaaz_private.require_profile(p_actor uuid) returns void
language plpgsql set search_path='' as $$
begin
  if not exists(select 1 from public.profiles where id=p_actor and adult_attested) then
    raise exception using errcode='P0001',message='profile_required';
  end if;
end $$;
create function awaaz_private.take_quota(p_actor uuid,p_kind text,p_limit integer) returns void
language plpgsql set search_path='' as $$
declare v_used integer;
begin
  insert into awaaz_private.account_quotas(actor_id,kind,day,used)
    values(p_actor,p_kind,(now() at time zone 'UTC')::date,1)
    on conflict(actor_id,kind,day) do update set used=awaaz_private.account_quotas.used+1
    returning used into v_used;
  if v_used>p_limit then raise exception using errcode='P0001',message='rate_limited'; end if;
end $$;
create function awaaz_private.circle_summary(p_circle public.circles) returns jsonb
language sql immutable set search_path='' as $$
  select jsonb_build_object('id',p_circle.id,'name',p_circle.name,'ownerId',p_circle.owner_id,'createdAt',p_circle.created_at);
$$;
create function awaaz_private.circle_detail(p_actor uuid,p_circle uuid) returns jsonb
language plpgsql set search_path='' as $$
declare v_circle public.circles; v_members jsonb;
begin
  select c.* into v_circle from public.circles c join public.circle_members m on m.circle_id=c.id
    where c.id=p_circle and c.closed_at is null and m.user_id=p_actor and m.revoked_at is null;
  if not found then raise exception using errcode='P0001',message='not_found'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('userId',m.user_id,'displayName',p.display_name,
    'role',m.role,'joinedAt',m.joined_at) order by m.joined_at,m.user_id),'[]'::jsonb)
    into v_members from public.circle_members m join public.profiles p on p.id=m.user_id
    where m.circle_id=p_circle and m.revoked_at is null;
  return awaaz_private.circle_summary(v_circle)||jsonb_build_object('members',v_members);
end $$;
create function awaaz_private.invite_receipt(p_invite public.circle_invites,p_replayed boolean) returns jsonb
language sql immutable set search_path='' as $$
  select jsonb_build_object('id',p_invite.id,'circleId',p_invite.circle_id,'recipientId',p_invite.recipient_id,
    'expiresAt',p_invite.expires_at,'status',p_invite.status,'replayed',p_replayed);
$$;

-- One parameterized, transaction-scoped call per HTTP operation. The actor is
-- supplied only by the server after online Auth verification, never by a body.
create function awaaz_private.people_command(p_actor uuid,p_op text,p_data jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_profile public.profiles;
  v_circle public.circles;
  v_invite public.circle_invites;
  v_id uuid;
  v_recipient uuid;
  v_request uuid;
  v_name text;
  v_hash text;
  v_token_hash text;
  v_ttl integer;
  v_result jsonb;
  v_replayed boolean;
begin
  if p_actor is null or not exists(select 1 from auth.users where id=p_actor) then
    raise exception using errcode='P0001',message='unauthenticated';
  end if;
  if p_op='get_profile' then
    select * into v_profile from public.profiles where id=p_actor;
    if not found then return 'null'::jsonb; end if;
    return jsonb_build_object('id',v_profile.id,'displayName',v_profile.display_name,'locale',v_profile.locale,
      'adultAttested',v_profile.adult_attested,'createdAt',v_profile.created_at);
  elsif p_op='put_profile' then
    v_name:=btrim(p_data->>'displayName');
    if v_name is null or char_length(v_name) not between 1 and 80 or p_data->>'locale' not in ('en','bn')
      or p_data->'adultAttested' is distinct from 'true'::jsonb then
      raise exception using errcode='P0001',message='invalid_request';
    end if;
    insert into public.profiles(id,display_name,locale,adult_attested) values(p_actor,v_name,p_data->>'locale',true)
      on conflict(id) do update set display_name=excluded.display_name,locale=excluded.locale;
    return awaaz_private.people_command(p_actor,'get_profile');
  end if;
  perform awaaz_private.require_profile(p_actor);
  if p_op='list_circles' then
    select coalesce(jsonb_agg(awaaz_private.circle_summary(c) order by c.created_at desc,c.id),'[]'::jsonb)
      into v_result from public.circles c join public.circle_members m on m.circle_id=c.id
      where m.user_id=p_actor and m.revoked_at is null and c.closed_at is null;
    return jsonb_build_object('items',v_result);
  elsif p_op='get_circle' then
    return awaaz_private.circle_detail(p_actor,(p_data->>'id')::uuid);
  elsif p_op='create_circle' then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_actor::text,0));
    v_request:=(p_data->>'clientRequestId')::uuid; v_name:=btrim(p_data->>'name'); v_hash:=p_data->>'payloadHash';
    if v_request is null or v_name is null or char_length(v_name) not between 1 and 80
      or v_hash is null or v_hash !~ '^[0-9a-f]{64}$' then raise exception using errcode='P0001',message='invalid_request'; end if;
    select * into v_circle from public.circles where owner_id=p_actor and client_request_id=v_request;
    if found then
      if v_circle.payload_hash<>v_hash then raise exception using errcode='P0001',message='idempotency_conflict'; end if;
      if v_circle.closed_at is not null then raise exception using errcode='P0001',message='circle_closed'; end if;
      return jsonb_build_object('circle',awaaz_private.circle_summary(v_circle),'replayed',true);
    end if;
    if (select count(*) from public.circles where owner_id=p_actor and closed_at is null)>=5 then
      raise exception using errcode='P0001',message='circles_limit_reached';
    end if;
    if (select count(*) from public.circle_members where user_id=p_actor and revoked_at is null)>=20 then
      raise exception using errcode='P0001',message='circles_limit_reached';
    end if;
    perform awaaz_private.take_quota(p_actor,'circle',10);
    insert into public.circles(owner_id,client_request_id,payload_hash,name) values(p_actor,v_request,v_hash,v_name)
      returning * into v_circle;
    insert into public.circle_members(circle_id,user_id,role) values(v_circle.id,p_actor,'owner');
    return jsonb_build_object('circle',awaaz_private.circle_summary(v_circle),'replayed',false);
  elsif p_op='incoming_invites' then
    select coalesce(jsonb_agg(x.item order by x.created_at desc,x.id),'[]'::jsonb) into v_result from (
      select i.id,i.created_at,jsonb_build_object('id',i.id,'circleId',c.id,'circleName',c.name,
        'inviterName',p.display_name,'expiresAt',i.expires_at) item
      from public.circle_invites i join public.circles c on c.id=i.circle_id join public.profiles p on p.id=i.inviter_id
      where i.recipient_id=p_actor and i.status='pending' and i.expires_at>now() and c.closed_at is null
      order by i.created_at desc,i.id limit 50
    ) x;
    return jsonb_build_object('items',v_result);
  elsif p_op='create_invite' then
    v_id:=(p_data->>'circleId')::uuid;
    select * into v_circle from public.circles where id=v_id for update;
    if not found or v_circle.owner_id<>p_actor or v_circle.closed_at is not null then
      raise exception using errcode='P0001',message='not_found';
    end if;
    v_request:=(p_data->>'clientRequestId')::uuid; v_recipient:=(p_data->>'recipientId')::uuid;
    v_ttl:=(p_data->>'expiresInSeconds')::integer; v_hash:=p_data->>'payloadHash'; v_token_hash:=p_data->>'tokenHash';
    if v_request is null or v_recipient is null or v_recipient=p_actor or v_ttl is null or v_ttl not between 300 and 604800
      or v_hash is null or v_hash !~ '^[0-9a-f]{64}$' or v_token_hash is null or v_token_hash !~ '^[0-9a-f]{64}$' then
      raise exception using errcode='P0001',message='invalid_request';
    end if;
    -- Global per-actor order also serializes invite IDs across different circles.
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_actor::text,0));
    select * into v_invite from public.circle_invites where inviter_id=p_actor and client_request_id=v_request;
    if found then
      if v_invite.payload_hash<>v_hash then raise exception using errcode='P0001',message='idempotency_conflict'; end if;
      if v_invite.token_hash<>v_token_hash then raise exception using errcode='P0001',message='invite_reissue_required'; end if;
      return awaaz_private.invite_receipt(v_invite,true);
    end if;
    if not exists(select 1 from public.profiles where id=v_recipient and adult_attested) then
      raise exception using errcode='P0001',message='not_found';
    end if;
    if exists(select 1 from public.circle_members where circle_id=v_id and user_id=v_recipient and revoked_at is null) then
      raise exception using errcode='P0001',message='already_member';
    end if;
    update public.circle_invites set status='revoked',revoked_at=now()
      where circle_id=v_id and recipient_id=v_recipient and status='pending' and expires_at<=now();
    if exists(select 1 from public.circle_invites where circle_id=v_id and recipient_id=v_recipient and status='pending') then
      raise exception using errcode='P0001',message='invite_pending';
    end if;
    perform awaaz_private.take_quota(p_actor,'invite',20);
    insert into public.circle_invites(circle_id,inviter_id,recipient_id,client_request_id,payload_hash,token_hash,expires_at)
      values(v_id,p_actor,v_recipient,v_request,v_hash,v_token_hash,now()+v_ttl*interval '1 second') returning * into v_invite;
    return awaaz_private.invite_receipt(v_invite,false);
  elsif p_op in ('accept_invite','revoke_invite') then
    v_id:=(p_data->>'id')::uuid;
    select circle_id into v_recipient from public.circle_invites where id=v_id;
    if not found then raise exception using errcode='P0001',message='not_found'; end if;
    -- All membership/invite mutations lock circle first, then invitation.
    select * into v_circle from public.circles where id=v_recipient for update;
    select * into v_invite from public.circle_invites where id=v_id for update;
    if p_op='revoke_invite' then
      if p_actor not in (v_invite.inviter_id,v_invite.recipient_id) then raise exception using errcode='P0001',message='not_found'; end if;
      update public.circle_invites set status='revoked',revoked_at=coalesce(revoked_at,now()) where id=v_id;
      if v_invite.status='accepted' then
        update public.circle_members set revoked_at=coalesce(revoked_at,now())
          where circle_id=v_circle.id and user_id=v_invite.recipient_id;
      end if;
      return jsonb_build_object('id',v_id,'status','revoked');
    end if;
    if v_invite.recipient_id<>p_actor or v_invite.token_hash is distinct from p_data->>'tokenHash' then
      raise exception using errcode='P0001',message='not_found';
    end if;
    if v_circle.closed_at is not null or v_invite.status='revoked' then
      raise exception using errcode='P0001',message='invite_unavailable';
    end if;
    if v_invite.status='accepted' then
      if not exists(select 1 from public.circle_members where circle_id=v_circle.id and user_id=p_actor and revoked_at is null) then
        raise exception using errcode='P0001',message='invite_unavailable';
      end if;
      return jsonb_build_object('circle',awaaz_private.circle_detail(p_actor,v_circle.id),'replayed',true);
    end if;
    if v_invite.expires_at<=now() then raise exception using errcode='P0001',message='invite_unavailable'; end if;
    -- Actor lock prevents concurrent joins in different circles exceeding quota.
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_actor::text,0));
    if (select count(*) from public.circle_members where circle_id=v_circle.id and revoked_at is null)>=20 then
      raise exception using errcode='P0001',message='members_limit_reached';
    end if;
    if (select count(*) from public.circle_members where user_id=p_actor and revoked_at is null)>=20 then
      raise exception using errcode='P0001',message='circles_limit_reached';
    end if;
    insert into public.circle_members(circle_id,user_id,role) values(v_circle.id,p_actor,'member')
      on conflict(circle_id,user_id) do update set role='member',joined_at=now(),revoked_at=null;
    update public.circle_invites set status='accepted',accepted_at=now() where id=v_id;
    return jsonb_build_object('circle',awaaz_private.circle_detail(p_actor,v_circle.id),'replayed',false);
  elsif p_op in ('remove_member','close_circle') then
    v_id:=(p_data->>'circleId')::uuid;
    select * into v_circle from public.circles where id=v_id for update;
    if not found then raise exception using errcode='P0001',message='not_found'; end if;
    if p_op='close_circle' then
      if v_circle.owner_id<>p_actor then raise exception using errcode='P0001',message='not_found'; end if;
      update public.circles set closed_at=coalesce(closed_at,now()) where id=v_id;
      update public.circle_members set revoked_at=coalesce(revoked_at,now()) where circle_id=v_id;
      update public.circle_invites set status='revoked',revoked_at=coalesce(revoked_at,now()) where circle_id=v_id;
      return jsonb_build_object('id',v_id,'status','closed');
    end if;
    v_recipient:=(p_data->>'memberId')::uuid;
    if v_circle.closed_at is not null or (p_actor<>v_circle.owner_id and p_actor<>v_recipient)
      or not exists(select 1 from public.circle_members where circle_id=v_id and user_id=v_recipient) then
      raise exception using errcode='P0001',message='not_found';
    end if;
    if v_recipient=v_circle.owner_id then raise exception using errcode='P0001',message='owner_cannot_leave'; end if;
    update public.circle_members set revoked_at=coalesce(revoked_at,now()) where circle_id=v_id and user_id=v_recipient;
    update public.circle_invites set status='revoked',revoked_at=coalesce(revoked_at,now())
      where circle_id=v_id and recipient_id=v_recipient;
    return jsonb_build_object('circleId',v_id,'userId',v_recipient,'status','revoked');
  end if;
  raise exception using errcode='P0001',message='invalid_request';
end $$;

create function awaaz_private.is_circle_member(p_circle uuid) returns boolean
language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.circle_members m join public.circles c on c.id=m.circle_id
    where c.id=p_circle and c.closed_at is null and m.user_id=(select auth.uid()) and m.revoked_at is null);
$$;
alter table public.circles enable row level security;
alter table public.circle_members enable row level security;
alter table public.circle_invites enable row level security;
revoke all on public.circles,public.circle_members,public.circle_invites from public,anon,authenticated,service_role,awaaz_api;
grant select(id,owner_id,name,created_at) on public.circles to authenticated;
grant select on public.circle_members to authenticated;
grant select(id,circle_id,inviter_id,recipient_id,status,created_at,expires_at,accepted_at,revoked_at)
  on public.circle_invites to authenticated;
create policy circles_member_read on public.circles for select to authenticated using(awaaz_private.is_circle_member(id));
create policy members_circle_read on public.circle_members for select to authenticated
  using(revoked_at is null and awaaz_private.is_circle_member(circle_id));
create policy invites_intended_read on public.circle_invites for select to authenticated
  using(inviter_id=(select auth.uid()) or recipient_id=(select auth.uid()));

revoke all on all functions in schema awaaz_private from public,anon,authenticated,service_role,awaaz_api;
grant execute on function awaaz_private.is_circle_member(uuid) to authenticated;
grant execute on function awaaz_private.people_command(uuid,text,jsonb) to awaaz_api;
commit;
