export const uuid = { type: 'string', format: 'uuid' };
export const date = { type: 'string', format: 'date-time' };
export const boolean = { type: 'boolean' };
export const text = { type: 'string' };
export const categories = ['obstruction', 'lighting', 'theft', 'harassment', 'accident', 'other'];
export const category = { type: 'string', enum: categories };
export function object(properties: Record<string, unknown>, required = Object.keys(properties)) {
  return { type: 'object', additionalProperties: false, properties, required };
}
export const array = (items: unknown) => ({ type: 'array', items });
export const nullable = (value: Record<string, unknown>) => ({
  ...value,
  type: [value.type, 'null'],
});
export const error = object({ code: text });
export const reviewReason = {
  type: 'string',
  enum: [
    'reviewed',
    'duplicate',
    'unverifiable',
    'personal_information',
    'outside_scope',
    'resolved',
  ],
};
export const reviewInput = object({
  clientRequestId: uuid,
  decision: { type: 'string', enum: ['approve', 'reject'] },
  reason: reviewReason,
});
export const reviewReceipt = object({
  id: uuid,
  reportId: uuid,
  decision: { type: 'string', enum: ['approve', 'reject'] },
  reason: reviewReason,
  status: { type: 'string', enum: ['reviewed', 'rejected', 'withdrawn'] },
  expiresAt: nullable(date),
  reviewedAt: date,
  replayed: boolean,
});
export const errors = { '4xx': error, '5xx': error };
export const graphVersion = {
  type: 'string',
  pattern: '^dhaka-gh11\\.1-[0-9a-f]{20}-[0-9a-f]{12}$',
  maxLength: 64,
};
export const edgeId = { type: 'integer', minimum: 0, maximum: 10000000 };
export const roadCandidates = object({
  graphVersion,
  requiresHumanSelection: { type: 'boolean', const: true },
  items: {
    type: 'array',
    maxItems: 5,
    items: object({
      edgeId,
      distanceMetres: { type: 'number', minimum: 0, maximum: 35 },
      lengthMetres: { type: 'number' },
      carForward: boolean,
      carReverse: boolean,
      footForward: boolean,
      footReverse: boolean,
      geometry: object({
        type: { type: 'string', const: 'LineString' },
        coordinates: {
          type: 'array',
          minItems: 2,
          maxItems: 10000,
          items: { type: 'array', minItems: 2, maxItems: 2, items: { type: 'number' } },
        },
      }),
    }),
  },
});
export const publicationInput = object({ clientRequestId: uuid, graphVersion, edgeId });
export const publicationReceipt = object({
  id: uuid,
  reportId: uuid,
  eventId: uuid,
  graphVersion,
  edgeId,
  expiresAt: date,
  publishedAt: date,
  status: { type: 'string', enum: ['published', 'withdrawn', 'expired'] },
  replayed: boolean,
});
export const geoPoint = object({
  latitude: { type: 'number', minimum: 23.62, maximum: 24.02 },
  longitude: { type: 'number', minimum: 90.2, maximum: 90.58 },
});
export const routeInput = object({
  origin: geoPoint,
  destination: geoPoint,
  mode: { type: 'string', enum: ['car', 'walk'] },
});
routeInput.properties.includeReports = boolean;
export const geographicPlan = object({
  trafficAware: { type: 'boolean', const: false },
  durationModel: { type: 'string', const: 'osm_static_speed' },
  graphVersion: { type: 'string', maxLength: 128 },
  riskVersion: { type: 'string', pattern: '^(?:unknown-v1|reviewed-decay-v1:[0-9a-f-]{36})$' },
  riskLevel: { type: 'string', const: 'unknown' },
  evidenceCoverage: { type: 'null' },
  source: { type: 'string', const: 'openstreetmap' },
  sourceTimestamp: date,
  attribution: { type: 'string', const: '© OpenStreetMap contributors' },
  license: { type: 'string', const: 'ODbL-1.0' },
  generatedAt: date,
  expiresAt: date,
  origin: geoPoint,
  destination: geoPoint,
  mode: { type: 'string', enum: ['car', 'walk'] },
  routes: {
    type: 'array',
    minItems: 1,
    maxItems: 2,
    items: object({
      id: uuid,
      preference: { type: 'string', enum: ['fastest', 'reported'] },
      durationSeconds: { type: 'integer', minimum: 1, maximum: 21600 },
      distanceMetres: { type: 'number', minimum: 1, maximum: 100000 },
      points: {
        type: 'array',
        minItems: 2,
        maxItems: 2000,
        items: {
          type: 'array',
          minItems: 2,
          maxItems: 2,
          items: { type: 'number', minimum: 23.62, maximum: 90.58 },
        },
      },
    }),
  },
});
geographicPlan.properties.reportRouting = object({
  status: {
    type: 'string',
    enum: ['available', 'no_evidence', 'unavailable', 'disabled', 'same_route'],
  },
  synthetic: boolean,
});
const geographicRouteSchema = (
  geographicPlan.properties.routes as { items: { properties: Record<string, unknown> } }
).items;
geographicRouteSchema.properties.reportedEvidenceFraction = {
  type: 'number',
  minimum: 0,
  maximum: 1,
};
export const profileInput = object({
  displayName: { type: 'string', minLength: 1, maxLength: 80 },
  locale: { type: 'string', enum: ['en', 'bn'] },
  adultAttested: { type: 'boolean', const: true },
});
export const profile = object({ ...profileInput.properties, id: uuid, createdAt: date });
export const circle = object({ id: uuid, name: text, ownerId: uuid, createdAt: date });
export const member = object({
  userId: uuid,
  displayName: text,
  role: { type: 'string', enum: ['owner', 'member'] },
  joinedAt: date,
});
export const circleDetail = object({ ...circle.properties, members: array(member) });
export const circleInput = object({
  clientRequestId: uuid,
  name: { type: 'string', minLength: 1, maxLength: 80 },
});
export const circleCreated = object({ circle, replayed: boolean });
export const inviteInput = object(
  {
    clientRequestId: uuid,
    recipientId: uuid,
    expiresInSeconds: { type: 'integer', minimum: 300, maximum: 604800, default: 86400 },
  },
  ['clientRequestId', 'recipientId'],
);
export const invite = object({
  id: uuid,
  circleId: uuid,
  recipientId: uuid,
  expiresAt: date,
  status: { type: 'string', enum: ['pending', 'accepted', 'revoked'] },
  replayed: boolean,
  token: text,
});
export const incomingInvite = object({
  id: uuid,
  circleId: uuid,
  circleName: text,
  inviterName: text,
  inviterId: uuid,
  expiresAt: date,
});
export const blockVersion = { type: 'integer', minimum: 0, maximum: 2147483646 };
export const blockInput = object({ blocked: boolean, expectedVersion: blockVersion });
export const blockState = object({
  userId: uuid,
  blocked: boolean,
  version: blockVersion,
  changedAt: nullable(date),
});
export const blockReceipt = object({ ...blockState.properties, replayed: boolean });
export const blockEntry = object({
  userId: uuid,
  displayName: nullable({ type: 'string', maxLength: 80 }),
  version: { ...blockVersion, minimum: 1 },
  blockedAt: date,
});
export const blockPage = object({
  items: { type: 'array', maxItems: 50, items: blockEntry },
  nextCursor: nullable(uuid),
});
export const inviteToken = object({
  token: { type: 'string', minLength: 43, maxLength: 43, pattern: '^[A-Za-z0-9_-]+$' },
});
export const inviteAccepted = object({ circle: circleDetail, replayed: boolean });
export const reportInput = object({
  clientRequestId: uuid,
  category,
  description: { type: 'string', minLength: 10, maxLength: 700 },
  latitude: { type: 'number', minimum: -90, maximum: 90 },
  longitude: { type: 'number', minimum: -180, maximum: 180 },
  observedAt: date,
});
export const receipt = object({
  id: uuid,
  status: { type: 'string', enum: ['pending', 'reviewed', 'rejected', 'withdrawn'] },
  replayed: boolean,
});
export const privateReport = object({
  id: uuid,
  category,
  description: text,
  latitude: { type: 'number' },
  longitude: { type: 'number' },
  observedAt: date,
  createdAt: date,
  status: { type: 'string', enum: ['pending', 'reviewed', 'rejected'] },
});
export const publicEvent = object({
  id: uuid,
  category,
  roadSegmentId: text,
  summary: text,
  latitude: { type: 'number' },
  longitude: { type: 'number' },
  observedAt: date,
  expiresAt: date,
  publishedAt: date,
});
export const limit = { type: 'string', pattern: '^(?:[1-9]|[1-9][0-9]|100)$', default: '50' };
export const reportsQuery = object(
  { limit, cursor: { type: 'string', maxLength: 512, pattern: '^[A-Za-z0-9_-]+$' } },
  [],
);
export const coordinateQuery = { type: 'string', pattern: '^-?[0-9]{1,3}(?:\\.[0-9]{1,6})?$' };
export const eventsQuery = {
  ...object(
    {
      limit,
      south: coordinateQuery,
      west: coordinateQuery,
      north: coordinateQuery,
      east: coordinateQuery,
    },
    [],
  ),
  dependencies: {
    south: ['west', 'north', 'east'],
    west: ['south', 'north', 'east'],
    north: ['south', 'west', 'east'],
    east: ['south', 'west', 'north'],
  },
};
