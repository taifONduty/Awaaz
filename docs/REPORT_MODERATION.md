# Report moderation — local backend increment

Implemented 14 October 2026. Migration `202610140005_report_moderation.sql` adds a restricted review queue and approval/rejection ledger. The API uses its existing `awaaz_api` role, verified Supabase session and parameterized RPC calls. This stage does not publish community events or change geographic route costs.

## Access and operator workflow

Only an administrator can provision `awaaz_private.moderators`. User metadata, phone verification and profile fields cannot grant moderator rights. The API, authenticated clients, anonymous clients and `service_role` have no direct access to the grant or audit tables. The RPC checks the current grant, adult profile and database phone confirmation on every request, including retries. Revocation uses the grant row's transaction lock; already running decisions finish before the revocation commits, and subsequent commands are refused.

After applying migrations to a fresh hosted project, an administrator may explicitly provision a reviewed operator account:

```sql
INSERT INTO awaaz_private.moderators(user_id)
VALUES ('REPLACE_WITH_REVIEWED_OPERATOR_AUTH_UUID');
-- Revoke without deleting the minimal audit history:
UPDATE awaaz_private.moderators SET enabled=false
WHERE user_id='REPLACE_WITH_REVIEWED_OPERATOR_AUTH_UUID';
```

No moderators are provisioned by production startup. The subsequent [road-association fixture](ROAD_ASSOCIATION.md) explicitly provisions a test-only reviewer in its owned disposable database. Hosted Auth is still unconfigured; this increment was exercised in disposable local databases with synthetic identities.

The operator command uses an ordinary verified access token. Set `AWAAZ_MODERATION_API_URL` and `AWAAZ_MODERATION_ACCESS_TOKEN` in an ignored `apps/api/.env.moderation` file, then run from `apps/api`:

```powershell
node scripts/moderation.ts request-id
node --env-file=.env.moderation scripts/moderation.ts queue
node --env-file=.env.moderation scripts/moderation.ts queue <nextCursor>
node --env-file=.env.moderation scripts/moderation.ts approve <reportId> <requestId>
node --env-file=.env.moderation scripts/moderation.ts reject <reportId> personal_information <requestId>
```

Reuse the same request UUID after an uncertain response. The command accepts HTTPS or loopback HTTP, rejects redirects and URL credentials, limits responses to 256 KiB and times out after 15 seconds. Queue output contains private report text and coordinates for review; it excludes reporter identity. This command is an interim operator surface, not a finished moderation console.

## API and decision semantics

`GET /v1/moderation/reports?limit=20&cursor=...` returns pending reports oldest first, at most 50 per page, and `nextCursor`. A moderator's own submissions are excluded. Responses are `no-store`; server logs retain route templates and status only. Cursor timestamps preserve Postgres microseconds to avoid repeated or skipped boundary rows.

`POST /v1/moderation/reports/:reportId/reviews` accepts only `clientRequestId`, `decision` and `reason`. `approve` requires `reviewed`; rejection reasons are `duplicate`, `unverifiable`, `personal_information`, `outside_scope` or `resolved`. No client can supply a public summary, reporter identity, road ID, score or expiry.

New decisions return 201; retries return 200 with the original decision and expiry. Changed payloads under the same request UUID conflict. Report row locks serialize reviewers and withdrawal. Self-review is refused. The original submission becomes `reviewed` or `rejected`; its durable owner receipt reflects that status.

Approval is a candidate for later publication, not verification that an allegation is true. An approval expires from the original observation time according to this explicit pilot policy:

| Category | Maximum evidence lifetime |
| --- | --- |
| Accident | 1 hour |
| Theft, harassment, other | 2 hours |
| Obstruction | 6 hours |
| Lighting | 12 hours |

Already stale candidates cannot be approved; they can be rejected as resolved. Delayed review and retries cannot renew evidence. These durations need pilot calibration; they are not learned safety estimates.

Withdrawal deletes private text/location and any existing published event through the existing FK cascade. The review ledger retains only reviewer/request/report IDs, decision/reason, hash and timestamps. It intentionally has no report FK; a replay after withdrawal returns `status: withdrawn` and never restores the submission. Moderator account erasure cascades that moderator's ledger rows, consistent with the current account-erasure model. A reviewed operational retention policy is still required.

## Verification and next stage

Strict TypeScript and formatting checks pass; all 22 existing API checks pass. The database suite passes 20 test nodes: the existing parent plus 18 scenarios and one focused moderation scenario. That scenario exercises real SQL permission denials, grant revocation, independent database phone confirmation, pagination, self-review, idempotent decisions, conflicting commands, simultaneous reviewers, stale approval and withdrawal. It checks that neither `road_events` nor `edge_risk` receives invented evidence. Database test files run sequentially because migrations provision a cluster-wide API role; business-operation concurrency is still exercised inside the scenarios.

The subsequent [road-association increment](ROAD_ASSOCIATION.md) implements exact-edge registration, moderator selection and sanitized publication through a separate command. Approval alone still publishes nothing. Remaining work includes a moderation console, appeals and operational abuse handling, withdrawal-safe expiring evidence snapshots and an evaluated risk-aware GraphHopper extension. Routes continue to report unknown safety coverage. No model has been trained and no safety ranking is enabled.
