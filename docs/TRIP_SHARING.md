# Consented trip sharing

16 October 2026. The private SQL boundary, authenticated HTTP API and Flutter foreground sharing screen are implemented. The mobile screen has explicit Circle/member selection, 15/30/60-minute consent, a fixed audience, pause/resume, owner stop/revoke, incoming shares and recipient decline. The subsequent [native sharing increment](NATIVE_TRIP_SHARING.md) adds a scoped credential and explicit public background consent/pause/resume, verified in its own 108-second Android cycle. The foreground-only evidence in this record does not establish that later increment.

## Contract

### Mobile foreground scope

Open **Circle → Trip sharing**. Only explicitly selected members receive a grant. Location capture begins after the start acknowledgement (or explicit retry of the identical consent), and runs approximately every 15 seconds while this screen is foregrounded. Leaving it, locking the phone or losing authorization pauses capture; returning does not resume uploads without another explicit action. The separate native route monitor does not upload Circle locations. Recipient maps show only the leased latest fix; expired, revoked, failed-read and backgrounded locations are removed. Lease deadlines use server time plus a local monotonic stopwatch, conservatively including request latency, rather than trusting the phone's wall clock. Incoming lists support pagination.

Unknown start acknowledgements keep the request UUID, audience and duration frozen. The retry button sends that same request; a stopped/expired receipt cannot restart it. Stop/revoke UI is not updated optimistically: only the server receipt/current state confirms access removal. All private screen state is cleared on account changes, and late results are guarded by an account epoch. The foreground screen uses its own location adapter so it cannot cancel the planner or report composer's capture.

The Android integration entry point is `integration_test/sharing_test.dart`; `scripts/test-sharing.ps1` runs the saved test APK against the isolated emulator and disposable local fixture API. Coordinates in this scenario are explicitly synthetic. Runtime results are recorded below.

- One active outgoing share per account. The sharer selects one currently joined Circle and 1–10 named members; membership alone grants no location access. Receiving a share sends no notification or external message.
- Sharing lasts 5 minutes to 2 hours, fixed at creation. Extending or changing the audience requires ending it and making a new explicit decision. Creation is idempotent by an account-scoped request UUID and canonical payload hash; replay cannot resurrect a stopped or expired session.
- Keep one latest position, with accuracy and capture time, rather than a trace. Accept only recent Dhaka-pilot positions, monotonically ordered sequence numbers and at most one changed fix per five seconds. Replays cannot replace a newer position or resurrect an expired point. Location is never included in list responses or control receipts.
- Readers need their explicit grant, current mutual Circle membership, unchanged membership consent epochs, an open Circle, an active unexpired share and no block in either direction. Authorization and exact-position selection must use one SQL snapshot. A revoked read cannot retract an already downloaded location; clients must clear it on revocation/expiry and label freshness.
- Leaving/rejoining, blocking/unblocking or closing a Circle permanently revokes old grants. A recipient can decline a share by revoking their own grant. No operation can add recipients back to the same session. Account deletion cascades private records.
- Stop/revoke is irreversible and idempotent. A delayed position cannot reactivate sharing. Unknown network outcomes must remain visibly unconfirmed until a current server read resolves them; no silent new session or audience substitution.
- Fresh reads expire locations no later than 90 seconds after capture/acceptance or session expiry. Each returned point has its own `expiresAt`, separate from the share's expiry, and `serverTime` supports client clock-offset/lease handling. Recipients must clear coordinates at that deadline even without a successful refresh. A point is a user-reported position with accuracy/time, not verified evidence of physical whereabouts.
- A bounded cleanup operation removes expired coordinates and ended grants while the API runs. Minimal owner/request/hash/sequence/time tombstones remain until account deletion so old consent cannot restart a new session. Expired/ended audience identifiers and Circle associations are removed; no coordinates or profile-name snapshots belong in tombstones. Production supervision, backup retention and cleanup monitoring remain release requirements.

## API

All operations use online-verified Auth and require an adult profile. They do not require phone verification independently of the existing Circle boundary. The authenticated actor always comes from the verifier, never a body field.

