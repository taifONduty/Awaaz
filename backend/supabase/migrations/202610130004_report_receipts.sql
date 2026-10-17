begin;
-- Preserve the existing dispatcher's behavior without copying its write logic.
-- Only the public dispatcher remains executable by the restricted API role.
alter function awaaz_private.community_command(uuid,text,jsonb) rename to community_command_v1;
revoke all on function awaaz_private.community_command_v1(uuid,text,jsonb)
  from public,anon,authenticated,service_role,awaaz_api;

create function awaaz_private.community_command(p_actor uuid,p_op text,p_data jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_command awaaz_private.report_commands;
  v_status text;
  v_request uuid;
begin
  if p_op<>'report_receipt' then
    return awaaz_private.community_command_v1(p_actor,p_op,p_data);
  end if;
  perform awaaz_private.require_profile(p_actor);
  v_request:=(p_data->>'clientRequestId')::uuid;
  if v_request is null then raise exception using errcode='P0001',message='invalid_request'; end if;
  select * into v_command from awaaz_private.report_commands
    where actor_id=p_actor and client_request_id=v_request;
  if not found then raise exception using errcode='P0001',message='not_found'; end if;
  select status into v_status from public.report_submissions
    where id=v_command.report_id and owner_id=p_actor;
  -- A withdrawn payload has only its tombstone. No text/location is restored.
  return jsonb_build_object('id',v_command.report_id,'status',coalesce(v_status,'withdrawn'),'replayed',true);
end $$;
revoke all on function awaaz_private.community_command(uuid,text,jsonb)
  from public,anon,authenticated,service_role,awaaz_api;
grant execute on function awaaz_private.community_command(uuid,text,jsonb) to awaaz_api;
commit;
