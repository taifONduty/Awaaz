# Awaaz backend

The API implements accounts, consented trusted Circles, private contact blocking, temporary latest-position sharing, scoped native sharing credentials, consented SOS incidents/inbox/outbox, report submission/history/withdrawal, reviewed road publication and evidence snapshots. The runtime is in `apps/api`; eleven ordered migrations are in `backend/supabase/migrations`. This uses a fresh project and does not depend on the prototype's cloud credentials or mock users.

The implementation and its authorization rules have been exercised against PostgreSQL 17.11 with PostGIS 3.6.2. Flutter has account and geographic-routing adapters alongside isolated fixture adapters. A fresh Supabase project's Auth, pooler and Data API must be checked before real accounts are connected. [Verification evidence](../docs/BACKEND_VERIFICATION.md) distinguishes local database tests from cloud integration.

## Access boundary

The [SOS backend](../docs/SOS_DELIVERY.md) requires separate recipient opt-in and an explicit selected audience. Incident/grant/job creation is atomic; pending requests can be withdrawn before a delayed create, and responses never silently resolve the incident. Queue state, provider acceptance and a person's acknowledgment remain distinct. Push/SMS transports and the mobile SOS controls are unfinished; `/v1/sos/status` reports those delivery channels unavailable. No real message is sent by the current worker set.

Supabase Auth verifies every bearer token online. The token's user ID supplies ownership; clients cannot send an owner ID. Reporting additionally requires confirmed phone control, checked both by the API and against Auth's database record. Profile setup requires adult self-attestation. Neither attestation nor phone confirmation establishes identity or report truth.

Database calls use a dedicated `awaaz_api` connection, not a service-role key. This role has no direct application-table privileges or Auth-user reads. It executes scoped transaction functions in `awaaz_private`, whose fixed search paths and explicit grants prevent client invocation. Evidence refresh uses a separate restricted role. Parameterized, unnamed calls work without named prepared statements. Client reads have RLS and column grants; direct profile/Circle/report writes are denied. RLS membership helpers only evaluate the caller's own membership.

Circle membership permits Circle details and member display names. It grants **no location access**. Invitations bind the recipient account and a separate secret token; joining requires both. Intended recipients can decline, members can leave, owners can remove members or close a Circle. The owner must close a Circle rather than silently leaving it.

The separate [trip-sharing API](../docs/TRIP_SHARING.md) requires an explicit fixed-duration audience and retains only one latest recent point. Membership/closure/block revocation invalidates grants permanently; rejoin/unblock does not restore them. Each returned position has its own expiry. The API's bounded cleanup lifecycle removes expired coordinates and ended audiences, with readiness aging on cleanup failure. Flutter has explicit consent and recipient controls. The [scoped native transport and consumer controls](../docs/NATIVE_TRIP_SHARING.md) passed foreground/native handoff, pause/resume, screen-off upload, notification stop, lost-acknowledgement replay and account-change shutdown against real local HTTP/SQL. Hosted Auth, process/reboot delivery and physical-device checks remain open.

Reports start as pending private submissions. The implemented [moderation workflow](../docs/REPORT_MODERATION.md) requires separately provisioned reviewers and refuses self-review. [Real-road association](../docs/ROAD_ASSOCIATION.md) requires an explicit road selection, publishes fixed sanitized summaries and applies coarse coordinate precision in SQL. The public feed returns only unexpired published events and excludes reporter/source IDs and raw descriptions. A consumer moderation console and appeals remain unfinished.

## API contracts

All `/v1` operations require a Supabase bearer token. Set `Authorization: Bearer <access-token>`. Request and response schemas reject unexpected fields and exclude internal response data.

