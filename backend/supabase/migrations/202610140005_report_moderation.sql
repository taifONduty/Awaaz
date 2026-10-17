begin;
-- Moderator membership is provisioned by a database administrator. Neither a
-- profile field, user metadata nor a client-supplied JWT claim grants this role.
create table awaaz_private.moderators (
  user_id uuid primary key references auth.users(id) on delete cascade,
  enabled boolean not null default true,
  granted_at timestamptz not null default now()
);
-- This ledger intentionally has no submission FK: withdrawal erases the private
-- payload, while retaining the minimal decision/retry record. It contains no
-- reporter identity, original text, coordinates or free-text moderator notes.
create table awaaz_private.report_reviews (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid not null references auth.users(id) on delete cascade,
  client_request_id uuid not null,
  report_id uuid not null unique,
  decision text not null check(decision in ('approve','reject')),
  reason text not null check(reason in ('reviewed','duplicate','unverifiable','personal_information','outside_scope','resolved')),
  payload_hash text not null check(payload_hash ~ '^[0-9a-f]{64}$'),
  evidence_expires_at timestamptz,
  created_at timestamptz not null default now(),
  unique(actor_id,client_request_id),
  check((decision='approve' and reason='reviewed' and evidence_expires_at is not null)
    or (decision='reject' and reason<>'reviewed' and evidence_expires_at is null))
);
alter table awaaz_private.moderators enable row level security;
alter table awaaz_private.report_reviews enable row level security;
revoke all on awaaz_private.moderators,awaaz_private.report_reviews
  from public,anon,authenticated,service_role,awaaz_api;
create index report_submissions_review_cursor on public.report_submissions(created_at,id) where status='pending';

create function awaaz_private.moderation_command(p_actor uuid,p_op text,p_data jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_report public.report_submissions;
  v_review awaaz_private.report_reviews;
  v_limit integer;
  v_after_time timestamptz;
  v_after_id uuid;
  v_items jsonb;
  v_next jsonb:=null;
  v_id uuid;
  v_request uuid;
  v_decision text;
  v_reason text;
  v_hash text;
  v_expires timestamptz;
  v_replayed boolean:=false;
  v_status text;
begin
  -- The share lock makes revocation linearize with an in-flight review. Every
  -- command, including retries, checks the current administrator-owned grant.
  perform 1 from awaaz_private.moderators where user_id=p_actor and enabled for share;
  if not found then raise exception using errcode='P0001',message='moderator_required'; end if;
  perform awaaz_private.require_profile(p_actor);
  perform 1 from auth.users where id=p_actor and phone_confirmed_at is not null for share;
  if not found then raise exception using errcode='P0001',message='verification_required'; end if;
  if p_op='list_pending' then
    v_limit:=(p_data->>'limit')::integer;
    if v_limit is null or v_limit not between 1 and 50 then
      raise exception using errcode='P0001',message='invalid_request';
    end if;
    if p_data->'after' is not null and p_data->'after'<>'null'::jsonb then
      v_after_time:=(p_data->'after'->>'createdAt')::timestamptz;
      v_after_id:=(p_data->'after'->>'id')::uuid;
      if v_after_time is null or v_after_id is null then
        raise exception using errcode='P0001',message='invalid_cursor';
      end if;
    end if;
    select coalesce(jsonb_agg(x.item order by x.created_at,x.id),'[]'::jsonb) into v_items from (
      select r.id,r.created_at,awaaz_private.report_json(r) item
      from public.report_submissions r where r.status='pending' and r.owner_id<>p_actor
        and (v_after_time is null or (r.created_at,r.id)>(v_after_time,v_after_id))
      order by r.created_at,r.id limit v_limit+1
    ) x;
    if jsonb_array_length(v_items)>v_limit then
      v_next:=jsonb_build_object('createdAt',v_items->(v_limit-1)->>'createdAt','id',v_items->(v_limit-1)->>'id');
      v_items:=v_items-v_limit;
    end if;
    return jsonb_build_object('items',v_items,'next',v_next);
  elsif p_op='review' then
    v_id:=(p_data->>'reportId')::uuid;
    v_request:=(p_data->>'clientRequestId')::uuid;
    v_decision:=p_data->>'decision'; v_reason:=p_data->>'reason'; v_hash:=p_data->>'payloadHash';
    if v_id is null or v_request is null or v_hash is null or v_hash!~'^[0-9a-f]{64}$'
      or v_decision is null or v_reason is null
      or not ((v_decision='approve' and v_reason='reviewed') or (v_decision='reject'
        and v_reason in ('duplicate','unverifiable','personal_information','outside_scope','resolved'))) then
      raise exception using errcode='P0001',message='invalid_request';
    end if;
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('moderation:'||p_actor::text,0));
    select * into v_review from awaaz_private.report_reviews
      where actor_id=p_actor and client_request_id=v_request;
    if found then
      if v_review.payload_hash<>v_hash or v_review.report_id<>v_id then
        raise exception using errcode='P0001',message='idempotency_conflict';
      end if;
      v_replayed:=true;
    else
      -- Row locking also serializes two moderators and the owner's withdrawal.
      select * into v_report from public.report_submissions where id=v_id for update;
      if not found then raise exception using errcode='P0001',message='not_found'; end if;
      if v_report.owner_id=p_actor then raise exception using errcode='P0001',message='self_review_forbidden'; end if;
      if v_report.status<>'pending' then raise exception using errcode='P0001',message='already_reviewed'; end if;
      if v_decision='approve' then
        -- Evidence lifetimes are bounded from observation, never extended by
        -- delayed moderation or retries. These are pilot policy, not ML scores.
        v_expires:=v_report.observed_at + case v_report.category
          when 'accident' then interval '1 hour'
          when 'theft' then interval '2 hours'
          when 'harassment' then interval '2 hours'
          when 'obstruction' then interval '6 hours'
          when 'lighting' then interval '12 hours'
          else interval '2 hours' end;
        if v_expires<=now() then raise exception using errcode='P0001',message='stale_report'; end if;
      end if;
      insert into awaaz_private.report_reviews(actor_id,client_request_id,report_id,decision,reason,payload_hash,evidence_expires_at)
        values(p_actor,v_request,v_id,v_decision,v_reason,v_hash,v_expires) returning * into v_review;
      update public.report_submissions set status=case when v_decision='approve' then 'reviewed' else 'rejected' end where id=v_id;
      -- No road event or edge risk is created here. Publication requires a real
      -- versioned graph association and its own auditable, withdrawal-safe stage.
    end if;
    select status into v_status from public.report_submissions where id=v_review.report_id;
    return jsonb_build_object('id',v_review.id,'reportId',v_review.report_id,'decision',v_review.decision,
      'reason',v_review.reason,'status',coalesce(v_status,'withdrawn'),'expiresAt',v_review.evidence_expires_at,
      'reviewedAt',v_review.created_at,'replayed',v_replayed);
  end if;
  raise exception using errcode='P0001',message='invalid_request';
end $$;
revoke all on function awaaz_private.moderation_command(uuid,text,jsonb)
  from public,anon,authenticated,service_role,awaaz_api;
grant execute on function awaaz_private.moderation_command(uuid,text,jsonb) to awaaz_api;
commit;
