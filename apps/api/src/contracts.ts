import type { RoutingService } from './routing.ts';
import type { EvidenceStore } from './evidence.ts';

export type Principal = { id: string; phoneVerified: boolean };
export type ReportCategory =
  'obstruction' | 'lighting' | 'theft' | 'harassment' | 'accident' | 'other';
export type ReportInput = {
  clientRequestId: string;
  category: ReportCategory;
  description: string;
  latitude: number;
  longitude: number;
  observedAt: string;
};
export type ReportReceipt = {
  id: string;
  status: 'pending' | 'reviewed' | 'rejected' | 'withdrawn';
  replayed: boolean;
};
export type ProfileInput = { displayName: string; locale: 'en' | 'bn'; adultAttested: true };
export type Profile = ProfileInput & { id: string; createdAt: string };
export type Circle = { id: string; name: string; ownerId: string; createdAt: string };
export type CircleMember = {
  userId: string;
  displayName: string;
  role: 'owner' | 'member';
  joinedAt: string;
};
export type CircleDetail = Circle & { members: CircleMember[] };
export type CircleInput = { clientRequestId: string; name: string };
export type InviteInput = {
  clientRequestId: string;
  recipientId: string;
  expiresInSeconds?: number;
};
export type InviteReceipt = {
  id: string;
  circleId: string;
  recipientId: string;
  expiresAt: string;
  status: 'pending' | 'accepted' | 'revoked';
  replayed: boolean;
};
export type IncomingInvite = {
  id: string;
  circleId: string;
  circleName: string;
  inviterName: string;
  inviterId: string;
  expiresAt: string;
};
export type BlockState = {
  userId: string;
  blocked: boolean;
  version: number;
  changedAt: string | null;
};
export type BlockInput = { blocked: boolean; expectedVersion: number };
export type BlockReceipt = BlockState & { replayed: boolean };
export type BlockEntry = {
  userId: string;
  displayName: string | null;
  version: number;
  blockedAt: string;
};
export type BlockPage = { items: BlockEntry[]; nextCursor: string | null };
export type PrivateReport = Omit<ReportInput, 'clientRequestId'> & {
  id: string;
  createdAt: string;
  status: 'pending' | 'reviewed' | 'rejected';
};
export type ReportCursor = { createdAt: string; id: string };
export type ReviewReason =
  'reviewed' | 'duplicate' | 'unverifiable' | 'personal_information' | 'outside_scope' | 'resolved';
export type ReviewInput = {
  clientRequestId: string;
  decision: 'approve' | 'reject';
  reason: ReviewReason;
};
export type ReviewReceipt = Omit<ReviewInput, 'clientRequestId'> & {
  id: string;
  reportId: string;
  status: 'reviewed' | 'rejected' | 'withdrawn';
  expiresAt: string | null;
  reviewedAt: string;
  replayed: boolean;
};
export interface ModerationStore {
  listPending(
    actor: string,
    limit: number,
    after: ReportCursor | null,
  ): Promise<{ items: PrivateReport[]; next: ReportCursor | null }>;
  review(actor: string, reportId: string, input: ReviewInput, hash: string): Promise<ReviewReceipt>;
  roadCandidates(actor: string, reportId: string, graphVersion: string): Promise<RoadCandidates>;
  publish(
    actor: string,
    reportId: string,
    input: PublicationInput,
    hash: string,
  ): Promise<PublicationReceipt>;
}
export type RoadCandidate = {
  edgeId: number;
  distanceMetres: number;
  lengthMetres: number;
  carForward: boolean;
  carReverse: boolean;
  footForward: boolean;
  footReverse: boolean;
  geometry: { type: 'LineString'; coordinates: [number, number][] };
};
export type RoadCandidates = {
  graphVersion: string;
  requiresHumanSelection: true;
  items: RoadCandidate[];
};
export type PublicationInput = { clientRequestId: string; graphVersion: string; edgeId: number };
export type PublicationReceipt = {
  id: string;
  reportId: string;
  eventId: string;
  graphVersion: string;
  edgeId: number;
  expiresAt: string;
  publishedAt: string;
  status: 'published' | 'withdrawn' | 'expired';
  replayed: boolean;
};
export type PublicEvent = {
  id: string;
  category: ReportCategory;
  roadSegmentId: string;
  summary: string;
  latitude: number;
  longitude: number;
  observedAt: string;
  expiresAt: string;
  publishedAt: string;
};
export type EventBounds = { south: number; west: number; north: number; east: number };

export interface ReportStore {
  create(ownerId: string, input: ReportInput, payloadHash: string): Promise<ReportReceipt>;
}
export interface CommunityStore {
  receipt(ownerId: string, clientRequestId: string): Promise<ReportReceipt>;
  listOwn(
    ownerId: string,
    limit: number,
    before: ReportCursor | null,
  ): Promise<{ items: PrivateReport[]; next: ReportCursor | null }>;
  withdraw(ownerId: string, reportId: string): Promise<{ id: string; status: 'withdrawn' }>;
  listPublished(
    ownerId: string,
    limit: number,
    bounds: EventBounds,
  ): Promise<{ items: PublicEvent[] }>;
}
export interface PeopleStore {
  blockState(actor: string, userId: string): Promise<BlockState>;
  setBlock(actor: string, userId: string, input: BlockInput): Promise<BlockReceipt>;
  listBlocks(actor: string, limit: number, after: string | null): Promise<BlockPage>;
  getProfile(actor: string): Promise<Profile | null>;
  putProfile(actor: string, input: ProfileInput): Promise<Profile>;
  listCircles(actor: string): Promise<{ items: Circle[] }>;
  createCircle(
    actor: string,
    input: CircleInput,
    hash: string,
  ): Promise<{ circle: Circle; replayed: boolean }>;
  getCircle(actor: string, id: string): Promise<CircleDetail>;
  createInvite(
    actor: string,
    circleId: string,
    input: InviteInput,
    hash: string,
    tokenHash: string,
  ): Promise<InviteReceipt>;
  incomingInvites(actor: string): Promise<{ items: IncomingInvite[] }>;
  acceptInvite(
    actor: string,
    id: string,
    tokenHash: string,
  ): Promise<{ circle: CircleDetail; replayed: boolean }>;
  revokeInvite(actor: string, id: string): Promise<{ id: string; status: 'revoked' }>;
  removeMember(
    actor: string,
    circleId: string,
    memberId: string,
  ): Promise<{ circleId: string; userId: string; status: 'revoked' }>;
  closeCircle(actor: string, id: string): Promise<{ id: string; status: 'closed' }>;
}

export class DomainError extends Error {
  readonly code: string;
  readonly status: number;
  constructor(code: string, status: number) {
    super(code);
    this.code = code;
    this.status = status;
  }
}
export class IdempotencyConflict extends DomainError {
  constructor() {
    super('idempotency_conflict', 409);
  }
}
export type Dependencies = {
  sos?: import('./sos.ts').SosStore;
  shareDevices?: import('./share_devices.ts').ShareDeviceStore;
  sharing?: import('./sharing.ts').SharingStore;
  places?: import('./places.ts').PlaceCatalogue;
  routing?: RoutingService;
  evidence?: EvidenceStore;
  verifyToken: (token: string) => Promise<Principal | null>;
  reports: ReportStore;
  people?: PeopleStore;
  community?: CommunityStore;
  moderation?: ModerationStore;
  inviteToken?: (actor: string, circle: string, requestId: string) => string;
  ready?: () => Promise<boolean>;
  close?: () => Promise<void>;
  now?: () => Date;
};
