import type { FastifyInstance, FastifyRequest, onRequestHookHandler } from 'fastify';
import { DomainError } from './contracts.ts';
import * as s from './schemas.ts';
import { payloadHash } from './security.ts';

export type ShareInput = {
  clientRequestId: string;
  circleId: string;
  recipientIds: string[];
  durationSeconds: number;
};
export type SharePositionInput = {
  sequence: number;
  latitude: number;
  longitude: number;
  accuracyMetres: number;
  capturedAt: string;
};
export function positionHash(input: SharePositionInput): string {
  return payloadHash([
    'trip-share.position.v1',
    input.sequence,
    input.latitude,
    input.longitude,
    input.accuracyMetres,
    input.capturedAt,
  ]);
}
export type ShareControl = {
  id: string;
  circleId: string | null;
  startedAt: string;
  expiresAt: string;
  status: 'active' | 'stopped' | 'expired';
  sequence: number;
  recipients: { userId: string; active: boolean }[];
};
export type ShareReceipt = ShareControl & { replayed: boolean };
export type SharePositionReceipt = {
  shareId: string;
  sequence: number;
  acceptedAt: string;
  expiresAt: string;
  replayed: boolean;
};
export type SharedTrip = {
  id: string;
  ownerId: string;
  ownerName: string;
  expiresAt: string;
  serverTime: string;
  lastUpdatedAt: string | null;
  freshness: 'waiting' | 'fresh' | 'stale';
  location: {
    latitude: number;
    longitude: number;
    accuracyMetres: number;
    capturedAt: string;
    expiresAt: string;
  } | null;
};
export type IncomingShares = {
  items: { id: string; ownerName: string; expiresAt: string }[];
  nextCursor: string | null;
};
export interface SharingStore {
  create(actor: string, input: ShareInput, hash: string): Promise<ShareReceipt>;
  current(actor: string): Promise<{ share: ShareControl | null }>;
  request(actor: string, requestId: string): Promise<ShareControl>;
  view(actor: string, shareId: string): Promise<SharedTrip>;
  incoming(actor: string, limit: number, after: string | null): Promise<IncomingShares>;
  position(
    actor: string,
    shareId: string,
    input: SharePositionInput,
    hash: string,
  ): Promise<SharePositionReceipt>;
  stop(actor: string, shareId: string): Promise<ShareControl>;
  revoke(
    actor: string,
    shareId: string,
    recipientId: string,
  ): Promise<{ shareId: string; userId: string; status: 'revoked' }>;
  cleanupExpired(): Promise<{ positionsDeleted: number; grantsDeleted: number }>;
}

const sequence = { type: 'integer', minimum: 0, maximum: 2147483646 };
const latitude = { type: 'number', minimum: 23.62, maximum: 24.02 };
const longitude = { type: 'number', minimum: 90.2, maximum: 90.58 };
const accuracy = { type: 'number', minimum: 1, maximum: 100 };
const controlFields = {
  id: s.uuid,
  circleId: s.nullable(s.uuid),
  startedAt: s.date,
  expiresAt: s.date,
  status: { type: 'string', enum: ['active', 'stopped', 'expired'] },
  sequence,
  recipients: { ...s.array(s.object({ userId: s.uuid, active: s.boolean })), maxItems: 10 },
};
const control = s.object(controlFields);
const response = (schema: unknown) => ({ 200: schema, ...s.errors });

