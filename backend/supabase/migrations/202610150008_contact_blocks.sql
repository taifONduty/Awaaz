begin;

-- Keep only the current decision/version. An unblocked tombstone prevents an
-- old delayed mutation from becoming a fresh version-zero request again.
create table awaaz_private.user_block_settings (
  blocker_id uuid not null references public.profiles(id) on delete cascade,
  target_id uuid not null references public.profiles(id) on delete cascade,
  blocked boolean not null,
  version integer not null check(version between 1 and 2147483646),
  label_snapshot text,
  changed_at timestamptz not null default now(),
  primary key(blocker_id,target_id),
  check(blocker_id<>target_id),
  check(label_snapshot is null or (blocked and char_length(label_snapshot) between 1 and 80))
);
create index user_block_reverse on awaaz_private.user_block_settings(target_id,blocker_id)
  where blocked;
create index circle_invite_contact_pair on public.circle_invites(inviter_id,recipient_id,circle_id)
  where status in ('pending','accepted');
create index circle_invite_contact_recipient on public.circle_invites(circle_id,recipient_id)
  where status in ('pending','accepted');
alter table awaaz_private.user_block_settings enable row level security;
revoke all on awaaz_private.user_block_settings from public,anon,authenticated,service_role,awaaz_api;
alter table awaaz_private.account_quotas drop constraint account_quotas_kind_check;
alter table awaaz_private.account_quotas add constraint account_quotas_kind_check
  check(kind in ('report','circle','invite','block'));

create function awaaz_private.blocked_pair(p_one uuid,p_two uuid) returns boolean
language sql stable set search_path='' as $$
  select exists(select 1 from awaaz_private.user_block_settings b where b.blocked and
    ((b.blocker_id=p_one and b.target_id=p_two) or (b.blocker_id=p_two and b.target_id=p_one)));
$$;
create function awaaz_private.block_state(p_actor uuid,p_target uuid) returns jsonb
language sql stable set search_path='' as $$
  select jsonb_build_object('userId',p_target,'blocked',coalesce(b.blocked,false),
    'version',coalesce(b.version,0),'changedAt',b.changed_at)
    from (values(1)) anchor(n) left join awaaz_private.user_block_settings b
      on b.blocker_id=p_actor and b.target_id=p_target;
$$;

alter function awaaz_private.people_command(uuid,text,jsonb) rename to people_command_before_blocks;
-- Renaming retains the previous grant. It must not remain an API bypass.
revoke all on function awaaz_private.people_command_before_blocks(uuid,text,jsonb)
  from public,anon,authenticated,service_role,awaaz_api;