| Operation | Contract |
| --- | --- |
| `POST /v1/shares` | `clientRequestId`, `circleId`, 1–10 distinct `recipientIds`, `durationSeconds=300..7200`; returns control receipt and `replayed` |
| `GET /v1/me/share` | Own active control state or `share: null`; no coordinates |
| `GET /v1/share-requests/:requestId` | Own receipt reconciliation, including stopped/expired state |
| `GET /v1/shared-trips` | Authorized incoming summaries only; `limit=1..50` default 30, UUID `after` cursor; no coordinates |
| `GET /v1/shares/:shareId` | One authorized current trip, freshness, server time and the latest position or null |
| `PUT /v1/shares/:shareId/position` | Owner only; bounded integer sequence, Dhaka coordinates, accuracy 1–100 m, capture time within -30/+5 seconds of acceptance |
| `DELETE /v1/shares/:shareId` | Owner's irreversible stop; removes latest position and audience |
| `DELETE /v1/shares/:shareId/recipients/:userId` | Owner revokes a chosen recipient, or recipient declines their own grant |

Control and position payloads have separate versioned hash domains. UUID case, audience order and timestamp offsets are canonicalized before hashing. Immediate identical position replay preserves its original expiry; older/different sequence content receives `stale_position`, and cannot revive a purged point. Changed fixes are limited durably to one per five seconds; unchanged replays consume no interval. Creation is limited to 20 new shares/account/UTC day; replays do not charge again. Common authenticated-account/IP HTTP limits apply to every route. Responses are `no-store`, with fixed allowlists; raw coordinate bodies and token values are absent from request logs.

## Database and retention lifecycle

Migration `202610150009_trip_sharing.sql` creates private control/grant/latest-point tables, membership epochs and irreversible revocation triggers. Direct clients, service-role callers, the API login and the evidence worker have no direct table privileges. The API can execute only the scoped sharing RPC and a fixed, no-argument cleanup function. Readiness refuses direct table/helper grants or missing RPC grants.

Start takes sorted account locks before its Circle/session/grants. Upload and stop take the owner account/session locks. Membership/closure/block triggers revoke grants without acquiring session locks after grant locks. Cleanup locks eligible sessions first, then deletes points/grants, using `SKIP LOCKED` and a 500-session bound. This preserves the mutation order instead of taking point/session locks in reverse.

The API runs cleanup on readiness initialization and every 30 seconds, with at most one pending operation. Successful cleanup readiness ages out after 90 seconds of monotonic process time; failures return a non-ready status without logging private database errors. Shutdown cancels future work and awaits its owned request before closing pools. Other replicas skip locked sessions. Database predicates deny expired/revoked reads even while cleanup is down, but physical erasure depends on a supervised running process and monitored cleanup capacity. Retained recipient copies, external backups and network responses already in flight cannot be recalled by a database revocation.

## Implementation order

1. Complete: private SQL tables, membership epochs/revocation triggers, scoped sharing RPC and retention boundary.
2. Complete locally: strict authenticated API contracts, restricted-role readiness and bounded cleanup lifecycle.
3. Complete locally: focused real PostgreSQL/HTTP scenarios for grants, stale/duplicate positions, consent revocation/rejoin, expiry, isolation and concurrent mutation.
4. Implemented: Flutter sharing controls and recipient view, with account-owned state and English/Bangla copy; local Android verification below.
5. Native session-bound upload/stop transport and lifecycle behavior, followed by the real emulator cycle. Background credential lifetime/refresh must be designed explicitly before connecting it; copying an expiring Flutter access token is not a finished background transport. Hosted Auth and physical-device background validation remain separate gates.

## Current evidence

### Flutter/Android foreground client, 16 October 2026

Final Flutter analysis passes with no issues (20 seconds). The Android sharing cycle passes in process 3324 in 60 seconds against the disposable authenticated HTTP/PostgreSQL fixture backend. It selects a named recipient through the UI, drops an already committed start acknowledgement, explicitly refreshes current state before retrying, verifies identical consent bodies and one position, confirms that foreground exit pauses capture and return does not resume it, reads the selected recipient's fresh position, revokes that recipient and clears the read, confirms stop in Bangla, refuses old-consent resurrection and clears private state on logout. Test cleanup stops the synthetic share and closes its Circle. No notification or external message was sent.

The first Android run passed consent/retry/upload/pause but stopped on a test helper trying to find a lazily built incoming row before scrolling. The helper now scrolls that row into view. Review also exposed a real UI edge case: a successful refresh could discover an active share while its start acknowledgement remained unresolved. The exact-consent retry remains reachable in that state, and the passing run explicitly covers it. Sharing actions and initial recipient reads now have a visible loading indicator; unnamed recipient removal stays disabled until the authorized Circle detail is available.