| Method | Path | Behavior |
| --- | --- | --- |
| GET / PUT | `/v1/me` | Read own identity/profile; create or update adult-attested profile |
| GET | `/v1/me/blocks` | Private paginated list of outgoing active blocks |
| GET / PUT | `/v1/me/blocks/:userId` | Read or explicitly change a versioned outgoing block decision |
| POST | `/v1/shares` | Idempotent explicit share for 1–10 selected current Circle members, fixed 5-minute to 2-hour lifetime |
| GET | `/v1/me/share` | Own current share control state; no coordinates |
| GET | `/v1/share-requests/:requestId` | Own creation receipt/status reconciliation |
| GET | `/v1/shared-trips` | Authorized incoming summaries; no coordinates |
| GET / DELETE | `/v1/shares/:shareId` | Authorized latest point, or owner's irreversible stop |
| PUT | `/v1/shares/:shareId/position` | Owner's recent, ordered, accuracy-bounded latest point |
| DELETE | `/v1/shares/:shareId/recipients/:userId` | Owner revokes a recipient, or recipient declines their own grant |
| GET / POST | `/v1/circles` | List active memberships; idempotently create a Circle |
| GET / DELETE | `/v1/circles/:circleId` | Read as a member; close as owner |
| POST | `/v1/circles/:circleId/invites` | Owner invites an existing adult-profile account |
| GET | `/v1/circle-invites` | Intended account's pending, unexpired invitation inbox |
| POST | `/v1/circle-invites/:inviteId/accept` | Accept with the token as the intended account |
| DELETE | `/v1/circle-invites/:inviteId` | Revoke/decline; an accepted invitation's membership is also revoked |
| DELETE | `/v1/circles/:circleId/members/:memberId` | Leave yourself, or owner removes a member |
| POST | `/v1/reports` | Submit within the provisional Dhaka pilot; confirmed phone required |
| GET | `/v1/reports` | Own private history with keyset pagination |
| DELETE | `/v1/reports/:reportId` | Withdraw own private payload and linked public event atomically |
| GET | `/v1/road-events` | Published-event feed filtered by viewport and expiry |

Circle/report creation and invitations take a UUID `clientRequestId`. Repeating identical input returns the original receipt with `replayed: true`; changing the payload returns `409 idempotency_conflict`. Withdrawal retains a minimal private retry record, so an identical retry returns `withdrawn` and cannot restore deleted text or coordinates. Daily quota counters also survive deletion. Retention cleanup for these records remains a production gate.

Invitations use `recipientId` and optional `expiresInSeconds` (300–604800, default 86400). Recipients must already have a profile; there is no public account/phone directory. The future client can exchange account IDs through an explicit contact/QR flow. Raw tokens are returned to the inviter, never stored or included in the inbox. Delivery through the inviter's chosen channel is not automated by this API.

A server-only HMAC secret makes invitation-creation retries return the same token. After secret rotation, old creation retries return `invite_reissue_required`; revoke and create a new invitation with a new request ID to redeliver. Already-issued tokens remain usable until expiry or revocation because acceptance checks their stored hash. A suspected compromise requires explicit revocation as well as rotation.

Report/event lists accept `limit=1..100`, default 50. Private history accepts the returned `nextCursor`. Contact blocks accept `limit=1..50`, default 30, and an `after` UUID cursor. [Blocking contract](../docs/CONTACT_BLOCKS.md) covers account-bound decisions, stale-write rejection, invitation revocation and non-restoring unblock. Event viewports supply all four of `south,west,north,east`; each span is at most 0.6 degrees. The default rectangle is 23.62–24.02 latitude / 90.20–90.58 longitude. This is provisional operational coverage, not an audited Dhaka administrative boundary.

The generated [OpenAPI 3.1 document](openapi.json) contains the complete request/response contracts. Run `pnpm openapi` to regenerate it without connecting to Auth or a database.

## Limits and operational behavior

- Per process: 600 requests/minute/IP before Auth, 120/minute/authenticated account, and 20 report attempts/minute/account. Shared addresses do not merge account quotas. Proxy trust is disabled; a hosting reverse proxy needs explicitly audited trust configuration and an upstream traffic limit.
- Durable database quotas per account per UTC day: 10 Circle creations, 20 invitations, 20 report submissions, 200 changed block decisions and 20 new trip shares. Replays do not charge again; failed transactions do not consume quota. One active outgoing share is allowed per account; changed positions are limited durably to one per five seconds.
- Capacity: five active owned Circles, twenty active Circle memberships per account, twenty members per Circle including its owner. Concurrent mutations serialize the relevant account/Circle changes.
- `/health` is process liveness. `/ready` checks database access, required functions and the restricted role. Startup fails if this boundary is not ready.
- Private responses use `Cache-Control: no-store`. CORS accepts only configured origins. Logs contain request IDs, methods, route templates and status codes, without token/body/query/user identifiers.
- Remote PostgreSQL uses verified TLS, with an optional vendor CA. SSL URL parameters are rejected to prevent driver options overriding verification. The connection pool has six clients and bounded connection/query/SQL/lock timeouts.
- SIGINT/SIGTERM drain the server and close its pool. No Windows service, public port, auto-start task or external deployment has been installed.

