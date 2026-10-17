# SOS requests and delivery

17 October 2026. The authenticated incident API, recipient consent, private inbox/response boundary and transactional notification outbox are implemented. Flutter now connects recipient settings, named audience confirmation, private receipts, explicit responses, cancellation/resolution and foreground location. **Push/SMS transport is not connected.** The page labels the in-app inbox limitation and offers a separate system dialer for 999. The local Android/HTTP/PostgreSQL consumer scenario passes in 146 seconds (process 4994). No real notification or emergency call was sent during this increment.

## Implemented contract

Recipients separately enable receiving help requests from accepted Circles. Joining a Circle is insufficient. Every fresh preference confirmation advances its decision version, including confirming the current value; only an actual value change replaces its consent epoch. This fences older pending decisions without revoking grants when the current value is kept. Sender/recipient phone verification, adult profiles, active memberships, membership epochs, Circle closure and either-direction blocking are checked in SQL. Disabling and re-enabling the preference, or leaving/rejoining, never restores an old grant.

An explicit request freezes its nonce, Circle, 1–10 selected recipients, mode and location permission. A transaction validates the entire audience and creates one incident, private grants and one push job per recipient. A partial audience failure creates none of them. Retries use the same request and hash and return the original state/deadline; terminal consent cannot restart. A different payload with the same nonce conflicts. There is one active incident per owner, a fixed one-hour window and a separate 20-starts-per-day abuse budget; ordinary reporting cannot consume that budget. This is not a claim that deployment capacity or network admission is isolated yet.

Creation does not wait for GPS. Location permission defaults to an explicit API field and can be false. When true, a later owner-authenticated position upload accepts only a recent, accurate Dhaka fix with monotonic sequence, unchanged-retry handling and a five-second new-point minimum. Only the latest point is kept. Each point has a server-issued lease of at most 90 seconds; unavailable/expired means no coordinates. Ending or revoking the last live audience erases the point. A mobile/native SOS publisher remains to be connected; the existing trip-sharing service does not automatically start sending SOS positions.

Reading the recipient view never acknowledges it. An explicit response can be **seen**, **contacting**, **helping**, or **unavailable**. Versioned updates reconcile identical retries and refuse stale/ABA decisions. A response stops further queued alerts to that recipient, leaving other recipients' jobs alone; it cannot end the incident. Only its owner can resolve/cancel it; repeated terminal operations preserve the original outcome. Recipients with current access can see the terminal receipt until the original window expires, with no coordinates.

Unknown start outcomes can be withdrawn by request ID. If create already committed, withdrawal ends that incident. If withdrawal wins first, an owner/nonce tombstone refuses any delayed create. Repeating withdrawal is harmless. Its receipt distinguishes the withdrawn request from any existing incident's actual terminal outcome; it does not promise that an earlier notification was never received. Creating a new request requires a new explicit user decision and nonce.

## HTTP API

All private endpoints require a verified authenticated account; database checks are independent of the transport claim. Responses are no-store and strict schemas reject unsolicited fields.

| Endpoint | Behavior |
| --- | --- |
| `GET /v1/sos/status` | Implemented storage capability; push/SMS delivery flags are currently false |
| `GET/PUT /v1/me/sos-preference` | Read or explicitly change receiving consent with `expectedVersion` |
| `GET /v1/circles/:circleId/sos-recipients` | Eligible, opted-in current members; no phone numbers |
| `POST /v1/incidents` | Atomic incident/grants/jobs; frozen retries |
| `GET /v1/me/incident` | Owner's active incident receipt or null |
| `GET /v1/incident-requests/:requestId` | Reconcile an owner's uncertain start |
| `DELETE /v1/incident-requests/:requestId` | Withdraw a pending or committed request; prevents delayed activation |
| `GET /v1/me/incidents` | Bounded, cursor-paginated recipient inbox |
| `GET /v1/incidents/:incidentId` | Recipient-authorized view; read does not acknowledge |
| `PUT /v1/incidents/:incidentId/position` | Separately consented owner position, sequence and freshness checks |
| `PUT /v1/incidents/:incidentId/response` | Explicit versioned recipient response |
| `DELETE /v1/incidents/:incidentId/access` | Recipient declines access permanently |
| `POST /v1/incidents/:incidentId/end` | Owner resolves/cancels; existing terminal outcome wins |

## Queue and retention semantics

Jobs contain references, kind, incident version and timing/state metadata. They contain no coordinates, message body or phone number. A request job expires after two minutes, independently from the incident's longer private inbox window. Membership/preference/block revocation cancels future attempts. Ending queues a closure update only for still-authorized recipients who may have received the request or explicitly responded; never-sent queued requests can be cancelled without sending a confusing closure alert.