Current artifacts:

| Artifact | Bytes | SHA-256 | Build |
| --- | ---: | --- | ---: |
| Regular Maps preview | 108,536,895 | `c7d98dbef00cfe2406e91cd236c1b25c9ae399cc94f9c716f8690e3b369fc183` | 279.3 s |
| Sharing integration APK | 110,029,749 | `a8d2fe817d7659cb64c3ed1184e8affae778a81ad5056a5f196ffec90944293a` | 105.6 s |

Screens: [named consent](ui-redesign/sharing-consent.png), [active owner controls](ui-redesign/sharing-active.png), [recipient fixture view](ui-redesign/sharing-recipient.png), [stopped Bangla state](ui-redesign/sharing-stopped-bn.png). Coordinates are synthetic and the test build disables the Google Maps provider/key. The recipient map widget is compiled in the regular preview but this cycle verifies its coordinate/lease state using the fixture view, not a live recipient Google Map. Existing native GPS/route-monitor evidence remains separate. Hosted Auth, native background sharing, physical-device behavior, startup stability and production operations remain open.

The emulator showed platform ANR dialogs before the test application launched. The runner refused to start behind a dialog; a fresh successful hierarchy dump located the Wait action before continuing. No cold-boot stability fix is claimed by the passing sharing scenario.

The final regular preview is restored in process 3646. Its on-device APK SHA-256 matches `c7d98dbef00cfe2406e91cd236c1b25c9ae399cc94f9c716f8690e3b369fc183`. [The restored screen](ui-redesign/sharing-restored-preview.png) shows real Dhaka Google Maps tiles with no covering dialog. The launch wait command timed out after 22,519 ms; observation continued without restarting that process, which reached the visible map. Both `TripMonitorService` and the Geolocator plugin foreground service were absent, and the local fixture API reported ready. This warm recovery is not a resolution of the startup release gate.

### Earlier backend evidence

All 27 API checks and 29 PostgreSQL/PostGIS test nodes pass after the final migration and API wiring. TypeScript and formatting pass; OpenAPI is regenerated. The four sharing database scenarios exercise explicit recipient isolation, no location in lists, one latest row, duplicate/changed/stale positions, rate enforcement, stop and old-consent refusal, leave/rejoin, block/unblock, recipient decline, Circle closure, expiry, cleanup skipping a locked session, direct-role denial, readiness refusal for an accidental table grant and deletion cascade. Real concurrent start/block and stop/upload operations wait on held account locks before release. Two HTTP/lifecycle checks cover canonical consent, strict input/response schemas, Auth/account limits, cleanup coalescing, readiness aging and graceful shutdown.

The final migration was loaded into a fresh disposable Android fixture database. A real network HTTP probe passed: concurrent duplicate consent converged to one share, unselected access was denied, the selected recipient read a fresh leased point, duplicate position retained its expiry, incoming summaries excluded coordinates, recipient decline revoked access and further uploads, and replay of stopped consent remained stopped. Temporary synthetic sharing/Circle records were stopped/closed by the probe. API and real-street routing readiness both passed afterward. No notification or external message was sent.

The emulator's installed APK, contact-block UI cycle and earlier native route-monitor evidence remain separate. No mobile sharing, hosted Auth, recipient map, push delivery, physical-device background upload or production retention guarantee is claimed by these backend checks.

Restoring the unchanged preview reproduced startup ANRs. ActivityManager identified `GeolocatorLocationService` execution waiting 20,255 ms in Awaaz process 2458; System UI and Settings also became unresponsive in that boot. Wait actions returned that process to real Maps, and a later read-only inspection confirmed the native monitor stopped at revision 0. Recurrent dialogs required explicit recovery with the local API/router stopped. Relaunching alone reached [real Maps in process 3701](ui-redesign/sharing-backend-recovered-preview.png), with native monitoring confirmed inactive/stopped at revision 0. The local fixture API was then restarted after the app settled. This is startup evidence, not a sharing-client result or a startup fix. See [startup lifecycle](STARTUP_LIFECYCLE.md).

Final review after the backend restart confirms API/router readiness, the same Awaaz process 3701 in the foreground, [real Maps without a dialog](ui-redesign/sharing-backend-running-preview.png), and no `TripMonitorService`. No Android artifact was rebuilt for this backend-only increment.
