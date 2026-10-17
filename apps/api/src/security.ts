import { createHash, createHmac } from 'node:crypto';
import { DomainError } from './contracts.ts';
import type { ReportCursor } from './contracts.ts';

export function payloadHash(values: unknown[]): string {
  return createHash('sha256').update(JSON.stringify(values)).digest('hex');
}
export function tokenHash(token: string): string {
  return createHash('sha256').update(token).digest('hex');
}
export function inviteTokenFactory(secret: string) {
  // A random 32-byte secret is represented by 64 hexadecimal characters.
  if (!/^[0-9a-f]{64}$/i.test(secret))
    throw new Error('INVITE_TOKEN_SECRET must contain 64 hexadecimal characters');
  const key = Buffer.from(secret, 'hex');
  return (actor: string, circle: string, requestId: string) =>
    createHmac('sha256', key)
      .update(
        JSON.stringify([
          'awaaz-invite-v1',
          actor.toLowerCase(),
          circle.toLowerCase(),
          requestId.toLowerCase(),
        ]),
      )
      .digest('base64url');
}
export function encodeCursor(cursor: ReportCursor | null): string | null {
  return cursor
    ? Buffer.from(JSON.stringify([1, cursor.createdAt, cursor.id])).toString('base64url')
    : null;
}
export function decodeCursor(cursor: string | undefined): ReportCursor | null {
  if (!cursor) return null;
  try {
    if (cursor.length > 512 || !/^[A-Za-z0-9_-]+$/.test(cursor)) throw new Error();
    const value: unknown = JSON.parse(Buffer.from(cursor, 'base64url').toString('utf8'));
    if (
      !Array.isArray(value) ||
      value.length !== 3 ||
      value[0] !== 1 ||
      typeof value[1] !== 'string' ||
      typeof value[2] !== 'string' ||
      !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$/.test(value[1]) ||
      !Number.isFinite(Date.parse(value[1])) ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value[2])
    )
      throw new Error();
    // PostgreSQL timestamps have microsecond precision. Converting through a
    // JavaScript Date would truncate the cursor and repeat/skip boundary rows.
    return { createdAt: value[1], id: value[2].toLowerCase() };
  } catch {
    throw new DomainError('invalid_cursor', 400);
  }
}