`queued`, `sending`, `provider_accepted`, `failed`, `cancelled`, `expired` and `unknown` are distinct. Cancelling a queued job marks it cancelled. Cancelling an in-flight job records an unknown transport outcome and cancellation time; it cannot invent proof of non-delivery. Existing provider acceptance is preserved. Recipient acknowledgment is recorded separately. FCM's returned message ID indicates acceptance, not device delivery, and delivery order is not guaranteed. Future senders/receivers must therefore enforce the incident version and latest authorized server state. [FCM lifetime and acceptance](https://firebase.google.com/docs/cloud-messaging/customize-messages/setting-message-lifespan), [ordering/collapse semantics](https://firebase.google.com/docs/cloud-messaging/customize-messages/collapsible-message-types).

There is no sender in this increment. Jobs remain queued and then expire; tests do not simulate successful real delivery. The API capability flags remain false. Recording `audible` mode is not a siren implementation.

A coalesced, bounded cleanup runs through the same owned lifecycle used for sharing: one request at a time, 30-second cadence, monotonic readiness aging and graceful shutdown. It locks incident parents first and uses `SKIP LOCKED`; candidate selection is bounded before mutation. Expiry gates reads even while cleanup is unavailable: overdue queued jobs display expired, overdue in-flight jobs display unknown, and owner receipts omit old recipient/response details after their retention window. Precise points expire within 90 seconds, cleanup removes grants/responses 24 hours after the incident window and job history after seven days. Minimal nonce/hash/terminal-state and withdrawal tombstones remain until account deletion to prevent old requests being reactivated. Auth deletion cascades these records. Operational supervision and backup retention must be configured before production.

Client/API/evidence roles have no direct SOS table or internal-helper access. API readiness refuses accidental table or column grants and unexpected helper execution. The evidence worker cannot read SOS records or execute SOS operations. SOS data is separate from public community evidence and model-training inputs.

## Mobile controls

The SOS entry opens a native Material 3 help page. English and Bangla include a system-dialer action for 999, a separate recipient opt-in setting, an eligible Circle audience, explicit named-recipient confirmation, owner receipts, recipient inbox, explicit response choices and irreversible cancellation/resolution. Opening an inbox item never acknowledges it. The page deliberately says that push/SMS are unavailable and that saving a request does not contact emergency services.

An encrypted, owner/backend-scoped journal freezes a single activation nonce, audience, Circle and location choice before sending. Names, coordinates and credentials are not saved in it. A lost acknowledgment is reconciled by reading the nonce receipt; activation is never resent automatically. Retrying requires another review of the identical decision. Withdrawal is journaled before sending and can fence an activation whose result is still unknown. An older activation acknowledgment cannot erase a newer withdrawal.

Coordinates are acquired only after server acknowledgment, with separate foreground consent. Leaving this page, opening account management, locking the device, account changes or upload failure pauses capture. Reopening or recovering a receipt does not resume GPS; explicit resume first refreshes the server sequence to reconcile a lost upload acknowledgment. Only the latest leased point is shown, and expired or inaccessible coordinates are removed. This increment does not implement native background SOS capture; ordinary trip sharing remains a separate consent and service.

Preference/response confirmations bind account lifetime, record ID/version and a one-minute review window. Fresh same-value confirmation advances the decision version so an older pending change cannot land later. A CAS conflict requires a fresh review. Location work does not hold the mutation lock, so Stop remains available during GPS acquisition.

