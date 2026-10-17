import type { FastifyInstance, FastifyRequest, onRequestHookHandler } from 'fastify';
import { DomainError } from './contracts.ts';
import { payloadHash } from './security.ts';
import type { SharePositionInput } from './sharing.ts';
import * as s from './schemas.ts';

export type SosPreference = { allowed: boolean; version: number };
export type SosInput = {
  clientRequestId: string;
  circleId: string;
  recipientIds: string[];
  mode: 'silent' | 'audible';
  shareLocation: boolean;
};
export type SosResponse = 'seen' | 'contacting' | 'helping' | 'unavailable';
export type SosStatus = 'active' | 'ended' | 'cancelled' | 'expired';
export type SosDelivery = {
  kind: 'request' | 'resolved' | 'cancelled';
  status:
    'queued' | 'sending' | 'provider_accepted' | 'failed' | 'cancelled' | 'expired' | 'unknown';
  attempts: number;
  providerAcceptedAt: string | null;
  cancelledAt: string | null;
};
export type SosControl = {
  id: string;
  circleId: string | null;
  startedAt: string;
  expiresAt: string;
  serverTime: string;
  status: SosStatus;
  version: number;
  mode: 'silent' | 'audible';
  shareLocation: boolean;
  sequence: number;
  recipients: {
    userId: string;
    active: boolean;
    response: SosResponse | null;
    responseVersion: number;
    respondedAt: string | null;
    delivery: SosDelivery[];
  }[];
};
export type SosReceipt = SosControl & { replayed: boolean };
export type SosPositionReceipt = {
  incidentId: string;
  sequence: number;
  acceptedAt: string;
  expiresAt: string;
  replayed: boolean;
};
export type SosView = {
  id: string;
  ownerId: string;
  ownerName: string;
  startedAt: string;
  expiresAt: string;
  serverTime: string;
  status: SosStatus;
  version: number;
  response: SosResponse | null;
  responseVersion: number;
  respondedAt: string | null;
  location: {
    latitude: number;
    longitude: number;
    accuracyMetres: number;
    capturedAt: string;
    expiresAt: string;
  } | null;
};
export type SosIncoming = {
  items: { id: string; ownerName: string; status: SosStatus; expiresAt: string }[];
  nextCursor: string | null;
};
export type SosResponseInput = { response: SosResponse; expectedVersion: number };
export type SosResponseReceipt = {
  incidentId: string;
  response: SosResponse;
  version: number;
  respondedAt: string;
  replayed: boolean;
};
export interface SosStore {
  preference(actor: string): Promise<SosPreference>;
  setPreference(
    actor: string,
    input: { allowed: boolean; expectedVersion: number },
  ): Promise<SosPreference & { replayed: boolean }>;
  eligible(
    actor: string,
    circleId: string,
  ): Promise<{ items: { userId: string; displayName: string }[] }>;
  create(actor: string, input: SosInput, hash: string): Promise<SosReceipt>;
  current(actor: string): Promise<{ incident: SosControl | null }>;
  request(actor: string, requestId: string): Promise<SosControl>;
  cancelRequest(
    actor: string,
    requestId: string,
  ): Promise<{
    clientRequestId: string;
    incidentId: string | null;
    incidentStatus: SosStatus | null;
    status: 'cancelled';
  }>;
  view(actor: string, incidentId: string): Promise<SosView>;
  incoming(actor: string, limit: number, after: string | null): Promise<SosIncoming>;
  respond(actor: string, incidentId: string, input: SosResponseInput): Promise<SosResponseReceipt>;
  decline(actor: string, incidentId: string): Promise<{ incidentId: string; status: 'revoked' }>;
  end(actor: string, incidentId: string, outcome: 'resolved' | 'cancelled'): Promise<SosControl>;
  position(
    actor: string,
    incidentId: string,
    input: SharePositionInput,
    hash: string,
  ): Promise<SosPositionReceipt>;
  cleanupExpired(): Promise<{ positionsDeleted: number; grantsDeleted: number }>;
}

