import Fastify, { LogController } from 'fastify';
import type { FastifyRequest, FastifyReply, FastifyServerOptions } from 'fastify';
import rateLimit from '@fastify/rate-limit';
import cors from '@fastify/cors';
import swagger from '@fastify/swagger';
import { DomainError } from './contracts.ts';
import type {
  Dependencies,
  Principal,
  ReportInput,
  ProfileInput,
  CircleInput,
  InviteInput,
  ReviewInput,
  PublicationInput,
  BlockInput,
} from './contracts.ts';
import * as s from './schemas.ts';
import { payloadHash, tokenHash, encodeCursor, decodeCursor } from './security.ts';
import type { RouteInput } from './routing.ts';
import { placeKinds } from './places.ts';
import { registerSharingRoutes, SharingCleanup } from './sharing.ts';
import { registerShareDeviceRoutes } from './share_devices.ts';
import { registerSosRoutes } from './sos.ts';

export { IdempotencyConflict } from './contracts.ts';
export type {
  Principal,
  ReportInput,
  ReportReceipt,
  ReportStore,
  Dependencies,
} from './contracts.ts';
type ServerOptions = { logger?: FastifyServerOptions['logger']; allowedOrigins?: string[] };
type Id = { circleId: string };
type InviteId = { inviteId: string };
const response = (value: unknown) => ({ 200: value, ...s.errors });
const createdResponse = (value: unknown) => ({ 200: value, 201: value, ...s.errors });
const idParams = s.object({ circleId: s.uuid });
const inviteParams = s.object({ inviteId: s.uuid });