The visual reference is the public Google Personal Safety screen composite linked from [this walkthrough](https://www.inkl.com/news/how-to-use-the-personal-safety-app-to-stay-safe-and-alert-emergency-contacts): named audience, a clear active state and explicit stop controls. These patterns are implemented using this app's existing Material theme; no reference bitmap or US emergency number is embedded. Mobbin discovery was unavailable without a paid plan. This is a reference, not a claim that the older screenshot represents Google's latest UI.

## Verification

The real HTTP/PostgreSQL scenario verifies recipient opt-in and atomic failure, canonical frozen retries, point freshness/expiry, explicit response and stale-decision refusal, owner resolution, pending-request withdrawal and actual start/withdrawal races, preference ABA, decline, leave/rejoin, Circle closure, a simultaneous block/start race, unknown in-flight cancellation, direct role denial, readiness refusal after an accidental column grant and Auth-deletion cascade. Fixture identities and direct synthetic time/state changes are isolated to a marker-protected disposable database. No provider requests are issued.

All 27 API checks and 38 real PostgreSQL/PostGIS nodes passed. TypeScript and formatting checks passed and the offline OpenAPI document was regenerated. The final response/lease-read refinements then passed all five SOS nodes again (14.4 seconds), including the other recipient's job remaining queued and expiry before physical cleanup. Logs are retained locally as `sos-api-tests.log`, `sos-db-all.log`, `sos-db-focused.log`, `sos-api-check.log`, `sos-format.log` and `sos-openapi.log`. The subsequent mobile scenario passes on the owned API 36 AVD in 146 seconds (process 4994): rendered recipient opt-in, named selection/confirmation, a deliberately lost committed activation acknowledgment, encrypted journal recovery by nonce without another POST, no automatic GPS resumption, explicit resume and real Geolocator capture, recipient read without acknowledgment, explicit helping response, owner resolution with location removal, and a Bangla terminal inbox/view. The fixture APK disables Google Maps, so this is not visual evidence for the recipient live map or provider delivery. The later screenshot-review adjustment automatically reveals opened/responded request details and is checked separately by analysis. [The earlier sharing cycle](NATIVE_TRIP_SHARING.md) remains separate evidence.

The full local development API was restored against all eleven migrations after the final SQL changes. `/ready` returned HTTP 200; routing reported enabled/ready; `/v1/sos/status` returned storage available with push/SMS false. The emulator is closed between builds to preserve memory on this host; its previously verified regular Maps APK remains installed.

## Remaining implementation and gates

| Requirement | Current boundary / next work |
| --- | --- |
| Consumer SOS and recipient preferences/inbox | Implemented; the local Android consumer scenario passes |
| Durable private local intent | Implemented encrypted frozen activation/withdrawal journal; lost activation acknowledgment recovery passes on Android, while withdrawal concurrency has HTTP/SQL evidence |
| GPS unknown/fresh/background | Foreground publisher and leased display implemented; native background SOS publisher remains |
| Push transport | Implement restricted claims/leases, authenticated device registration, FCM transport, bounded retry and recipient deduplication; fresh project credentials and a two-device drill are also required |
| SMS escalation | Implement explicit recipient/channel opt-in, a tested provider policy, receipts and bounded escalation; provider account/configuration and local delivery evidence are required |
| Opened/device-received evidence | Add separately scoped device receipts; never infer them from provider acceptance or a GET |
| Resolution updates | Queue creation is implemented; actual sending and late/out-of-order receiver handling remain |
| Emergency dialing and siren | System-dialer fallback implemented; separately controlled audio remains; no automatic dispatch/call |
| Non-app recipient view | Implement scoped, expiring, revocable access and explicit acknowledgment POST |
| Timed check-in escalation | Implement durable server deadlines and separately agreed reminder/grace/escalation policy |
| Operations and release | Reserve command/worker capacity, supervise cleanup/delivery, monitor age/unknown jobs, and exercise recovery; hosted Auth, physical devices/OEM/Doze and the Dhaka pilot remain gates |

For the dialer control, the Bangladesh Police lists **999** as emergency service. This is an official directory reference, not an Awaaz dispatch integration. [Bangladesh Police hotline directory](https://www.police.gov.bd/en/hot_line_number).

## Android artifacts and limits, 17 October

- Functional pass: `.local/sos-android-passed.log`, process 4994, 146 seconds. Fixture HTTP timings: `.local/sos-android-fixtures.log`. No external notification, SMS or emergency call was sent. The 999 control was rendered but not invoked by the test.
- Fresh same-value preference and response confirmations pass all five focused SQL nodes again (16.1 seconds). TypeScript passes. Mobile analysis is clean; the existing journey/help-entry regression passes in four seconds. Prior 27/38 API/database totals belong to the backend checkpoint, rather than a repeated run of every check after the mobile UI work.
- Reviewed screenshots: [active owner receipt](ui-redesign/sos-active.png), [recipient inbox](ui-redesign/sos-inbox.png), [Bangla terminal inbox](ui-redesign/sos-inbox-bangla.png). The latter two capture inbox/receiving controls; they do not show the opened response controls or prove map rendering. Details now reveal themselves on opening/responding so the user does not have to discover content below the fold.
- First cold run: `.local/sos-android-first-run.log` failed at recipient preference confirmation with `network_unavailable`; an authenticated read later confirmed the write committed (`allowed=true`, version 1). The unchanged test later passed. Preflight also refused both an Awaaz ANR dialog and a System UI ANR; their screenshots are retained locally. A covering System UI dialog was explicitly cleared before the successful run. These failures remain a startup/performance gate, not a discarded success criterion.
- Windows reported 20 MB available memory, roughly 3.94 GB nonpaged kernel allocation and approximately 79,000 pages/second during the failed attempt. This host cannot provide reliable smoothness/battery/latency measurements under that pressure. Kernel allocation was still about 3.92 GB after requesting AVD shutdown. The allocation's cause is not established; no system-wide memory settings were changed.
- Push/SMS senders, native background SOS capture, siren audio, non-app access and timed escalation remain unfinished. Hosted Auth, physical-device/release validation and Figma synchronization remain gates.

Final artifact record: regular Maps debug APK SHA256 `D54F8FF6BA2BD7B3793055DFC3F82025EC71A1391B21CBD8EF918184C2B517AE` (108,640,551 bytes; 466.7-second build); passing fixture APK SHA256 `D366521BEE84A5255A86C2691D60009C191753EFFE4FCD1C335EF6605E5BA9C4` (110,129,188 bytes). The final detail-reveal source passes focused analysis; the context is looked up after the frame await without an intervening yield. The full API was restored against all eleven migrations: readiness 200, routing enabled/ready, SOS storage true and push/SMS false. A later emulator launch was blocked by SDK crash-report consent; the launcher now uses the locally documented `-crash-report-mode disabled` option without submitting reports. The AVD subsequently booted, but became unavailable before the final regular-APK installation. The built APK and earlier consumer pass are retained; a final running Maps preview is not claimed for this increment.