The minute limits are in-process traffic protection, not distributed abuse prevention. Durable SQL quotas span API replicas. A production ingress and load/soak evidence are still required.

## Local verification without a cloud account

Node 24+ and pnpm are required. From the repository root:

```powershell
./scripts/start-test-postgres.ps1
./scripts/check.ps1 -BackendOnly -DatabaseTests
./scripts/stop-test-postgres.ps1
```

This laptop has a portable PostgreSQL/PostGIS installation at `C:\Users\User\.codex\toolchains\postgres-17.11\pgsql`. On another Windows machine supply `-PgBin` pointing to compatible installed binaries with PostGIS. The startup script uses loopback port 54329, SCRAM authentication and an explicitly marked integration-only cluster. It creates no system service.

Generated synthetic credentials are kept under ignored `.local/backend-postgres` and `apps/api/.env.test`. The integration harness refuses non-local or unmarked clusters, creates a fresh random test database, loads a **test-only** Auth/role bootstrap plus all migrations, and drops only that generated database afterward. Never apply `backend/test/bootstrap.sql` to Supabase.

From `apps/api`, the individual checks are:

```powershell
pnpm install --frozen-lockfile
pnpm format:check
pnpm check
pnpm test
pnpm test:db
pnpm openapi
```

The database tests use synthetic users and a test verifier. Separate Auth-adapter tests exercise the real SDK's request/error handling against a mocked transport. This does not certify Supabase OTP, session revocation, PostgREST, Realtime or production TLS.

## Run against a fresh Supabase development project

1. Create the development project. Apply every SQL migration in filename order (currently ten) using a privileged migration connection. PostGIS must be in `extensions`. Do not add `awaaz_private` to exposed Data API schemas.
2. The migrations create `awaaz_api` as NOLOGIN/NOINHERIT. In a privileged **psql** session run `ALTER ROLE awaaz_api LOGIN;`, then `\password awaaz_api` to set a unique password interactively. Do not grant it other role memberships or application-table privileges.
3. Copy `apps/api/.env.example` to `.env`. Configure the fresh project's URL and publishable key; use a database URL for `awaaz_api`. For a shared Supabase pooler its username is `awaaz_api.<project-ref>`; use the actual host/port from the project's Connect panel. A persistent IPv4 backend can use its session pooler. Percent-encode password characters.
4. Set a random 32-byte `INVITE_TOKEN_SECRET` as 64 hexadecimal characters in local secret configuration. Configure the vendor CA path if needed and explicit web origins. Do not place database passwords, the invitation secret or service-role keys in Flutter.
5. Run `pnpm dev` in `apps/api`. The default API address is `http://127.0.0.1:3030`, separate from the Flutter preview at port 8765. It only starts when configuration and restricted database readiness pass.
6. Check real Auth sessions, phone confirmation, revoke/expiry behavior, both clients' RLS/Data API access and the chosen TLS/pooler endpoint in that disposable project before enabling Flutter network adapters.

These settings follow [Supabase roles](https://supabase.com/docs/guides/database/postgres/roles) and [connection guidance](https://supabase.com/docs/guides/database/connecting-to-postgres). The code owns its TLS settings because connection-string SSL options can replace the driver's SSL object; see [node-postgres TLS](https://node-postgres.com/features/ssl).

## Next backend increments and release gates

1. Connect Flutter Auth/profile/Circle/report repositories; implement contact-ID exchange, account blocking and explicit account deletion with sessions revoked and full erasure.
2. Add moderation queue, narrowly scoped operator roles, observable-event review, audit/appeals, media isolation and retention jobs. Never auto-publish accusations about identifiable people.
3. Add opt-in, revocable journey/location-sharing grants, trip persistence and atomic SOS/outbox commands. Workers need provider receipts, retries, cancellation and recipient authorization at send time. Provider acceptance must not be labelled human acknowledgement.
4. Integrate licensed maps/geocoding and audited road graphs, versioned risk snapshots and routing. Withdrawal/expiry must invalidate derived overlays. Roads without evidence retain an unknown risk state; the existing constraints reject invented zero risk.
5. Validate native Android screen-off monitoring, push/SMS providers, operational monitoring, load/soak behavior, secrets rotation, backups/restore, and a controlled Dhaka pilot.

No live notifications, background tracking, production routes or ML training are enabled. The full design is in [the road-safety plan](../docs/AWAAZ_ROAD_SAFETY_DESIGN.md). This increment establishes the account and community data boundary; it does not complete the public-release gates.
