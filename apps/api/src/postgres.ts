import { Pool } from 'pg';
import { DomainError, IdempotencyConflict } from './contracts.ts';
import { postgresEvidence } from './evidence.ts';
import type { ShareDeviceStore, ShareDeviceState } from './share_devices.ts';
import type { SosStore } from './sos.ts';
import type {
  SharingStore,
  ShareReceipt,
  ShareControl,
  SharePositionReceipt,
  SharedTrip,
  IncomingShares,
} from './sharing.ts';
import type { EvidenceStore } from './evidence.ts';
import type {
  PeopleStore,
  CommunityStore,
  ReportStore,
  Profile,
  Circle,
  CircleDetail,
  InviteReceipt,
  IncomingInvite,
  ReportReceipt,
  PrivateReport,
  ReportCursor,
  PublicEvent,
  ModerationStore,
  ReviewReceipt,
  RoadCandidates,
  PublicationReceipt,
  BlockState,
  BlockReceipt,
  BlockPage,
} from './contracts.ts';

export interface SqlExecutor {
  query(text: string, values?: unknown[]): Promise<{ rows: Record<string, unknown>[] }>;
}
const errors: Record<string, number> = {
  unauthenticated: 401,
  profile_required: 403,
  verification_required: 403,
  not_found: 404,
  invalid_request: 400,
  invalid_report: 400,
  invalid_cursor: 400,
  invalid_bounds: 400,
  outside_pilot: 422,
  idempotency_conflict: 409,
  already_member: 409,
  invite_pending: 409,
  owner_cannot_leave: 409,
  members_limit_reached: 409,
  circles_limit_reached: 409,
  invite_unavailable: 410,
  circle_closed: 410,
  invite_reissue_required: 409,
  block_changed: 409,
  blocks_limit_reached: 409,
  block_version_exhausted: 409,
  rate_limited: 429,
  moderator_required: 403,
  self_review_forbidden: 403,
  already_reviewed: 409,
  stale_report: 409,
  graph_not_ready: 503,
  report_not_approved: 409,
  already_published: 409,
  edge_not_near_report: 422,
  share_recipient_unavailable: 409,
  share_already_active: 409,
  share_unavailable: 410,
  stale_position: 409,
  device_revoked: 403,
  device_already_bound: 409,
  native_publisher_active: 409,
  sos_preference_changed: 409,
  sos_response_changed: 409,
  sos_recipient_unavailable: 409,
  incident_already_active: 409,
  incident_unavailable: 410,
};
function persistenceError(error: unknown): never {
  if (typeof error === 'object' && error !== null && 'code' in error) {
    const code = String(error.code);
    const message = 'message' in error ? String(error.message) : '';
    if (code === 'P0001' && errors[message]) {
      if (message === 'idempotency_conflict') throw new IdempotencyConflict();
      throw new DomainError(message, errors[message]!);
    }
    if (['22P02', '22007', '22008', '23502', '23514', '22023'].includes(code))
      throw new DomainError('invalid_request', 400);
    if (code === '23503') throw new DomainError('not_found', 404);
  }
  // Never carry a driver's SQL text, connection string, detail or stack to HTTP.
  throw new Error('Database operation unavailable');
}

