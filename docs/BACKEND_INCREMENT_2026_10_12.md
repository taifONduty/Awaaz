# Backend increment: accounts, trusted circles and community data

## Starting point

The API has one authenticated report-write endpoint and five passing unit tests. The first PostGIS schema has not yet been exercised against a database. Flutter is still a demo client; no production accounts, locations or emergency delivery are connected.

## Implementation order

1. Add bounded, typed endpoints for own profile setup/read, circles, intended-account invitations, explicit acceptance, revocation, leaving and closure.
2. Keep Supabase Auth for online token verification. Replace broad service-role data access with a PostgreSQL connection using an `awaaz_api` role that can execute only scoped database operations. Transactions enforce actor ownership and concurrency constraints.
3. Add own-report reads/deletion, deletion retry tombstones, a sanitized bounded event feed and durable account quotas. Raw reports remain private and publication remains an operator/moderation responsibility.
4. Add response schemas, generated OpenAPI, configured CORS, non-cached private responses, readiness, privacy-conscious logs and graceful shutdown.
5. Run meaningful HTTP/adapter tests and database integration tests: two users and a stranger, expired/replayed/revoked invites, concurrent requests, RLS, denied direct writes, hidden hashes/source IDs, deletion cascades and the restricted API role.
6. Document local setup and cloud configuration. No old credentials, production deployment, real notifications or claimed live road coverage are part of this increment.

## Contract choices

- Profile setup requires an explicit adult attestation. This is self-attestation, not identity verification. Phone confirmation remains separate and is required to submit road reports.
- An invite identifies its intended account. A copied token cannot join a different account. It expires, is single-relationship consent, and cannot restore a revoked membership. Tokens are hashed in storage; replayable token derivation uses a server-only secret. Rotation prevents regenerating old creation tokens. Already-issued tokens remain valid until expiry/revocation; redelivery requires revocation and a new command, and a compromise requires explicit revocation.
- Membership grants no location access. Journey/SOS sharing grants and the durable notification worker follow this foundation.
- Each write uses authenticated actor IDs, never client ownership fields. Circle creation/report submission and invite creation have explicit idempotency contracts.
- The API database role has no direct table writes, Auth-user reads or arbitrary moderation authority. Its scoped operations are server-only; client roles retain RLS.
- Lists are bounded. Private report pagination uses a validated cursor. Public event reads filter expiry and exclude source submission IDs, identities and exact private text/location.

## References checked

[Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security), [database functions](https://supabase.com/docs/guides/database/functions), [Postgres connection options](https://supabase.com/docs/guides/database/connecting-to-postgres), [node-postgres TLS configuration](https://node-postgres.com/features/ssl), and [Fastify schemas](https://fastify.dev/docs/latest/Reference/Validation-and-Serialization/). Scoped functions use an empty search path and explicit grants; pooled calls use parameterized, unnamed statements.

## Remaining production work

Fresh Supabase project credentials and real Auth integration drills; Flutter wiring; account blocking/deletion workflows; moderation/audits/appeals; authenticated sharing grants, journeys and SOS commands/outbox; map/routing integration; native Android monitoring; provider delivery; operating/restore/pilot evidence. This increment does not complete those release gates.

## Completed implementation and evidence

Accounts, Circles/invitations, private report history/withdrawal, published-event reads, restricted SQL operations, durable quotas, privacy-conscious responses/logging, readiness, CORS and OpenAPI export are implemented. Per-account minute limits respect shared Wi-Fi/mobile IPs. The old service-role data adapter has been removed.

Formatting and TypeScript checks pass, as do 19 HTTP/adapter cases and 17 real PostgreSQL/PostGIS scenarios. A portable integration-only PostgreSQL 17.11/PostGIS 3.6.2 cluster enabled database verification despite Docker's unavailable daemon. [Setup and contracts](../backend/README.md) and [detailed evidence/limits](BACKEND_VERIFICATION.md) record the reproducible checks and cloud integration gates.