create function awaaz_private.people_command(p_actor uuid,p_op text,p_data jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_actor uuid;
  v_other uuid;
  v_owner uuid;
  v_circle uuid;
  v_invite public.circle_invites;
  v_setting awaaz_private.user_block_settings;
  v_target uuid;
  v_desired boolean;
  v_expected integer;
  v_version integer;
  v_blocked boolean;
  v_label text;
  v_removed uuid;
  v_limit integer;
  v_after uuid;
  v_result jsonb;
begin
  if p_actor is null or not exists(select 1 from auth.users where id=p_actor) then
    raise exception using errcode='P0001',message='unauthenticated';
  end if;
  if p_op in ('get_profile','put_profile') then
    return awaaz_private.people_command_before_blocks(p_actor,p_op,p_data);
  end if;
  perform awaaz_private.require_profile(p_actor);

  -- Every membership mutation takes all relevant account locks first, in UUID
  -- order, then circle/invitation rows. This extends the original actor lock
  -- discipline without introducing circle -> account / account -> circle cycles.
  if p_op in ('create_invite','remove_member','close_circle') then
    v_circle:=(p_data->>'circleId')::uuid;
    select owner_id into v_owner from public.circles where id=v_circle;
    if p_op='create_invite' then v_other:=(p_data->>'recipientId')::uuid;
    elsif p_op='remove_member' then v_other:=(p_data->>'memberId')::uuid; end if;
  elsif p_op in ('accept_invite','revoke_invite') then
    select * into v_invite from public.circle_invites where id=(p_data->>'id')::uuid;
    v_circle:=v_invite.circle_id; v_owner:=v_invite.inviter_id; v_other:=v_invite.recipient_id;
  elsif p_op='set_block' then
    v_other:=(p_data->>'userId')::uuid;
  end if;
  if p_op in ('create_circle','create_invite','accept_invite','revoke_invite',
      'remove_member','close_circle','set_block') then
    for v_actor in select distinct account_id from unnest(array[p_actor,v_other,v_owner]) account_id
        where account_id is not null order by account_id loop
      perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_actor::text,0));
    end loop;
  end if;

  if p_op in ('get_block','set_block') then
    v_target:=(p_data->>'userId')::uuid;
    if v_target is null or v_target=p_actor then
      raise exception using errcode='P0001',message='invalid_request';
    end if;
    if p_op='get_block' then return awaaz_private.block_state(p_actor,v_target); end if;
    if jsonb_typeof(p_data->'blocked') is distinct from 'boolean' or
       jsonb_typeof(p_data->'expectedVersion') is distinct from 'number' then
      raise exception using errcode='P0001',message='invalid_request';
    end if;
    v_desired:=(p_data->>'blocked')::boolean;
    if p_data->>'expectedVersion' !~ '^(0|[1-9][0-9]*)$' then
      raise exception using errcode='P0001',message='invalid_request';
    end if;
    v_expected:=(p_data->>'expectedVersion')::integer;
    if v_expected<0 or v_expected>2147483646 then
      raise exception using errcode='P0001',message='invalid_request';
    end if;
    select * into v_setting from awaaz_private.user_block_settings
      where blocker_id=p_actor and target_id=v_target for update;
    v_version:=coalesce(v_setting.version,0); v_blocked:=coalesce(v_setting.blocked,false);
    if v_version<>v_expected then
      if v_version=v_expected+1 and v_blocked=v_desired then
        return awaaz_private.block_state(p_actor,v_target)||jsonb_build_object('replayed',true);
      end if;
      raise exception using errcode='P0001',message='block_changed';
    end if;
    if v_blocked=v_desired then
      return awaaz_private.block_state(p_actor,v_target)||jsonb_build_object('replayed',true);
    end if;
    if v_version>=2147483646 then
      raise exception using errcode='P0001',message='block_version_exhausted';
    end if;
    if v_desired then
      -- Blocking does not become a profile-directory/existence oracle. A caller
      -- must know this account through an invitation, shared circle or own state.
      if v_version=0 and not exists(select 1 from public.circle_invites i
          where (i.inviter_id=p_actor and i.recipient_id=v_target) or
            (i.inviter_id=v_target and i.recipient_id=p_actor)) and
          not exists(select 1 from public.circle_members a join public.circle_members b
            on a.circle_id=b.circle_id where a.user_id=p_actor and b.user_id=v_target) then
        raise exception using errcode='P0001',message='not_found';
      end if;
      -- Past contact permits blocking, not discovering a former contact's
      -- current name. Capture only labels the caller can currently see.
      select p.display_name into v_label from public.profiles p where p.id=v_target and (
        exists(select 1 from public.circle_members a join public.circle_members b using(circle_id)
          join public.circles c on c.id=a.circle_id where a.user_id=p_actor and b.user_id=v_target
            and a.revoked_at is null and b.revoked_at is null and c.closed_at is null)
          or exists(select 1 from public.circle_invites i join public.circles c on c.id=i.circle_id
            where i.inviter_id=v_target and i.recipient_id=p_actor and i.status='pending'
              and i.expires_at>now() and c.closed_at is null));
      if (select count(*) from awaaz_private.user_block_settings where blocker_id=p_actor and blocked)>=1000 then
        raise exception using errcode='P0001',message='blocks_limit_reached';
      end if;
    end if;
    perform awaaz_private.take_quota(p_actor,'block',200);

    if v_desired then
      -- Lock each affected circle before touching its invitation/member rows.
      -- In a third party's circle the blocker leaves; they cannot remove others.
      for v_circle in with candidates as (
          select a.circle_id from public.circle_members a join public.circle_members b using(circle_id)
            where a.user_id=p_actor and b.user_id=v_target and a.revoked_at is null and b.revoked_at is null
          union
          select i.circle_id from public.circle_invites i where i.status in ('pending','accepted')
            and (i.status='accepted' or i.expires_at>now()) and
            ((i.inviter_id=p_actor and i.recipient_id=v_target) or (i.inviter_id=v_target and i.recipient_id=p_actor))
          union
          select m.circle_id from public.circle_members m join public.circle_invites i using(circle_id)
            where m.user_id=v_target and m.revoked_at is null and i.recipient_id=p_actor
              and i.status='pending' and i.expires_at>now()
          union
          select m.circle_id from public.circle_members m join public.circle_invites i using(circle_id)
            where m.user_id=p_actor and m.revoked_at is null and i.recipient_id=v_target
              and i.status='pending' and i.expires_at>now()
        ) select c.id from public.circles c join candidates q on q.circle_id=c.id
          where c.closed_at is null order by c.id for update of c loop
        update public.circle_invites i set status='revoked',revoked_at=coalesce(i.revoked_at,now())
          where i.circle_id=v_circle and i.status in ('pending','accepted') and (
            (i.inviter_id=p_actor and i.recipient_id=v_target) or (i.inviter_id=v_target and i.recipient_id=p_actor)
            or (i.recipient_id=p_actor and exists(select 1 from public.circle_members m where m.circle_id=v_circle and m.user_id=v_target and m.revoked_at is null))
            or (i.recipient_id=v_target and exists(select 1 from public.circle_members m where m.circle_id=v_circle and m.user_id=p_actor and m.revoked_at is null)));
        if exists(select 1 from public.circle_members where circle_id=v_circle and user_id=p_actor and revoked_at is null)
           and exists(select 1 from public.circle_members where circle_id=v_circle and user_id=v_target and revoked_at is null) then
          select case when owner_id=p_actor then v_target else p_actor end into v_removed
            from public.circles where id=v_circle;
          update public.circle_members set revoked_at=coalesce(revoked_at,now())
            where circle_id=v_circle and user_id=v_removed;
          update public.circle_invites set status='revoked',revoked_at=coalesce(revoked_at,now())
            where circle_id=v_circle and recipient_id=v_removed and status<>'revoked';
        end if;
      end loop;
    end if;
    insert into awaaz_private.user_block_settings(blocker_id,target_id,blocked,version,label_snapshot)
      values(p_actor,v_target,v_desired,v_version+1,case when v_desired then v_label end)
      on conflict(blocker_id,target_id) do update set blocked=excluded.blocked,version=excluded.version,
        label_snapshot=excluded.label_snapshot,changed_at=now();
    return awaaz_private.block_state(p_actor,v_target)||jsonb_build_object('replayed',false);
  elsif p_op='list_blocks' then
    v_limit:=coalesce((p_data->>'limit')::integer,30); v_after:=(p_data->>'after')::uuid;
    if v_limit not between 1 and 50 then raise exception using errcode='P0001',message='invalid_request'; end if;
    with page as materialized (
      select * from awaaz_private.user_block_settings where blocker_id=p_actor and blocked
        and (v_after is null or target_id>v_after) order by target_id limit v_limit+1
    ), visible as (select * from page order by target_id limit v_limit)
    select jsonb_build_object('items',coalesce((select jsonb_agg(jsonb_build_object('userId',target_id,
      'displayName',label_snapshot,'version',version,'blockedAt',changed_at) order by target_id) from visible),'[]'::jsonb),
      'nextCursor',case when (select count(*) from page)>v_limit
        then (select target_id from visible order by target_id desc limit 1) end) into v_result;
    return v_result;
  elsif p_op in ('create_invite','accept_invite') then
    v_target:=case when p_op='create_invite' then v_other else v_invite.recipient_id end;
    if exists(select 1 from public.circle_members m where m.circle_id=v_circle and m.revoked_at is null
        and awaaz_private.blocked_pair(v_target,m.user_id)) then
      raise exception using errcode='P0001',message=case when p_op='create_invite' then 'not_found' else 'invite_unavailable' end;
    end if;
  elsif p_op='incoming_invites' then
    select coalesce(jsonb_agg(x.item order by x.created_at desc,x.id),'[]'::jsonb) into v_result from (
      select i.id,i.created_at,jsonb_build_object('id',i.id,'circleId',c.id,'circleName',c.name,
        'inviterId',i.inviter_id,'inviterName',p.display_name,'expiresAt',i.expires_at) item
      from public.circle_invites i join public.circles c on c.id=i.circle_id join public.profiles p on p.id=i.inviter_id
      where i.recipient_id=p_actor and i.status='pending' and i.expires_at>now() and c.closed_at is null
        and not exists(select 1 from public.circle_members m where m.circle_id=c.id and m.revoked_at is null
          and awaaz_private.blocked_pair(p_actor,m.user_id))
      order by i.created_at desc,i.id limit 50) x;
    return jsonb_build_object('items',v_result);
  end if;
  return awaaz_private.people_command_before_blocks(p_actor,p_op,p_data);
end $$;

revoke all on function awaaz_private.blocked_pair(uuid,uuid),awaaz_private.block_state(uuid,uuid),
  awaaz_private.people_command(uuid,text,jsonb) from public,anon,authenticated,service_role,awaaz_api;
grant execute on function awaaz_private.people_command(uuid,text,jsonb) to awaaz_api;
commit;