export function postgresStores(db: SqlExecutor): {
  people: PeopleStore;
  community: CommunityStore;
  reports: ReportStore;
  moderation: ModerationStore;
  evidence: EvidenceStore;
  sharing: SharingStore;
  shareDevices: ShareDeviceStore;
  sos: SosStore;
  ready: () => Promise<boolean>;
} {
  async function rpc<T>(
    area: 'people' | 'community' | 'moderation' | 'sharing' | 'sos',
    actor: string,
    operation: string,
    data: unknown = {},
  ): Promise<T> {
    const sql =
      area === 'people'
        ? 'SELECT awaaz_private.people_command($1::uuid,$2::text,$3::jsonb) AS result'
        : area === 'community'
          ? 'SELECT awaaz_private.community_command($1::uuid,$2::text,$3::jsonb) AS result'
          : area === 'sharing'
            ? 'SELECT awaaz_private.sharing_command($1::uuid,$2::text,$3::jsonb) AS result'
            : area === 'sos'
              ? 'SELECT awaaz_private.sos_command($1::uuid,$2::text,$3::jsonb) AS result'
              : 'SELECT awaaz_private.moderation_command($1::uuid,$2::text,$3::jsonb) AS result';
    try {
      const result = await db.query(sql, [actor, operation, data]);
      if (!result.rows[0] || !Object.hasOwn(result.rows[0], 'result'))
        throw new Error('Missing operation result');
      return result.rows[0].result as T;
    } catch (error) {
      return persistenceError(error);
    }
  }
  async function deviceRpc<T>(
    hash: string,
    shareId: string,
    operation: string,
    data: unknown = {},
  ): Promise<T> {
    try {
      const result = await db.query(
        'SELECT awaaz_private.share_device_command($1::text,$2::uuid,$3::text,$4::jsonb) AS result',
        [hash, shareId, operation, data],
      );
      if (!result.rows[0]?.result) throw new Error('Missing device result');
      return result.rows[0].result as T;
    } catch (error) {
      return persistenceError(error);
    }
  }
  return {
    sos: {
      preference: (actor) => rpc('sos', actor, 'get_preference'),
      setPreference: (actor, input) => rpc('sos', actor, 'set_preference', input),
      eligible: (actor, circleId) => rpc('sos', actor, 'eligible', { circleId }),
      create: (actor, input, hash) => rpc('sos', actor, 'create', { ...input, payloadHash: hash }),
      current: (actor) => rpc('sos', actor, 'current'),
      request: (actor, clientRequestId) => rpc('sos', actor, 'request', { clientRequestId }),
      cancelRequest: (actor, clientRequestId) =>
        rpc('sos', actor, 'cancel_request', { clientRequestId }),
      view: (actor, incidentId) => rpc('sos', actor, 'view', { incidentId }),
      incoming: (actor, limit, after) => rpc('sos', actor, 'incoming', { limit, after }),
      respond: (actor, incidentId, input) =>
        rpc('sos', actor, 'response', { incidentId, ...input }),
      decline: (actor, incidentId) => rpc('sos', actor, 'decline', { incidentId }),
      end: (actor, incidentId, outcome) => rpc('sos', actor, 'end', { incidentId, outcome }),
      position: (actor, incidentId, input, hash) =>
        rpc('sos', actor, 'position', { incidentId, ...input, payloadHash: hash }),
      cleanupExpired: async () => {
        try {
          const result = await db.query('SELECT awaaz_private.cleanup_sos() AS result');
          if (!result.rows[0]?.result) throw new Error('Missing cleanup result');
          return result.rows[0].result as { positionsDeleted: number; grantsDeleted: number };
        } catch (error) {
          return persistenceError(error);
        }
      },
    },
    shareDevices: {
      owner: async (actor, shareId, operation, hash) => {
        try {
          const result = await db.query(
            'SELECT awaaz_private.share_device_owner($1::uuid,$2::uuid,$3::text,$4::text) AS result',
            [actor, shareId, operation, hash ?? null],
          );
          if (!result.rows[0]?.result) throw new Error('Missing device receipt');
          return result.rows[0].result as ShareDeviceState;
        } catch (error) {
          return persistenceError(error);
        }
      },
      state: (hash, shareId) => deviceRpc<ShareDeviceState>(hash, shareId, 'state'),
      position: (hash, shareId, input, payloadHash) =>
        deviceRpc<SharePositionReceipt>(hash, shareId, 'position', { ...input, payloadHash }),
      stop: (hash, shareId) => deviceRpc<ShareDeviceState>(hash, shareId, 'stop'),
    },
    sharing: {
      create: (actor, input, hash) =>
        rpc<ShareReceipt>('sharing', actor, 'create', { ...input, payloadHash: hash }),
      current: (actor) => rpc<{ share: ShareControl | null }>('sharing', actor, 'current'),
      request: (actor, clientRequestId) =>
        rpc<ShareControl>('sharing', actor, 'request', { clientRequestId }),
      view: (actor, shareId) => rpc<SharedTrip>('sharing', actor, 'view', { shareId }),
      incoming: (actor, limit, after) =>
        rpc<IncomingShares>('sharing', actor, 'incoming', { limit, after }),
      position: (actor, shareId, input, hash) =>
        rpc<SharePositionReceipt>('sharing', actor, 'position', {
          shareId,
          ...input,
          payloadHash: hash,
        }),
      stop: (actor, shareId) => rpc<ShareControl>('sharing', actor, 'stop', { shareId }),
      revoke: (actor, shareId, recipientId) =>
        rpc<{ shareId: string; userId: string; status: 'revoked' }>('sharing', actor, 'revoke', {
          shareId,
          recipientId,
        }),
      cleanupExpired: async () => {
        try {
          const result = await db.query('SELECT awaaz_private.cleanup_trip_sharing() AS result');
          if (!result.rows[0] || !Object.hasOwn(result.rows[0], 'result'))
            throw new Error('Missing cleanup result');
          const counts = result.rows[0].result as {
            positionsDeleted?: unknown;
            grantsDeleted?: unknown;
          };
          if (
            !counts ||
            ![counts.positionsDeleted, counts.grantsDeleted].every(
              (value, index) =>
                typeof value === 'number' &&
                Number.isInteger(value) &&
                value >= 0 &&
                value <= (index === 0 ? 500 : 5000),
            )
          )
            throw new Error('Invalid cleanup result');
          return counts as { positionsDeleted: number; grantsDeleted: number };
        } catch (error) {
          return persistenceError(error);
        }
      },
    },
    evidence: postgresEvidence(db),
    moderation: {
      roadCandidates: (actor, reportId, graphVersion) =>
        rpc<RoadCandidates>('moderation', actor, 'road_candidates', { reportId, graphVersion }),
      publish: (actor, reportId, input, hash) =>
        rpc<PublicationReceipt>('moderation', actor, 'publish', {
          ...input,
          reportId,
          payloadHash: hash,
        }),
      listPending: (actor, limit, after) =>
        rpc<{ items: PrivateReport[]; next: ReportCursor | null }>(
          'moderation',
          actor,
          'list_pending',
          { limit, after },
        ),
      review: (actor, reportId, input, hash) =>
        rpc<ReviewReceipt>('moderation', actor, 'review', {
          ...input,
          reportId,
          payloadHash: hash,
        }),
    },
    people: {
      blockState: (actor, userId) => rpc<BlockState>('people', actor, 'get_block', { userId }),
      setBlock: (actor, userId, input) =>
        rpc<BlockReceipt>('people', actor, 'set_block', { userId, ...input }),
      listBlocks: (actor, limit, after) =>
        rpc<BlockPage>('people', actor, 'list_blocks', { limit, after }),
      getProfile: (actor) => rpc<Profile | null>('people', actor, 'get_profile'),
      putProfile: (actor, input) => rpc<Profile>('people', actor, 'put_profile', input),
      listCircles: (actor) => rpc<{ items: Circle[] }>('people', actor, 'list_circles'),
      createCircle: (actor, input, hash) =>
        rpc<{ circle: Circle; replayed: boolean }>('people', actor, 'create_circle', {
          ...input,
          payloadHash: hash,
        }),
      getCircle: (actor, id) => rpc<CircleDetail>('people', actor, 'get_circle', { id }),
      createInvite: (actor, circleId, input, hash, tokenHash) =>
        rpc<InviteReceipt>('people', actor, 'create_invite', {
          ...input,
          circleId,
          expiresInSeconds: input.expiresInSeconds ?? 86400,
          payloadHash: hash,
          tokenHash,
        }),
      incomingInvites: (actor) =>
        rpc<{ items: IncomingInvite[] }>('people', actor, 'incoming_invites'),
      acceptInvite: (actor, id, tokenHash) =>
        rpc<{ circle: CircleDetail; replayed: boolean }>('people', actor, 'accept_invite', {
          id,
          tokenHash,
        }),
      revokeInvite: (actor, id) =>
        rpc<{ id: string; status: 'revoked' }>('people', actor, 'revoke_invite', { id }),
      removeMember: (actor, circleId, memberId) =>
        rpc<{ circleId: string; userId: string; status: 'revoked' }>(
          'people',
          actor,
          'remove_member',
          { circleId, memberId },
        ),
      closeCircle: (actor, id) =>
        rpc<{ id: string; status: 'closed' }>('people', actor, 'close_circle', { circleId: id }),
    },
    reports: {
      create: (actor, input, hash) =>
        rpc<ReportReceipt>('community', actor, 'create_report', { ...input, payloadHash: hash }),
    },
    community: {
      receipt: (actor, clientRequestId) =>
        rpc<ReportReceipt>('community', actor, 'report_receipt', { clientRequestId }),
      listOwn: (actor, limit, before) =>
        rpc<{ items: PrivateReport[]; next: ReportCursor | null }>(
          'community',
          actor,
          'list_own_reports',
          { limit, before },
        ),
      withdraw: (actor, id) =>
        rpc<{ id: string; status: 'withdrawn' }>('community', actor, 'withdraw_report', { id }),
      listPublished: (actor, limit, bounds) =>
        rpc<{ items: PublicEvent[] }>('community', actor, 'list_published_events', {
          limit,
          ...bounds,
        }),
    },
    ready: async () => {
      try {
        const result = await db.query(`SELECT current_user='awaaz_api'
          AND NOT EXISTS(SELECT 1 FROM pg_catalog.pg_roles WHERE rolname=current_user
            AND (rolsuper OR rolbypassrls OR rolcreatedb OR rolcreaterole OR rolreplication OR rolinherit))
          AND NOT EXISTS(SELECT 1 FROM pg_catalog.pg_auth_members m JOIN pg_catalog.pg_roles r ON r.oid=m.member
            WHERE r.rolname=current_user)
          AND NOT EXISTS(SELECT 1 FROM unnest(ARRAY['public.profiles','public.report_submissions','public.circles',
            'public.circle_members','public.circle_invites','public.notification_outbox','awaaz_private.report_commands',
            'awaaz_private.account_quotas','awaaz_private.user_block_settings','awaaz_private.sos_preferences','awaaz_private.sos_grants','awaaz_private.sos_positions','awaaz_private.sos_request_cancellations','awaaz_private.trip_shares',
            'awaaz_private.trip_share_grants','awaaz_private.trip_share_positions','awaaz_private.trip_share_devices','public.road_events','public.risk_snapshots','public.edge_risk',
            'public.incidents','awaaz_private.moderators','awaaz_private.report_reviews',
            'awaaz_private.road_graphs','awaaz_private.road_edges','awaaz_private.road_publications']) name WHERE pg_catalog.has_table_privilege(current_user,name,'SELECT,INSERT,UPDATE,DELETE'))
          AND pg_catalog.to_regprocedure('awaaz_private.people_command(uuid,text,jsonb)') IS NOT NULL
          AND pg_catalog.to_regprocedure('awaaz_private.community_command(uuid,text,jsonb)') IS NOT NULL
          AND pg_catalog.to_regprocedure('awaaz_private.community_command_v1(uuid,text,jsonb)') IS NOT NULL
          AND NOT pg_catalog.has_function_privilege(current_user,'awaaz_private.community_command_v1(uuid,text,jsonb)','EXECUTE')
          AND pg_catalog.has_function_privilege(current_user,'awaaz_private.people_command(uuid,text,jsonb)','EXECUTE')
          AND pg_catalog.has_function_privilege(current_user,'awaaz_private.sos_command(uuid,text,jsonb)','EXECUTE')
          AND pg_catalog.has_function_privilege(current_user,'awaaz_private.cleanup_sos()','EXECUTE')
          AND NOT EXISTS(SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='awaaz_private' AND p.proname=ANY(ARRAY['sos_grant_live','sos_cancel_jobs','sos_grant_changed','sos_access_changed','sos_control','sos_view','sos_finish'])
            AND pg_catalog.has_function_privilege(current_user,p.oid,'EXECUTE'))
          AND NOT EXISTS(SELECT 1 FROM unnest(ARRAY['public.incidents','public.notification_outbox','awaaz_private.sos_preferences','awaaz_private.sos_grants','awaaz_private.sos_positions','awaaz_private.sos_request_cancellations']) name
            WHERE pg_catalog.has_any_column_privilege(current_user,name,'SELECT,INSERT,UPDATE,REFERENCES'))
          AND NOT pg_catalog.has_function_privilege(current_user,'awaaz_private.people_command_before_blocks(uuid,text,jsonb)','EXECUTE')
          AND NOT pg_catalog.has_function_privilege(current_user,'awaaz_private.blocked_pair(uuid,uuid)','EXECUTE')
          AND NOT pg_catalog.has_function_privilege(current_user,'awaaz_private.block_state(uuid,uuid)','EXECUTE')
          AND pg_catalog.has_function_privilege(current_user,'awaaz_private.sharing_command(uuid,text,jsonb)','EXECUTE')
          AND NOT pg_catalog.has_function_privilege(current_user,'awaaz_private.sharing_command_before_devices(uuid,text,jsonb)','EXECUTE')
          AND pg_catalog.has_function_privilege(current_user,'awaaz_private.cleanup_trip_sharing()','EXECUTE')
          AND pg_catalog.has_function_privilege(current_user,'awaaz_private.share_device_owner(uuid,uuid,text,text)','EXECUTE')
          AND pg_catalog.has_function_privilege(current_user,'awaaz_private.share_device_command(text,uuid,text,jsonb)','EXECUTE')
          AND NOT pg_catalog.has_function_privilege(current_user,'awaaz_private.share_device_control(uuid)','EXECUTE')
          AND NOT pg_catalog.has_function_privilege(current_user,'awaaz_private.share_grant_live(awaaz_private.trip_share_grants)','EXECUTE')
          AND NOT pg_catalog.has_function_privilege(current_user,'awaaz_private.share_control(uuid,uuid)','EXECUTE')
          AND NOT pg_catalog.has_function_privilege(current_user,'awaaz_private.share_view(uuid,uuid)','EXECUTE')
          AND NOT pg_catalog.has_function_privilege(current_user,'awaaz_private.rotate_membership_consent()','EXECUTE')
          AND NOT pg_catalog.has_function_privilege(current_user,'awaaz_private.revoke_membership_shares()','EXECUTE')
          AND NOT pg_catalog.has_function_privilege(current_user,'awaaz_private.revoke_closed_circle_shares()','EXECUTE')
          AND NOT pg_catalog.has_function_privilege(current_user,'awaaz_private.revoke_blocked_shares()','EXECUTE')
          AND pg_catalog.has_function_privilege(current_user,'awaaz_private.community_command(uuid,text,jsonb)','EXECUTE')
          AND pg_catalog.has_function_privilege(current_user,'awaaz_private.moderation_command(uuid,text,jsonb)','EXECUTE')
          AND NOT pg_catalog.has_function_privilege(current_user,'awaaz_private.moderation_command_v1(uuid,text,jsonb)','EXECUTE')
          AND NOT pg_catalog.has_function_privilege(current_user,'awaaz_private.graph_import(text,jsonb)','EXECUTE')
          AND pg_catalog.has_function_privilege(current_user,'awaaz_private.current_evidence_snapshot(text)','EXECUTE')
          AND pg_catalog.has_function_privilege(current_user,'awaaz_private.read_evidence_snapshot(uuid,integer)','EXECUTE')
          AND pg_catalog.has_function_privilege(current_user,'awaaz_private.read_evidence_edge(uuid,integer)','EXECUTE')
          AND NOT pg_catalog.has_function_privilege(current_user,'awaaz_private.build_evidence_snapshot(text)','EXECUTE') AS ready`);
        return result.rows[0]?.ready === true;
      } catch {
        return false;
      }
    },
  };
}

