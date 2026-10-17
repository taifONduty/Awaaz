import type { SqlExecutor } from './postgres.ts';

export async function evidenceWorkerAllowed(db: SqlExecutor): Promise<boolean> {
  try {
    const result = await db.query(`SELECT current_user='awaaz_evidence'
      AND NOT EXISTS(SELECT 1 FROM pg_catalog.pg_roles WHERE rolname=current_user AND (rolsuper OR rolbypassrls OR rolcreatedb OR rolcreaterole OR rolreplication OR rolinherit))
      AND NOT EXISTS(SELECT 1 FROM pg_catalog.pg_auth_members m JOIN pg_catalog.pg_roles r ON r.oid=m.member WHERE r.rolname=current_user)
      AND NOT EXISTS(SELECT 1 FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname||'.'||c.relname=ANY(ARRAY['public.profiles','public.report_submissions','public.circles','public.circle_members',
        'public.circle_invites','public.road_events','public.risk_snapshots','public.edge_risk','public.incidents','public.notification_outbox',
        'awaaz_private.moderators','awaaz_private.report_reviews','awaaz_private.road_graphs','awaaz_private.road_edges','awaaz_private.road_publications',
        'awaaz_private.report_commands','awaaz_private.account_quotas','awaaz_private.sos_preferences','awaaz_private.sos_grants','awaaz_private.sos_positions','awaaz_private.sos_request_cancellations','auth.users'])
        AND pg_catalog.has_table_privilege(current_user,c.oid,'SELECT,INSERT,UPDATE,DELETE'))
      AND pg_catalog.has_function_privilege(current_user,'awaaz_private.graph_import(text,jsonb)','EXECUTE')
      AND NOT pg_catalog.has_function_privilege(current_user,'awaaz_private.moderation_command(uuid,text,jsonb)','EXECUTE')
      AND NOT pg_catalog.has_function_privilege(current_user,'awaaz_private.people_command(uuid,text,jsonb)','EXECUTE')
      AND NOT pg_catalog.has_function_privilege(current_user,'awaaz_private.community_command(uuid,text,jsonb)','EXECUTE')
      AND NOT EXISTS(SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname='awaaz_private' AND p.proname=ANY(ARRAY['sos_command','cleanup_sos','sos_grant_live','sos_cancel_jobs','sos_grant_changed','sos_access_changed','sos_control','sos_view','sos_finish'])
        AND pg_catalog.has_function_privilege(current_user,p.oid,'EXECUTE'))
      AND NOT EXISTS(SELECT 1 FROM unnest(ARRAY['public.incidents','public.notification_outbox','awaaz_private.sos_preferences','awaaz_private.sos_grants','awaaz_private.sos_positions','awaaz_private.sos_request_cancellations']) name
        WHERE pg_catalog.has_any_column_privilege(current_user,name,'SELECT,INSERT,UPDATE,REFERENCES')) AS allowed`);
    return result.rows[0]?.allowed === true;
  } catch {
    return false;
  }
}