export async function buildServer(deps: Dependencies, options: ServerOptions = {}) {
  const app = Fastify({
    bodyLimit: 16_384,
    logger: options.logger ?? false,
    logController: new LogController({ disableRequestLogging: true }),
    requestTimeout: 30_000,
    connectionTimeout: 10_000,
    keepAliveTimeout: 5_000,
    ajv: { customOptions: { removeAdditional: false, coerceTypes: false } },
  });
  const sharingCleanup = deps.sharing ? new SharingCleanup(deps.sharing) : undefined;
  const sosCleanup = deps.sos ? new SharingCleanup(deps.sos) : undefined;
  if (sharingCleanup) app.addHook('onReady', () => sharingCleanup.start());
  if (sosCleanup) app.addHook('onReady', () => sosCleanup.start());
  const principals = new WeakMap<object, Principal>();
  await app.register(swagger, {
    openapi: {
      openapi: '3.1.0',
      info: {
        title: 'Awaaz API',
        version: '0.2.0',
        description:
          'Adult Dhaka pilot backend. Membership grants no location access. Optional geographic routing has unknown safety coverage. SOS delivery is not connected.',
      },
      components: {
        securitySchemes: {
          bearerAuth: { type: 'http', scheme: 'bearer', bearerFormat: 'Supabase access token' },
          shareDeviceAuth: {
            type: 'http',
            scheme: 'bearer',
            bearerFormat: 'Awaaz scoped share credential',
          },
        },
      },
    },
  });
  await app.register(cors, {
    origin: options.allowedOrigins?.length ? options.allowedOrigins : false,
    credentials: false,
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Authorization', 'Content-Type'],
  });
  await app.register(rateLimit, { global: false });
  const limit = (max: number, keyGenerator: (request: FastifyRequest) => string) => {
    const check = app.createRateLimit({ max, timeWindow: '1 minute', keyGenerator });
    return async (request: FastifyRequest, reply: FastifyReply) => {
      const result = await check(request);
      if (!result.isAllowed && result.isExceeded) {
        reply.header('retry-after', result.ttlInSeconds);
        throw new DomainError('rate_limited', 429);
      }
    };
  };
  // Shared mobile/Wi-Fi addresses get a coarse pre-auth gate; business limits
  // belong to verified accounts. Separate counters must all run on each request.
  app.addHook(
    'onRequest',
    limit(600, (request) => `ip:${request.ip}`),
  );
  const accountLimit = limit(120, (request) => `account:${principals.get(request)!.id}`);
  const reportLimit = limit(20, (request) => `report:${principals.get(request)!.id}`);
  app.addHook('preHandler', async (request, reply) => {
    if (principals.has(request)) await accountLimit(request, reply);
  });
  app.addHook('onSend', async (request, reply) => {
    reply.header('x-request-id', request.id);
    if (request.url.startsWith('/v1/') || request.url.startsWith('/ready'))
      reply.header('cache-control', 'no-store');
  });
  app.addHook('onResponse', async (request, reply) => {
    // Route template only: no private IDs, URLs, query strings, bodies or tokens.
    app.log.info(
      {
        requestId: request.id,
        method: request.method,
        route: request.routeOptions.url ?? 'unmatched',
        statusCode: reply.statusCode,
      },
      'request complete',
    );
  });

  const authenticate =
    (verifiedPhone = false) =>
    async (request: FastifyRequest, reply: FastifyReply) => {
      const header = request.headers.authorization;
      if (!header || header.length > 8192 || !/^Bearer \S+$/.test(header))
        return reply.code(401).send({ code: 'unauthenticated' });
      let principal: Principal | null;
      try {
        principal = await deps.verifyToken(header.slice(7));
      } catch {
        return reply.code(503).send({ code: 'auth_unavailable' });
      }
      if (!principal) return reply.code(401).send({ code: 'unauthenticated' });
      if (verifiedPhone && !principal.phoneVerified)
        return reply.code(403).send({ code: 'verification_required' });
      principals.set(request, principal);
    };
  const actor = (request: FastifyRequest) => principals.get(request)!.id;
  const authSchema = { security: [{ bearerAuth: [] }] };

  app.get(
    '/health',
    {
      schema: {
        tags: ['Operations'],
        response: response(s.object({ service: s.text, status: s.text, version: s.text })),
      },
    },
    async () => ({ service: 'awaaz-api', status: 'ok', version: '0.2.0' }),
  );
  app.get(
    '/ready',
    {
      schema: {
        tags: ['Operations'],
        response: { 200: s.object({ status: s.text }), 503: s.object({ status: s.text }) },
      },
    },
    async (_request, reply) => {
      let ready = false;
      try {
        ready =
          ((await deps.ready?.()) ?? false) &&
          (sharingCleanup?.ready() ?? true) &&
          (sosCleanup?.ready() ?? true);
      } catch {
        /* No infrastructure detail is returned. */
      }
      return reply.code(ready ? 200 : 503).send({ status: ready ? 'ready' : 'not_ready' });
    },
  );
  app.get('/openapi.json', { schema: { hide: true } }, async () => app.swagger());

  app.get(
    '/v1/routing/status',
    {
      schema: {
        tags: ['Routing'],
        response: response(s.object({ enabled: s.boolean, ready: s.boolean })),
      },
    },
    async () => ({
      enabled: !!deps.routing,
      ready: deps.routing ? await deps.routing.ready() : false,
    }),
  );
  app.post<{ Body: { query: string } }>(
    '/v1/places/search',
    {
      preHandler: limit(60, (request) => `places:${request.ip}`),
      schema: {
        tags: ['Routing'],
        description:
          'Search imported public OSM names. No GPS, query history or verified entrance is supplied.',
        body: s.object({ query: { type: 'string', minLength: 2, maxLength: 80 } }),
        response: response(
          s.object({
            graphVersion: s.graphVersion,
            datasetVersion: { type: 'string', pattern: '^dhaka-places-v1-[0-9a-f]{20}$' },
            sourceTimestamp: s.date,
            source: { type: 'string', const: 'openstreetmap' },
            attribution: { type: 'string', const: '© OpenStreetMap contributors' },
            license: { type: 'string', const: 'ODbL-1.0' },
            coverage: { type: 'string', const: 'imported_places_only' },
            items: {
              type: 'array',
              maxItems: 8,
              items: s.object({
                id: { type: 'string', pattern: '^osm:(node|way|relation):[1-9][0-9]{0,19}$' },
                name: { type: 'string', maxLength: 160 },
                nameEn: { type: 'string', maxLength: 160 },
                nameBn: { type: 'string', maxLength: 160 },
                kind: { type: 'string', enum: placeKinds },
                point: s.object({
                  latitude: { type: 'number', minimum: 23.62, maximum: 24.02 },
                  longitude: { type: 'number', minimum: 90.2, maximum: 90.58 },
                }),
              }),
            },
          }),
        ),
      },
    },
    async (request) => {
      if (!deps.places) throw new DomainError('places_unavailable', 503);
      return deps.places.search(request.body.query);
    },
  );
  app.post<{ Body: RouteInput }>(
    '/v1/routes',
    {
      preHandler: limit(30, (request) => `routing:${request.ip}`),
      schema: {
        tags: ['Routing'],
        description:
          'Ephemeral geographic route planning. No trip history, traffic ETA, safety score or contact sharing is created.',
        body: s.routeInput,
        response: response(s.geographicPlan),
      },
    },
    async (request, reply) => {
      if (!deps.routing) throw new DomainError('routing_not_configured', 503);
      const cancellation = new AbortController();
      const abandoned = () => {
        if (!reply.raw.writableEnded) cancellation.abort();
      };
      request.raw.once('aborted', abandoned);
      reply.raw.once('close', abandoned);
      try {
        return await deps.routing.plan(request.body, cancellation.signal);
      } finally {
        request.raw.removeListener('aborted', abandoned);
        reply.raw.removeListener('close', abandoned);
      }
    },
  );

  app.get(
    '/v1/routing/evidence/status',
    {
      schema: {
        tags: ['Routing'],
        description:
          'Availability of reviewed evidence for the configured real graph. Experimental reported-route comparison may consume this snapshot; safety assessment remains unknown.',
        response: response(
          s.object({
            available: s.boolean,
            safetyAssessment: { type: 'string', const: 'unknown' },
            snapshot: s.nullable(
              s.object({
                id: s.uuid,
                graphVersion: s.graphVersion,
                createdAt: s.date,
                expiresAt: s.date,
                registeredEdgeCount: { type: 'integer' },
                evidencedEdgeCount: { type: 'integer' },
              }),
            ),
          }),
        ),
      },
    },
    async () => {
      const version = deps.routing?.graphVersion;
      const current = version && deps.evidence ? await deps.evidence.current(version) : null;
      if (!current || !deps.evidence)
        return { available: false, safetyAssessment: 'unknown', snapshot: null };
      const { metadata } = await deps.evidence.read(current.id);
      if (metadata.graphVersion !== version) throw new DomainError('evidence_unavailable', 503);
      return {
        available: true,
        safetyAssessment: 'unknown',
        snapshot: {
          id: metadata.id,
          graphVersion: metadata.graphVersion,
          createdAt: metadata.createdAt,
          expiresAt: metadata.expiresAt,
          registeredEdgeCount: metadata.registeredEdgeCount,
          evidencedEdgeCount: metadata.evidencedEdgeCount,
        },
      };
    },
  );

  app.post<{ Body: ReportInput }>(
    '/v1/reports',
    {
      preHandler: reportLimit,
      onRequest: authenticate(true),
      schema: {
        ...authSchema,
        tags: ['Community'],
        body: s.reportInput,
        response: createdResponse(s.receipt),
      },
    },
    async (request, reply) => {
      const input = {
        ...request.body,
        clientRequestId: request.body.clientRequestId.toLowerCase(),
        description: request.body.description.normalize('NFC').trim(),
        observedAt: new Date(request.body.observedAt).toISOString(),
      };
      const age = (deps.now?.() ?? new Date()).getTime() - Date.parse(input.observedAt);
      if ([...input.description].length < 10 || age < -300_000 || age > 72 * 3_600_000)
        throw new DomainError('invalid_report', 400);
      if (
        input.latitude < 23.62 ||
        input.latitude > 24.02 ||
        input.longitude < 90.2 ||
        input.longitude > 90.58
      )
        throw new DomainError('outside_pilot', 422);
      const hash = payloadHash([
        input.category,
        input.description,
        input.latitude,
        input.longitude,
        input.observedAt,
      ]);
      const receipt = await deps.reports.create(actor(request), input, hash);
      return reply.code(receipt.replayed ? 200 : 201).send(receipt);
    },
  );

  const moderation = deps.moderation;
  if (moderation) {
    app.get<{ Params: { reportId: string }; Querystring: { graphVersion: string } }>(
      '/v1/moderation/reports/:reportId/road-candidates',
      {
        onRequest: authenticate(true),
        schema: {
          ...authSchema,
          tags: ['Moderation'],
          description:
            'Private nearby edges from a registered immutable graph. Human selection is required; proximity does not verify an incident.',
          params: s.object({ reportId: s.uuid }),
          querystring: s.object({ graphVersion: s.graphVersion }),
          response: response(s.roadCandidates),
        },
      },
      async (request) =>
        moderation.roadCandidates(
          actor(request),
          request.params.reportId.toLowerCase(),
          request.query.graphVersion,
        ),
    );
    app.post<{ Params: { reportId: string }; Body: PublicationInput }>(
      '/v1/moderation/reports/:reportId/publications',
      {
        onRequest: authenticate(true),
        preHandler: limit(20, (request) => `publication:${actor(request)}`),
        schema: {
          ...authSchema,
          tags: ['Moderation'],
          params: s.object({ reportId: s.uuid }),
          body: s.publicationInput,
          description:
            'Explicitly associate a live approved report with an actual edge within 35 metres. Publishes fixed-vocabulary coarse evidence, never a safety score.',
          response: createdResponse(s.publicationReceipt),
        },
      },
      async (request, reply) => {
        const reportId = request.params.reportId.toLowerCase();
        const input = {
          ...request.body,
          clientRequestId: request.body.clientRequestId.toLowerCase(),
        };
        const receipt = await moderation.publish(
          actor(request),
          reportId,
          input,
          payloadHash([reportId, input.graphVersion, input.edgeId]),
        );
        return reply.code(receipt.replayed ? 200 : 201).send(receipt);
      },
    );
    app.get<{ Querystring: { limit?: string; cursor?: string } }>(
      '/v1/moderation/reports',
      {
        onRequest: authenticate(true),
        schema: {
          ...authSchema,
          tags: ['Moderation'],
          description:
            'Administrator-provisioned moderators only. Private pending submissions; oldest first. No reporter identity is returned.',
          querystring: s.object(
            {
              limit: { type: 'string', pattern: '^(?:[1-9]|[1-4][0-9]|50)$' },
              cursor: { type: 'string', maxLength: 512 },
            },
            [],
          ),
          response: response(
            s.object({ items: s.array(s.privateReport), nextCursor: s.nullable(s.text) }),
          ),
        },
      },
      async (request) => {
        const result = await moderation.listPending(
          actor(request),
          Number(request.query.limit ?? 20),
          decodeCursor(request.query.cursor),
        );
        return { items: result.items, nextCursor: encodeCursor(result.next) };
      },
    );
    app.post<{ Params: { reportId: string }; Body: ReviewInput }>(
      '/v1/moderation/reports/:reportId/reviews',
      {
        onRequest: authenticate(true),
        preHandler: limit(30, (request) => `moderation:${actor(request)}`),
        schema: {
          ...authSchema,
          tags: ['Moderation'],
          description:
            'Audited idempotent approve/reject decision. Approval stays private pending real graph association; it does not publish an event or safety score.',
          params: s.object({ reportId: s.uuid }),
          body: s.reviewInput,
          response: createdResponse(s.reviewReceipt),
        },
      },
      async (request, reply) => {
        const reportId = request.params.reportId.toLowerCase();
        const input = {
          ...request.body,
          clientRequestId: request.body.clientRequestId.toLowerCase(),
        };
        if ((input.decision === 'approve') !== (input.reason === 'reviewed'))
          throw new DomainError('invalid_request', 400);
        const receipt = await moderation.review(
          actor(request),
          reportId,
          input,
          payloadHash([reportId, input.decision, input.reason]),
        );
        return reply.code(receipt.replayed ? 200 : 201).send(receipt);
      },
    );
  }

  const people = deps.people;
  if (people) {
    if (!deps.inviteToken) throw new Error('People endpoints require an invite token factory');
    const makeToken = deps.inviteToken;
    app.get<{ Querystring: { limit?: string; after?: string } }>(
      '/v1/me/blocks',
      {
        onRequest: authenticate(),
        schema: {
          ...authSchema,
          tags: ['Account'],
          description:
            'Private outgoing block decisions only. Membership and old invitations are not restored by unblocking.',
          querystring: s.object(
            { limit: { type: 'string', pattern: '^(?:[1-9]|[1-4][0-9]|50)$' }, after: s.uuid },
            [],
          ),
          response: response(s.blockPage),
        },
      },
      async (request) =>
        people.listBlocks(
          actor(request),
          Number(request.query.limit ?? '30'),
          request.query.after?.toLowerCase() ?? null,
        ),
    );
    app.get<{ Params: { userId: string } }>(
      '/v1/me/blocks/:userId',
      {
        onRequest: authenticate(),
        schema: {
          ...authSchema,
          tags: ['Account'],
          params: s.object({ userId: s.uuid }),
          response: response(s.blockState),
        },
      },
      async (request) => people.blockState(actor(request), request.params.userId.toLowerCase()),
    );
    app.put<{ Params: { userId: string }; Body: BlockInput }>(
      '/v1/me/blocks/:userId',
      {
        onRequest: authenticate(),
        schema: {
          ...authSchema,
          tags: ['Account'],
          params: s.object({ userId: s.uuid }),
          body: s.blockInput,
          description:
            'Version-conditional block/unblock. A stale decision conflicts; it never overrides a newer choice. A successful block disconnects shared circles and revokes conflicting invitations atomically.',
          response: response(s.blockReceipt),
        },
      },
      async (request) =>
        people.setBlock(actor(request), request.params.userId.toLowerCase(), request.body),
    );
    app.get(
      '/v1/me',
      {
        onRequest: authenticate(),
        schema: {
          ...authSchema,
          tags: ['Account'],
          response: response(
            s.object({ userId: s.uuid, phoneVerified: s.boolean, profile: s.nullable(s.profile) }),
          ),
        },
      },
      async (request) => ({
        userId: actor(request),
        phoneVerified: principals.get(request)!.phoneVerified,
        profile: await people.getProfile(actor(request)),
      }),
    );
    app.put<{ Body: ProfileInput }>(
      '/v1/me',
      {
        onRequest: authenticate(),
        schema: {
          ...authSchema,
          tags: ['Account'],
          body: s.profileInput,
          response: response(s.profile),
        },
      },
      async (request) => {
        const input = {
          ...request.body,
          displayName: request.body.displayName.normalize('NFC').trim(),
        };
        if (!input.displayName) throw new DomainError('invalid_request', 400);
        return people.putProfile(actor(request), input);
      },
    );
    app.get(
      '/v1/circles',
      {
        onRequest: authenticate(),
        schema: {
          ...authSchema,
          tags: ['Circle'],
          response: response(s.object({ items: s.array(s.circle) })),
        },
      },
      async (request) => people.listCircles(actor(request)),
    );
    app.post<{ Body: CircleInput }>(
      '/v1/circles',
      {
        onRequest: authenticate(),
        schema: {
          ...authSchema,
          tags: ['Circle'],
          body: s.circleInput,
          response: createdResponse(s.circleCreated),
        },
      },
      async (request, reply) => {
        const input = {
          ...request.body,
          clientRequestId: request.body.clientRequestId.toLowerCase(),
          name: request.body.name.normalize('NFC').trim(),
        };
        if (!input.name) throw new DomainError('invalid_request', 400);
        const result = await people.createCircle(
          actor(request),
          input,
          payloadHash(['circle.create', input.name]),
        );
        return reply.code(result.replayed ? 200 : 201).send(result);
      },
    );
    app.get<{ Params: Id }>(
      '/v1/circles/:circleId',
      {
        onRequest: authenticate(),
        schema: {
          ...authSchema,
          tags: ['Circle'],
          params: idParams,
          response: response(s.circleDetail),
        },
      },
      async (request) => people.getCircle(actor(request), request.params.circleId.toLowerCase()),
    );
    app.post<{ Params: Id; Body: InviteInput }>(
      '/v1/circles/:circleId/invites',
      {
        onRequest: authenticate(),
        schema: {
          ...authSchema,
          tags: ['Circle'],
          params: idParams,
          body: s.inviteInput,
          response: createdResponse(s.invite),
        },
      },
      async (request, reply) => {
        const circleId = request.params.circleId.toLowerCase();
        const input = {
          ...request.body,
          clientRequestId: request.body.clientRequestId.toLowerCase(),
          recipientId: request.body.recipientId.toLowerCase(),
          expiresInSeconds: request.body.expiresInSeconds ?? 86400,
        };
        if (input.recipientId === actor(request)) throw new DomainError('invalid_request', 400);
        const token = makeToken(actor(request), circleId, input.clientRequestId);
        const result = await people.createInvite(
          actor(request),
          circleId,
          input,
          payloadHash(['invite.create', circleId, input.recipientId, input.expiresInSeconds]),
          tokenHash(token),
        );
        return reply.code(result.replayed ? 200 : 201).send({ ...result, token });
      },
    );
    app.get(
      '/v1/circle-invites',
      {
        onRequest: authenticate(),
        schema: {
          ...authSchema,
          tags: ['Circle'],
          response: response(s.object({ items: s.array(s.incomingInvite) })),
        },
      },
      async (request) => people.incomingInvites(actor(request)),
    );
    app.post<{ Params: InviteId; Body: { token: string } }>(
      '/v1/circle-invites/:inviteId/accept',
      {
        onRequest: authenticate(),
        schema: {
          ...authSchema,
          tags: ['Circle'],
          params: inviteParams,
          body: s.inviteToken,
          response: response(s.inviteAccepted),
        },
      },
      async (request) =>
        people.acceptInvite(
          actor(request),
          request.params.inviteId.toLowerCase(),
          tokenHash(request.body.token),
        ),
    );
    app.delete<{ Params: InviteId }>(
      '/v1/circle-invites/:inviteId',
      {
        onRequest: authenticate(),
        schema: {
          ...authSchema,
          tags: ['Circle'],
          params: inviteParams,
          response: response(
            s.object({ id: s.uuid, status: { const: 'revoked', type: 'string' } }),
          ),
        },
      },
      async (request) => people.revokeInvite(actor(request), request.params.inviteId.toLowerCase()),
    );
    app.delete<{ Params: Id & { memberId: string } }>(
      '/v1/circles/:circleId/members/:memberId',
      {
        onRequest: authenticate(),
        schema: {
          ...authSchema,
          tags: ['Circle'],
          params: s.object({ circleId: s.uuid, memberId: s.uuid }),
          response: response(
            s.object({
              circleId: s.uuid,
              userId: s.uuid,
              status: { const: 'revoked', type: 'string' },
            }),
          ),
        },
      },
      async (request) =>
        people.removeMember(
          actor(request),
          request.params.circleId.toLowerCase(),
          request.params.memberId.toLowerCase(),
        ),
    );
    app.delete<{ Params: Id }>(
      '/v1/circles/:circleId',
      {
        onRequest: authenticate(),
        schema: {
          ...authSchema,
          tags: ['Circle'],
          params: idParams,
          response: response(s.object({ id: s.uuid, status: { const: 'closed', type: 'string' } })),
        },
      },
      async (request) => people.closeCircle(actor(request), request.params.circleId.toLowerCase()),
    );
  }
  const community = deps.community;
  if (community) {
    app.get<{ Params: { clientRequestId: string } }>(
      '/v1/report-requests/:clientRequestId',
      {
        onRequest: authenticate(),
        schema: {
          ...authSchema,
          tags: ['Community'],
          params: s.object({ clientRequestId: s.uuid }),
          response: response(s.receipt),
        },
      },
      async (request) =>
        community.receipt(actor(request), request.params.clientRequestId.toLowerCase()),
    );
    app.get<{ Querystring: { limit: string; cursor?: string } }>(
      '/v1/reports',
      {
        onRequest: authenticate(),
        schema: {
          ...authSchema,
          tags: ['Community'],
          querystring: s.reportsQuery,
          response: response(
            s.object({ items: s.array(s.privateReport), nextCursor: s.nullable(s.text) }),
          ),
        },
      },
      async (request) => {
        const result = await community.listOwn(
          actor(request),
          Number(request.query.limit),
          decodeCursor(request.query.cursor),
        );
        return { items: result.items, nextCursor: encodeCursor(result.next) };
      },
    );
    app.delete<{ Params: { reportId: string } }>(
      '/v1/reports/:reportId',
      {
        onRequest: authenticate(),
        schema: {
          ...authSchema,
          tags: ['Community'],
          params: s.object({ reportId: s.uuid }),
          response: response(
            s.object({ id: s.uuid, status: { type: 'string', const: 'withdrawn' } }),
          ),
        },
      },
      async (request) => community.withdraw(actor(request), request.params.reportId.toLowerCase()),
    );
    app.get<{
      Querystring: { limit: string; south?: string; west?: string; north?: string; east?: string };
    }>(
      '/v1/road-events',
      {
        onRequest: authenticate(),
        schema: {
          ...authSchema,
          tags: ['Community'],
          querystring: s.eventsQuery,
          response: response(s.object({ items: s.array(s.publicEvent) })),
        },
      },
      async (request) => {
        const q = request.query;
        const bounds =
          q.south === undefined
            ? { south: 23.62, west: 90.2, north: 24.02, east: 90.58 }
            : {
                south: Number(q.south),
                west: Number(q.west),
                north: Number(q.north),
                east: Number(q.east),
              };
        if (!(
          bounds.south >= -90 &&
          bounds.north <= 90 &&
          bounds.west >= -180 &&
          bounds.east <= 180 &&
          bounds.south < bounds.north &&
          bounds.west < bounds.east &&
          bounds.north - bounds.south <= 0.6 &&
          bounds.east - bounds.west <= 0.6
        )) {
          throw new DomainError('invalid_bounds', 400);
        }
        return community.listPublished(actor(request), Number(q.limit), bounds);
      },
    );
  }

  if (deps.sharing) await registerSharingRoutes(app, deps.sharing, authenticate(), actor);
  if (deps.sos) await registerSosRoutes(app, deps.sos, authenticate(true), actor);
  if (deps.shareDevices)
    await registerShareDeviceRoutes(app, deps.shareDevices, authenticate(), actor);

  app.setNotFoundHandler((_request, reply) => reply.code(404).send({ code: 'not_found' }));
  app.setErrorHandler((error, _request, reply) => {
    if (error instanceof DomainError) return reply.code(error.status).send({ code: error.code });
    const status =
      typeof error === 'object' && error !== null && 'statusCode' in error
        ? Number(error.statusCode)
        : 500;
    const safeStatus = status >= 400 && status < 500 ? status : 503;
    return reply.code(safeStatus).send({
      code:
        safeStatus === 400
          ? 'invalid_request'
          : safeStatus === 429
            ? 'rate_limited'
            : safeStatus === 503
              ? 'storage_unavailable'
              : 'request_failed',
    });
  });
  app.addHook('onClose', async () => {
    await sharingCleanup?.close();
    await sosCleanup?.close();
    await deps.routing?.close?.();
    await deps.close?.();
  });
  return app;
}