export async function registerSharingRoutes(
  app: FastifyInstance,
  store: SharingStore,
  authenticate: onRequestHookHandler,
  actor: (request: FastifyRequest) => string,
) {
  const schema = { tags: ['Trip sharing'], security: [{ bearerAuth: [] }] };
  const shareParams = s.object({ shareId: s.uuid });
  app.post<{ Body: ShareInput }>(
    '/v1/shares',
    {
      onRequest: authenticate,
      schema: {
        ...schema,
        body: s.object({
          clientRequestId: s.uuid,
          circleId: s.uuid,
          recipientIds: { ...s.array(s.uuid), minItems: 1, maxItems: 10, uniqueItems: true },
          durationSeconds: { type: 'integer', minimum: 300, maximum: 7200 },
        }),
        response: {
          ...response(s.object({ ...controlFields, replayed: s.boolean })),
          201: s.object({ ...controlFields, replayed: s.boolean }),
        },
      },
    },
    async (request, reply) => {
      const input = {
        ...request.body,
        clientRequestId: request.body.clientRequestId.toLowerCase(),
        circleId: request.body.circleId.toLowerCase(),
        recipientIds: request.body.recipientIds.map((id) => id.toLowerCase()).sort(),
      };
      if (
        new Set(input.recipientIds).size !== input.recipientIds.length ||
        input.recipientIds.includes(actor(request))
      ) {
        throw new DomainError('invalid_request', 400);
      }
      const receipt = await store.create(
        actor(request),
        input,
        payloadHash([
          'trip-share.create.v1',
          input.circleId,
          input.recipientIds,
          input.durationSeconds,
        ]),
      );
      return reply.code(receipt.replayed ? 200 : 201).send(receipt);
    },
  );
  app.get(
    '/v1/me/share',
    {
      onRequest: authenticate,
      schema: {
        ...schema,
        querystring: s.object({}),
        response: response(s.object({ share: s.nullable(control) })),
      },
    },
    (request) => store.current(actor(request)),
  );
  app.get<{ Params: { requestId: string } }>(
    '/v1/share-requests/:requestId',
    {
      onRequest: authenticate,
      schema: { ...schema, params: s.object({ requestId: s.uuid }), response: response(control) },
    },
    (request) => store.request(actor(request), request.params.requestId.toLowerCase()),
  );
  app.get<{ Querystring: { limit?: string; after?: string } }>(
    '/v1/shared-trips',
    {
      onRequest: authenticate,
      schema: {
        ...schema,
        querystring: s.object(
          { limit: { type: 'string', pattern: '^(?:[1-9]|[1-4][0-9]|50)$' }, after: s.uuid },
          [],
        ),
        response: response(
          s.object({
            items: s.array(s.object({ id: s.uuid, ownerName: s.text, expiresAt: s.date })),
            nextCursor: s.nullable(s.uuid),
          }),
        ),
      },
    },
    (request) =>
      store.incoming(
        actor(request),
        Number(request.query.limit ?? '30'),
        request.query.after?.toLowerCase() ?? null,
      ),
  );
  app.get<{ Params: { shareId: string } }>(
    '/v1/shares/:shareId',
    {
      onRequest: authenticate,
      schema: {
        ...schema,
        params: shareParams,
        response: response(
          s.object({
            id: s.uuid,
            ownerId: s.uuid,
            ownerName: s.text,
            expiresAt: s.date,
            serverTime: s.date,
            lastUpdatedAt: s.nullable(s.date),
            freshness: { type: 'string', enum: ['waiting', 'fresh', 'stale'] },
            location: s.nullable(
              s.object({
                latitude,
                longitude,
                accuracyMetres: accuracy,
                capturedAt: s.date,
                expiresAt: s.date,
              }),
            ),
          }),
        ),
      },
    },
    (request) => store.view(actor(request), request.params.shareId.toLowerCase()),
  );
  app.put<{ Params: { shareId: string }; Body: SharePositionInput }>(
    '/v1/shares/:shareId/position',
    {
      onRequest: authenticate,
      schema: {
        ...schema,
        params: shareParams,
        body: s.object({
          sequence: { ...sequence, minimum: 1 },
          latitude,
          longitude,
          accuracyMetres: accuracy,
          capturedAt: s.date,
        }),
        response: response(
          s.object({
            shareId: s.uuid,
            sequence,
            acceptedAt: s.date,
            expiresAt: s.date,
            replayed: s.boolean,
          }),
        ),
      },
    },
    (request) => {
      const time = Date.parse(request.body.capturedAt);
      if (!Number.isFinite(time)) throw new DomainError('invalid_request', 400);
      const input = { ...request.body, capturedAt: new Date(time).toISOString() };
      return store.position(
        actor(request),
        request.params.shareId.toLowerCase(),
        input,
        positionHash(input),
      );
    },
  );
  app.delete<{ Params: { shareId: string } }>(
    '/v1/shares/:shareId',
    {
      onRequest: authenticate,
      schema: { ...schema, params: shareParams, response: response(control) },
    },
    (request) => store.stop(actor(request), request.params.shareId.toLowerCase()),
  );
  app.delete<{ Params: { shareId: string; userId: string } }>(
    '/v1/shares/:shareId/recipients/:userId',
    {
      onRequest: authenticate,
      schema: {
        ...schema,
        params: s.object({ shareId: s.uuid, userId: s.uuid }),
        response: response(
          s.object({
            shareId: s.uuid,
            userId: s.uuid,
            status: { type: 'string', const: 'revoked' },
          }),
        ),
      },
    },
    (request) =>
      store.revoke(
        actor(request),
        request.params.shareId.toLowerCase(),
        request.params.userId.toLowerCase(),
      ),
  );
}

/** Bounded retention, one operation at a time. Database expiry gates reads even
 * when this process is down. Physical cleanup needs a supervised running API. */
export class SharingCleanup {
  private readonly store: Pick<SharingStore, 'cleanupExpired'>;
  private readonly now: () => number;
  constructor(store: Pick<SharingStore, 'cleanupExpired'>, now = () => performance.now()) {
    this.store = store;
    this.now = now;
  }
  private timer: ReturnType<typeof setInterval> | undefined;
  private pending: Promise<void> | undefined;
  private closed = false;
  private lastSuccess: number | undefined;
  ready() {
    return !this.closed && this.lastSuccess !== undefined && this.now() - this.lastSuccess < 90_000;
  }
  async start() {
    await this.run();
    if (!this.closed) this.timer = setInterval(() => void this.run(), 30_000).unref();
  }
  run(): Promise<void> {
    if (this.closed) return Promise.resolve();
    if (this.pending) return this.pending;
    this.pending = (async () => {
      try {
        await this.store.cleanupExpired();
        this.lastSuccess = this.now();
      } catch {
        /* Readiness ages out without logging private database details. */
      }
    })().finally(() => {
      this.pending = undefined;
    });
    return this.pending;
  }
  async close() {
    this.closed = true;
    if (this.timer) clearInterval(this.timer);
    await this.pending;
  }
}
