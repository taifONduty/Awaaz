import { createHash } from 'node:crypto';
import type { FastifyInstance, FastifyRequest, onRequestHookHandler } from 'fastify';
import { DomainError } from './contracts.ts';
import type { SharePositionInput, SharePositionReceipt } from './sharing.ts';
import { positionHash } from './sharing.ts';
import * as s from './schemas.ts';

export type ShareDeviceState = {
  shareId: string;
  expiresAt: string;
  serverTime: string;
  sequence: number;
  status: 'unbound' | 'active' | 'revoked' | 'stopped' | 'expired';
};
export interface ShareDeviceStore {
  owner(
    actor: string,
    shareId: string,
    operation: 'bind' | 'state' | 'revoke',
    hash?: string,
  ): Promise<ShareDeviceState>;
  state(hash: string, shareId: string): Promise<ShareDeviceState>;
  position(
    hash: string,
    shareId: string,
    input: SharePositionInput,
    payloadHash: string,
  ): Promise<SharePositionReceipt>;
  stop(hash: string, shareId: string): Promise<ShareDeviceState>;
}

// The prefix and hash domain prevent reuse as an account/invitation credential.
export function deviceCredentialHash(token: string): string {
  return createHash('sha256').update('awaaz-share-device-v1\0').update(token).digest('hex');
}
const state = s.object({
  shareId: s.uuid,
  expiresAt: s.date,
  serverTime: s.date,
  sequence: { type: 'integer', minimum: 0, maximum: 2147483646 },
  status: { type: 'string', enum: ['unbound', 'active', 'revoked', 'stopped', 'expired'] },
});
const response = (value: unknown) => ({ 200: value, ...s.errors });
const params = s.object({ shareId: s.uuid });

export async function registerShareDeviceRoutes(
  app: FastifyInstance,
  store: ShareDeviceStore,
  authenticate: onRequestHookHandler,
  actor: (request: FastifyRequest) => string,
) {
  const ownerSchema = {
    tags: ['Trip sharing'],
    security: [{ bearerAuth: [] }],
    params,
    response: response(state),
  };
  app.post<{ Params: { shareId: string }; Body: { credentialHash: string } }>(
    '/v1/shares/:shareId/device',
    {
      onRequest: authenticate,
      schema: {
        ...ownerSchema,
        body: s.object({ credentialHash: { type: 'string', pattern: '^[0-9a-f]{64}$' } }),
      },
    },
    (request) =>
      store.owner(
        actor(request),
        request.params.shareId.toLowerCase(),
        'bind',
        request.body.credentialHash,
      ),
  );
  app.get<{ Params: { shareId: string } }>(
    '/v1/shares/:shareId/device',
    { onRequest: authenticate, schema: ownerSchema },
    (request) => store.owner(actor(request), request.params.shareId.toLowerCase(), 'state'),
  );
  app.delete<{ Params: { shareId: string } }>(
    '/v1/shares/:shareId/device',
    { onRequest: authenticate, schema: ownerSchema },
    (request) => store.owner(actor(request), request.params.shareId.toLowerCase(), 'revoke'),
  );

  const digest = (request: FastifyRequest) =>
    deviceCredentialHash(request.headers.authorization!.slice(7));
  const deviceAuth: onRequestHookHandler = async (request) => {
    if (!/^Bearer awaaz-share-v1\.[A-Za-z0-9_-]{43}$/.test(request.headers.authorization ?? '')) {
      throw new DomainError('unauthenticated', 401);
    }
  };
  const deviceSchema = {
    tags: ['Native trip sharing'],
    security: [{ shareDeviceAuth: [] }],
    params,
  };
  // Separate from Auth account gates. Hashes are used only as bounded rate keys;
  // raw credentials and request bodies never enter application logs.
  const config = {
    rateLimit: {
      max: 30,
      timeWindow: '1 minute',
      keyGenerator: (request: FastifyRequest) =>
        `share-device:${deviceCredentialHash(request.headers.authorization ?? request.ip)}`,
    },
  };
  app.get<{ Params: { shareId: string } }>(
    '/v1/share-devices/:shareId',
    { onRequest: deviceAuth, config, schema: { ...deviceSchema, response: response(state) } },
    (request) => store.state(digest(request), request.params.shareId.toLowerCase()),
  );
  app.delete<{ Params: { shareId: string } }>(
    '/v1/share-devices/:shareId',
    { onRequest: deviceAuth, config, schema: { ...deviceSchema, response: response(state) } },
    (request) => store.stop(digest(request), request.params.shareId.toLowerCase()),
  );
  app.put<{ Params: { shareId: string }; Body: SharePositionInput }>(
    '/v1/share-devices/:shareId/position',
    {
      onRequest: deviceAuth,
      config,
      schema: {
        ...deviceSchema,
        body: s.object({
          sequence: { type: 'integer', minimum: 1, maximum: 2147483646 },
          latitude: { type: 'number', minimum: 23.62, maximum: 24.02 },
          longitude: { type: 'number', minimum: 90.2, maximum: 90.58 },
          accuracyMetres: { type: 'number', minimum: 1, maximum: 100 },
          capturedAt: s.date,
        }),
        response: response(
          s.object({
            shareId: s.uuid,
            sequence: { type: 'integer', minimum: 1, maximum: 2147483646 },
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
        digest(request),
        request.params.shareId.toLowerCase(),
        input,
        positionHash(input),
      );
    },
  );
}