const version = { type: 'integer', minimum: 0, maximum: 2147483646 };
const expectedVersion = { type: 'integer', minimum: 0, maximum: 2147483645 };
const status = { type: 'string', enum: ['active', 'ended', 'cancelled', 'expired'] };
const responseChoice = { type: 'string', enum: ['seen', 'contacting', 'helping', 'unavailable'] };
const location = s.object({
  latitude: { type: 'number', minimum: 23.62, maximum: 24.02 },
  longitude: { type: 'number', minimum: 90.2, maximum: 90.58 },
  accuracyMetres: { type: 'number', minimum: 1, maximum: 100 },
  capturedAt: s.date,
  expiresAt: s.date,
});
const preference = s.object({ allowed: s.boolean, version });
const controlFields = {
  id: s.uuid,
  circleId: s.nullable(s.uuid),
  startedAt: s.date,
  expiresAt: s.date,
  serverTime: s.date,
  status,
  version: { ...version, minimum: 1 },
  mode: { type: 'string', enum: ['silent', 'audible'] },
  shareLocation: s.boolean,
  sequence: version,
  recipients: {
    ...s.array(
      s.object({
        userId: s.uuid,
        active: s.boolean,
        response: s.nullable(responseChoice),
        responseVersion: version,
        respondedAt: s.nullable(s.date),
        delivery: {
          ...s.array(
            s.object({
              kind: { type: 'string', enum: ['request', 'resolved', 'cancelled'] },
              status: {
                type: 'string',
                enum: [
                  'queued',
                  'sending',
                  'provider_accepted',
                  'failed',
                  'cancelled',
                  'expired',
                  'unknown',
                ],
              },
              attempts: { type: 'integer', minimum: 0 },
              providerAcceptedAt: s.nullable(s.date),
              cancelledAt: s.nullable(s.date),
            }),
          ),
          maxItems: 3,
        },
      }),
    ),
    maxItems: 10,
  },
};
const control = s.object(controlFields);
const response = (value: unknown) => ({ 200: value, ...s.errors });
const params = s.object({ incidentId: s.uuid });
export function sosHash(input: SosInput): string {
  return payloadHash([
    'sos.create.v1',
    input.circleId,
    input.recipientIds,
    input.mode,
    input.shareLocation,
  ]);
}
export function sosPositionHash(input: SharePositionInput): string {
  return payloadHash([
    'sos.position.v1',
    input.sequence,
    input.latitude,
    input.longitude,
    input.accuracyMetres,
    input.capturedAt,
  ]);
}
export async function registerSosRoutes(
  app: FastifyInstance,
  store: SosStore,
  authenticate: onRequestHookHandler,
  actor: (request: FastifyRequest) => string,
) {
  const schema = { tags: ['SOS'], security: [{ bearerAuth: [] }] };
  const options = (value: unknown, extra: object = {}) => ({
    onRequest: authenticate,
    schema: { ...schema, ...extra, response: response(value) },
  });
  app.get(
    '/v1/sos/status',
    {
      schema: {
        tags: ['SOS'],
        response: response(
          s.object({
            requestStorage: { type: 'boolean', const: true },
            pushDelivery: { type: 'boolean', const: false },
            smsDelivery: { type: 'boolean', const: false },
          }),
        ),
      },
    },
    async () => ({ requestStorage: true, pushDelivery: false, smsDelivery: false }),
  );
  app.get('/v1/me/sos-preference', options(preference), (request) =>
    store.preference(actor(request)),
  );
  app.put<{ Body: { allowed: boolean; expectedVersion: number } }>(
    '/v1/me/sos-preference',
    options(s.object({ allowed: s.boolean, version, replayed: s.boolean }), {
      body: s.object({ allowed: s.boolean, expectedVersion }),
    }),
    (request) => store.setPreference(actor(request), request.body),
  );
  app.get<{ Params: { circleId: string } }>(
    '/v1/circles/:circleId/sos-recipients',
    options(
      s.object({
        items: {
          ...s.array(s.object({ userId: s.uuid, displayName: { type: 'string', maxLength: 80 } })),
          maxItems: 100,
        },
      }),
      { params: s.object({ circleId: s.uuid }) },
    ),
    (request) => store.eligible(actor(request), request.params.circleId.toLowerCase()),
  );
  app.post<{ Body: SosInput }>(
    '/v1/incidents',
    {
      onRequest: authenticate,
      schema: {
        ...schema,
        body: s.object({
          clientRequestId: s.uuid,
          circleId: s.uuid,
          recipientIds: { ...s.array(s.uuid), minItems: 1, maxItems: 10, uniqueItems: true },
          mode: { type: 'string', enum: ['silent', 'audible'] },
          shareLocation: s.boolean,
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
      if (new Set(input.recipientIds).size !== input.recipientIds.length)
        throw new DomainError('invalid_request', 400);
      const result = await store.create(actor(request), input, sosHash(input));
      return reply.code(result.replayed ? 200 : 201).send(result);
    },
  );
  app.get('/v1/me/incident', options(s.object({ incident: s.nullable(control) })), (request) =>
    store.current(actor(request)),
  );
  app.get<{ Params: { requestId: string } }>(
    '/v1/incident-requests/:requestId',
    options(control, { params: s.object({ requestId: s.uuid }) }),
    (request) => store.request(actor(request), request.params.requestId.toLowerCase()),
  );
  app.delete<{ Params: { requestId: string } }>(
    '/v1/incident-requests/:requestId',
    options(
      s.object({
        clientRequestId: s.uuid,
        incidentId: s.nullable(s.uuid),
        incidentStatus: s.nullable(status),
        status: { type: 'string', const: 'cancelled' },
      }),
      { params: s.object({ requestId: s.uuid }) },
    ),
    (request) => store.cancelRequest(actor(request), request.params.requestId.toLowerCase()),
  );
  app.get<{ Params: { incidentId: string } }>(
    '/v1/incidents/:incidentId',
    options(
      s.object({
        id: s.uuid,
        ownerId: s.uuid,
        ownerName: { type: 'string', maxLength: 80 },
        startedAt: s.date,
        expiresAt: s.date,
        serverTime: s.date,
        status,
        version: { ...version, minimum: 1 },
        response: s.nullable(responseChoice),
        responseVersion: version,
        respondedAt: s.nullable(s.date),
        location: s.nullable(location),
      }),
      { params },
    ),
    (request) => store.view(actor(request), request.params.incidentId.toLowerCase()),
  );
  app.get<{ Querystring: { limit?: string; after?: string } }>(
    '/v1/me/incidents',
    options(
      s.object({
        items: {
          ...s.array(
            s.object({
              id: s.uuid,
              ownerName: { type: 'string', maxLength: 80 },
              status,
              expiresAt: s.date,
            }),
          ),
          maxItems: 50,
        },
        nextCursor: s.nullable(s.uuid),
      }),
      {
        querystring: s.object(
          { limit: { type: 'string', pattern: '^(?:[1-9]|[1-4][0-9]|50)$' }, after: s.uuid },
          [],
        ),
      },
    ),
    (request) =>
      store.incoming(
        actor(request),
        Number(request.query.limit ?? 30),
        request.query.after?.toLowerCase() ?? null,
      ),
  );
  app.put<{ Params: { incidentId: string }; Body: SosResponseInput }>(
    '/v1/incidents/:incidentId/response',
    options(
      s.object({
        incidentId: s.uuid,
        response: responseChoice,
        version,
        respondedAt: s.date,
        replayed: s.boolean,
      }),
      { params, body: s.object({ response: responseChoice, expectedVersion }) },
    ),
    (request) =>
      store.respond(actor(request), request.params.incidentId.toLowerCase(), request.body),
  );
  app.delete<{ Params: { incidentId: string } }>(
    '/v1/incidents/:incidentId/access',
    options(s.object({ incidentId: s.uuid, status: { type: 'string', const: 'revoked' } }), {
      params,
    }),
    (request) => store.decline(actor(request), request.params.incidentId.toLowerCase()),
  );
  app.post<{ Params: { incidentId: string }; Body: { outcome: 'resolved' | 'cancelled' } }>(
    '/v1/incidents/:incidentId/end',
    options(control, {
      params,
      body: s.object({ outcome: { type: 'string', enum: ['resolved', 'cancelled'] } }),
    }),
    (request) =>
      store.end(actor(request), request.params.incidentId.toLowerCase(), request.body.outcome),
  );
  app.put<{ Params: { incidentId: string }; Body: SharePositionInput }>(
    '/v1/incidents/:incidentId/position',
    options(
      s.object({
        incidentId: s.uuid,
        sequence: { ...version, minimum: 1 },
        acceptedAt: s.date,
        expiresAt: s.date,
        replayed: s.boolean,
      }),
      {
        params,
        body: s.object({
          sequence: { ...version, minimum: 1 },
          latitude: { type: 'number', minimum: 23.62, maximum: 24.02 },
          longitude: { type: 'number', minimum: 90.2, maximum: 90.58 },
          accuracyMetres: { type: 'number', minimum: 1, maximum: 100 },
          capturedAt: s.date,
        }),
      },
    ),
    (request) => {
      const time = Date.parse(request.body.capturedAt);
      if (!Number.isFinite(time)) throw new DomainError('invalid_request', 400);
      const input = { ...request.body, capturedAt: new Date(time).toISOString() };
      return store.position(
        actor(request),
        request.params.incidentId.toLowerCase(),
        input,
        sosPositionHash(input),
      );
    },
  );
}