export function createDatabasePool(
  connectionString: string,
  ca?: string,
  role: 'awaaz_api' | 'awaaz_evidence' = 'awaaz_api',
): Pool {
  let url: URL;
  try {
    url = new URL(connectionString);
  } catch {
    throw new Error('Invalid DATABASE_URL');
  }
  if (
    !['postgres:', 'postgresql:'].includes(url.protocol) ||
    !url.hostname ||
    !url.password ||
    decodeURIComponent(url.username).split('.')[0] !== role
  )
    throw new Error(`DATABASE_URL must use the dedicated ${role} role`);
  if (
    [...url.searchParams.keys()].some(
      (name) => name.toLowerCase().startsWith('ssl') || name.toLowerCase() === 'uselibpqcompat',
    )
  ) {
    throw new Error(
      'Remove SSL query parameters from DATABASE_URL; TLS verification is configured by the API',
    );
  }
  const loopback = ['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname);
  const pool = new Pool({
    connectionString,
    max: role === 'awaaz_evidence' ? 2 : 6,
    connectionTimeoutMillis: 5000,
    idleTimeoutMillis: 30_000,
    query_timeout: 10_000,
    application_name: role === 'awaaz_api' ? 'awaaz-api' : 'awaaz-evidence',
    ssl: loopback ? false : { rejectUnauthorized: true, ...(ca ? { ca } : {}) },
  });
  // Idle errors must be handled. Readiness and commands report failures safely.
  pool.on('error', () => {});
  return pool;
}
