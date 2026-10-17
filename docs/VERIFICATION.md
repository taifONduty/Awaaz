# First-slice verification — 12 October 2026

## Mobile SOS consumer flow, 17 October 2026

The real local Android/HTTP/PostgreSQL scenario passes in 146 seconds (process 4994): rendered opt-in and named consent, a lost committed save acknowledgment, encrypted nonce receipt recovery without resending, explicit GPS resume and capture, recipient read/response, owner resolution and a Bangla terminal view. Five focused SOS SQL nodes, TypeScript, mobile analysis and the existing journey/help-entry regression pass. The post-review detail auto-scroll is an additional small UI change, with its own final analysis. Push/SMS are disconnected; fixture Maps rendering is disabled. Cold-run network/ANR failures and severe Windows memory pressure remain explicit performance/startup gates. [Exact scope and screenshots](SOS_DELIVERY.md).

## SOS incident and outbox backend, 17 October 2026

Migration 11 and the verified-account API implement separate receiving consent, atomic incident/grant/job creation, frozen retries, pending-request withdrawal, explicit versioned recipient responses and owner-only resolution. All 27 API checks and 38 real PostgreSQL/PostGIS nodes pass. The final response/lease-read refinements pass the five SOS nodes again, covering suppression of that recipient's queued alerts and expiry before physical cleanup. TypeScript and formatting checks pass; offline OpenAPI is regenerated. Scenarios cover true start/block and start/withdrawal races, preference ABA, leave/rejoin/closure, accurate in-flight unknown states, expiring points, direct-role/column-grant denial and account erasure. These are synthetic local HTTP/SQL checks; push/SMS transports remain unfinished; mobile controls are covered by the subsequent increment above. [Contract, evidence and remaining launch requirements](SOS_DELIVERY.md).

## Consumer background sharing, 16 October 2026

The consumer Android cycle passed in 108 seconds, process 3884: real foreground capture/upload, cancellation, explicit named-audience background consent, Dart/native handoff, pause/resume without extending expiry, screen-off native upload and recipient read, actual notification Stop, recovery after a lost committed stop response, old-consent refusal and account-change shutdown. Final Flutter analysis is clean. A fixture timing correction supplies fresh HAL fixes during setup and stops them before the separate background location marker; production location validation/timeouts remain intact. The API/database/native-JVM results below belong to their recorded transport increment and were not needlessly repeated for these UI controls. Hosted Auth, process/reboot delivery, physical-device behavior and startup stability remain open. [Current APKs, screenshots and scope](NATIVE_TRIP_SHARING.md).

## Scoped native sharing transport, 16 October 2026

The native Android cycle passed in 91 seconds against production HTTP/SQL with synthetic fixture identities. It verifies screen-off position capture/upload in the same process, a recipient read, actual notification Stop, lost committed stop-acknowledgement replay, refusal to reactivate stopped consent and shutdown on account change. All 27 API checks, 33 real database test nodes and six native JVM checks pass; transport-source Flutter analysis is clean. Public background controls are a subsequent integration increment. Process/reboot delivery, physical-device/OEM behavior, hosted Auth and startup stability remain open. [Artifacts, exact scope and unfinished work](NATIVE_TRIP_SHARING.md).

## Foreground sharing client, 16 October 2026

Final Flutter analysis is clean. The real Android/HTTP sharing cycle passes in 60 seconds: named consent, lost acknowledgement with a current-state refresh before identical retry, one position, explicit foreground pause, selected-recipient read, irreversible access removal, Bangla stop, old-consent refusal and logout isolation. Synthetic coordinates and local fixture accounts are used; the integration build disables Google Maps. The final regular preview is restored with real Dhaka tiles and an installed APK hash matching the saved build. Native background upload/stop, hosted Auth, startup stability and production operations remain open. [Artifacts, screenshots and exact boundaries](TRIP_SHARING.md).

## Temporary sharing backend, 15 October 2026

All 27 API checks and 29 real PostgreSQL/PostGIS test nodes pass with migration 9. TypeScript and formatting are clean; OpenAPI is regenerated. Focused sharing scenarios cover explicit-audience isolation, recent latest-point updates, unchanged-expiry replays, sequencing/rate limits, stop and old-consent refusal, membership/block/closure/recipient revocation, expiry/cleanup, restricted-role access and actual concurrent start/block and stop/upload operations. The cleanup lifecycle has monotonic readiness aging and owned shutdown verification. [Exact contract, evidence and mobile/native work still open](TRIP_SHARING.md). This backend evidence does not establish an Android sharing flow, hosted Auth, background upload, push delivery or production retention.

## Contact blocking, 15 October 2026

The final contact-block migration passes all 24 real PostgreSQL/PostGIS nodes, including actual block-versus-join/invite races. All 25 HTTP/adapter checks pass; TypeScript and formatting are clean. The local deployed HTTP probe verifies duplicate convergence, revoked membership, stale rejection, refusal of an old token, non-restoring unblock and hidden former-contact names. All 34 focused Flutter account API/view-model/widget checks pass, including lost-acknowledgement reconciliation, invalidated approval across logout/login, no automatic retry, and English/Bangla controls at 320 pixels with double text size. Flutter analysis is clean. The dedicated Android cycle passes against real local HTTP/PostgreSQL, exercising rendered member/sender controls, a committed write with a dropped acknowledgement, revoked membership, old-token refusal and non-restoring unblock. The regular Maps preview is restored and its installed hash verified; API/router readiness pass and no trip-monitor service is active. [Artifacts, screenshots and exact scope](CONTACT_BLOCKS.md). These are local fixture checks, not hosted Auth or production load evidence. A System UI ANR appeared at the launcher before the test and required its visible Wait action; the wider startup limitation remains unresolved.

## Explicit monitored-route replacement, 15 October 2026

The active geographic journey now supports consented fresh-origin lookup and explicit replacement without changing the baseline during comparison. Native acceptance checks the plan lease; a matching owner/session/route/next-revision receipt commits the new route. The real-graph emulator review verifies expired-plan refusal, fresh acceptance from revision 1 to 2 in the same session, display-off check-in notification 7102, acknowledgement preserving revision 2 and a confirmed stop with no trip service. Android's HAL interactive hint remains true despite framework sleep/display off; this is not physical Doze/OEM evidence. All 18 focused Flutter cases and five native cases pass. The feedback/alert-visibility refinements pass the same 18 cases and full static analysis. Their final APK is installed with a matching device-side checksum; an actual startup-status timeout, explicit Retry and confirmed-off recovery are reviewed. The original native cycle belongs to its preceding build, as detailed in the evidence. Startup remains unresolved. [Builds, screenshots and scope](ROUTE_REPLACEMENT.md).

## 15 October: native status recovery and profile startup comparison

Native status failures now show an explicit unconfirmed state, actionable Retry and owner-binding reconciliation. Unknown snapshots cannot silently end the visible journey. All 12 focused monitor cases pass, including the extended Bangla large-text/reconciliation journey flow; changed-source static analysis is clean. The local profile APK builds, installs and renders Maps; Explore/Community/Circle navigation and actual API-backed Farmgate search work on the emulator. Cold and warm profile launch observations still time out around 13 seconds, and a cold System UI ANR recurs. Startup is unresolved. [Artifact hash, exact observations and scope](STARTUP_LIFECYCLE.md#15-october-status-recovery-and-anr-diagnosis).

## Named-place search increment, 15 October 2026

An offline public OSM catalogue supplies 36,563 named features to a bounded, provenance-bearing API and bilingual Flutter picker. All 24 API cases and 16 focused UI/geographic cases pass; TypeScript/formatting/static analysis are clean. Installed review verifies real keyboard lookup, separate pin confirmation, a real 5 min / 3.9 km route, Bangla names/categories and explicit retry after backgrounding. A final copy/style rebuild corrects a stale Bangla hint and subordinates attribution. The native monitor/database schema are unchanged; their older restart-suite evidence is not presented as a new run. [Contract, data limits, builds and screenshots](NAMED_PLACE_SEARCH.md).

## Evidence worker increment, 14 October 2026

A standalone restricted refresh worker now provides serialized graph leadership, atomic private health, recovery backoff, bounded retention and graceful shutdown. TypeScript/formatting checks, 23 API cases and 20 database test nodes pass. An actual 125,679-edge disposable-database diagnostic verifies dedicated LOGIN, denied Auth access, cycle coalescing, standby, scoped-permission failure/recovery, stale-health refusal and graceful owned IPC stop/lock release. One deletion-boundary case covers retention limits and preserved files/junction refusal. [Runtime/deployment scope and emulator integration evidence](EVIDENCE_WORKER.md).

## First-frame startup increment, 14 October 2026

The application now renders a loading surface before account/session initialization and owns/disposes the services created by that startup container. Coordinate-free timeline markers distinguish the first framework frame and account setup. Static analysis and 12 focused UI checks pass, including one consequential delayed-initialization/disposal scenario. The updated APK builds in 172.4 seconds and reaches Explore on a cold and warm launch with no recorded ANR in that emulator boot. Both launch observations nevertheless exceed Android's `am start -W` observation window, so slow startup and the earlier cold-start ANR remain unresolved. English/Bangla navigation works after launch. No backend or native monitor logic changed; their earlier verification is not presented as a fresh run. [Source contract, actual observations and remaining performance gates](STARTUP_LIFECYCLE.md).

## Reported-route integration, 14 October 2026

The experimental adapter now connects reviewed-evidence weighting to the route API and Flutter picker. A real-graph HTTP diagnostic returns distinct fastest/reported paths with immutable snapshot provenance, a shortened lease, explicit synthetic fixture labeling and unknown safety assessment. All 22 API checks, 20 database test nodes and 78 Flutter cases pass. Installed English/Bangla review confirms different geometry and visible choices/disclosure. The selected reported route armed the native service, generated a private check-in while the emulator was asleep, and stopped cleanly. A subsequent UI refinement moves monitor status above the map; analysis and 22 existing UI/monitor checks pass. Final build/review details are maintained in [Reported-route integration](REPORTED_ROUTE_INTEGRATION.md). The older six-case Android restart suite was not rerun for this increment.

## Evidence weighting engine increment, 14 October 2026

The read-only GraphHopper extension adds nonnegative per-edge evidence penalties while preserving access/turn constraints, physical time estimates and the base admissible heuristic. Six weighted car/walking A* costs match Dijkstra. Real-graph synthetic corridor observations change a selected route; virtual snap fragments get the original edge's multiplier, wrong digests fail, and a database epoch change during search rejects the result. TypeScript/formatting checks and the 22 existing API checks pass. This is an isolated engine/coordinator increment: the public API and mobile picker do not consume it yet, no APK changed, and Android cases were not rerun. [Algorithm, protocol, evidence and integration work](EVIDENCE_ROUTING_ENGINE.md).

## Evidence snapshot increment, 14 October 2026

Reviewed evidence now has sparse graph/epoch-bound snapshots with a two-minute maximum lease, conservative temporal grouping, contributor caps and explicit unknown defaults. API and Supabase RLS reads refuse withdrawn/expired evidence. Coarse public coordinates are enforced in SQL and direct centroid reads revoked. A real-graph disposable-database diagnostic verifies sparse storage, separate incident/environment dimensions, artifact export, role isolation, withdrawal invalidation, empty state and expiry. The status API continues to return `safetyAssessment: unknown`; geographic routing does not consume snapshots yet.

TypeScript/formatting checks, all 22 existing API checks and 20 database test nodes pass. All six existing Android cases pass in both restart phases with the snapshot-enabled fixture backend, using the unchanged test APK. No additional Android cases were written. These are synthetic observations/identities and emulated GPS. [Snapshot semantics, worker/artifact contract and remaining engine integration](EVIDENCE_SNAPSHOTS.md).

## Real-road association increment, 14 October 2026

The read-only GraphHopper export and restricted PostGIS import register 125,679 usable Dhaka edges with direction/access flags, artifact provenance and immutable graph metadata. Approved reports require explicit moderator selection within 35 metres before fixed-vocabulary coarse community publication. A real-graph disposable-database check verifies import isolation/replay, candidate access, approval/proximity gates, sanitized feed output, publication retries, withdrawal and evidence-epoch invalidation. It creates no risk score.

All 22 existing API checks and 20 database test nodes pass, including concurrent harness setup after fixing cluster-wide role races; TypeScript/formatting checks and Flutter analysis are clean. The integration APK builds in 317.5 seconds. All six existing Android cases pass in both process-restart phases against the actual review/association/publication fixture pipeline. The first attempt hit an emulator System UI ANR cover; guarded capture failed correctly, the dialog was resolved, and the full retry passed. No physical-device or live-Auth claim is made. [Provenance, APK digest, workflow, screenshot and remaining work](ROAD_ASSOCIATION.md).

## Moderation backend increment, 14 October 2026

Strict TypeScript and formatting checks pass. The 22 existing API checks and all 20 database test nodes pass after migration `202610140005_report_moderation.sql`. The focused real-SQL moderation scenario covers restricted grants and direct-table denials, independent phone verification, pagination, self-review, idempotent/conflicting decisions, concurrent reviewers, stale approval, withdrawal and revoked access. It also verifies that approval creates no public event or edge score. Database test files are serialized because their migration setup changes cluster-wide roles; operation-level concurrency checks remain active. A timestamp cursor truncation bug discovered during queue verification was fixed by preserving Postgres microseconds.

The disposable Android fixture API was restarted with the new migration; database readiness and the existing real GraphHopper router are ready. No Android source changed or APK was rebuilt in this backend increment. The prior real-route emulator evidence remains the mobile baseline. [Operator workflow, privacy boundary and remaining work](REPORT_MODERATION.md).

## Geographic routing increment, 14 October 2026

GraphHopper 11.1 imports actual buffered Dhaka OSM roads and serves versioned car/walking A* routes through the API. Six representative route costs match Dijkstra. Safety coverage is explicitly unknown and estimates exclude live traffic. All 22 API checks, 78 Flutter checks and later focused UI/monitor checks pass; analysis and API type/format checks are clean. The final Android preview builds in 171.3 seconds and displays real geographic routes in English/Bangla. A real returned corridor armed the native monitor, produced a private check-in while the emulator was asleep, acknowledged without contacting anyone, and ended with the service stopped. These use emulated GPS, not physical-phone proof. [Data provenance, APK hash, screenshots, limits and remaining work](REAL_ROUTING_INTEGRATION.md).

## Journey UI increment, 14 October 2026

The active journey and native monitor now form one surface, with a contextual arming confirmation and completion only after an inactive native stop response. All 22 existing focused UI/monitor checks pass; final analysis is clean. The Android preview builds in 261.7 seconds and is reviewed on the emulator in English/Bangla, including simulated check-in, keeping the baseline and finishing. Real Google Maps tiles still load. Cold-boot System UI and native-lookup recovery remain documented limitations. [Current APK, screenshots and verification boundaries](JOURNEY_UI_INTEGRATION.md). No new test cases were added, and the backend/native integration suites were not rerun for this presentation increment.

## Main Community/Circle increment, 14 October 2026

Community now renders the authenticated backend's published events, with filtering, actual observation time, expiry, loading/errors and sign-in/profile gates. Circle renders actual memberships/invitations, with direct member-detail navigation and expiry-safe secret actions. Thirty-two existing focused checks pass; 12 account-model checks pass after the final expiry refinement. Analysis is clean. Both six-case Android phases pass using real restricted local PostgreSQL/PostGIS operations, retaining the same database/actors across a confirmed process stop. [APK hashes, screenshots and limits](COMMUNITY_CIRCLE_INTEGRATION.md). Hosted services, sharing/delivery, real safety routing and physical-device gates are still outstanding.

## Google Maps renderer increment, 13 October 2026

The official Google Maps Android renderer loads real Dhaka tiles with the locally configured user-supplied key. Traffic, synthetic foreground GPS centering/movement, corrected vertical pan, explicit location stop, page-cover cleanup and background/resume cleanup were reviewed in the emulator. Eleven existing UI checks pass, final analysis is clean, and the Android preview builds in 175.3 seconds. No new test cases were added. The key is absent from the new runtime source and stored in ignored local configuration. [Configuration, APK hash and evidence](GOOGLE_MAPS_INTEGRATION.md).

Geographic rendering is now real; destination search, routes, risk estimates, Circle sharing and escalation still have their previously documented integration gates. This increment does not claim that Google Maps tiles enable safety-weighted routing or emergency delivery.

## Journey-planning UI increment, 13 October 2026

The current UI uses the taste skill's audit and publisher screenshots from Uber and Google Maps. Explore, destination picking and route comparison are rebuilt in Flutter; Android launch resources reuse Awaaz's existing shield. Twenty existing UI/account checks passed, followed by all 11 existing general UI checks after the selected-destination refinement. Flutter analysis is clean (57.4 seconds); the final Android debug preview builds successfully (179.3 seconds). No new test cases were added. Backend/native-monitor suites below are earlier evidence and were not rerun for this UI increment.

Implementation scope, remaining order and installed-build evidence are documented in [UI implementation order](ui-redesign/IMPLEMENTATION_ORDER.md). Geography, route metrics and ordinary journey controls remain a labeled preview. Figma has not been synchronized in this increment.

## Current native monitor increment — 13 October 2026

**75 Flutter tests and four Kotlin JVM tests pass**, with clean Flutter analysis and fixture API type/format checks. Both patched Android process-restart phases pass all **six cases**. They verify native screen-off corridor alerts, unchanged baseline after acknowledgement, explicit synthetic replacement, the actual notification Stop action, a new UUID after stopping, and interrupted state without resuming after force-stop. The earlier storage/reporting checks still pass, including receipt recovery with no additional POST. A pinned Geolocator patch makes unused NMEA/GNSS telemetry opt-in while retaining the default fused provider and preventing the observed main-thread cleanup block. [Patch provenance](../third_party/geolocator_android/PATCH.md), [monitor contract](NATIVE_JOURNEY_MONITOR.md) and [device evidence](ANDROID_DEVELOPMENT_LOOP.md). Real street routing/maps, hosted Auth, physical-phone/Doze behavior, sharing, moderation and contact delivery remain release gates. Older counts below describe preceding slices.

The patched preview/test APKs build successfully (203.6/75.4 seconds). The preceding release web build succeeded in 96.6 seconds with a successful Wasm dry run; the later patch changes only Android Java behavior and explicitly preserves the existing false altitude setting. Nonfatal vendor Gradle/SDK warnings and the existing Cupertino font warning remain; the app uses Material controls in the inspected views. These checks do not validate physical-phone performance.

## Previous reporting increment — 13 October 2026

**64 Flutter tests**, **19 API cases** and **18 real database scenarios** pass; analysis/type/format checks are clean. Both Android phases passed all **four cases**, including native foreground location capture, explicit consent, private submission/withdrawal and receipt recovery after a confirmed process restart with no new POST. Screens were visually inspected. Tests use synthetic identities/coordinates, the production default location adapter and the real restricted local SQL service. Hosted Auth, human permission-dialog behavior, physical-phone performance, maps/background monitoring and emergency delivery remain gates. [Full contract](LOCATION_REPORT_COMPOSER.md) and [device evidence](ANDROID_DEVELOPMENT_LOOP.md). Older counts below describe preceding slices.

## Subsequent private storage and process-restart verification

Native drafts and account/backend-scoped pending writes now use encrypted storage. **56 distinct unit/widget cases pass** (full 55-case suite plus the final additional confirmation case), and static analysis is clean. The corrected two-phase Android run passed all three cases in each phase, including a real committed report with a deliberately lost acknowledgement, a confirmed force-stop/new process, recovery of the original UUID/time, and unchanged server report IDs after retry. Native file inspection found no plaintext report description/JSON in the journal value. [Storage contract](PRIVATE_STORAGE_AND_RETRIES.md) and [device reproduction/evidence](ANDROID_DEVELOPMENT_LOOP.md) describe retention, explicit user removal and the current 72-hour replay limitation. Earlier counts below describe preceding slices.

## Subsequent Android/backend integration — 13 October 2026

The Android toolchain has been restored and preview/test APKs build and run on the Android 36 emulator. The current Flutter suite passes **45 unit/widget tests** and static analysis is clean. **All three Android integration cases passed in the second run**, including isolated real SQL, native encrypted session storage, journey controls and Bangla/draft flows. Screenshot capture checks native window focus; six checkpoints passed and the Bangla/Circle/pending-report screens were visually inspected without overlays. Native keyboard opening/Back dismissal were manually observed. The emulator still showed a System UI ANR during boot, dismissed before the run; reliable cold boot and responsiveness remain unresolved. See [current Android evidence, limitations and reproduction](ANDROID_DEVELOPMENT_LOOP.md). The historical counts and toolchain limits below describe earlier slices.

## Subsequent backend increment

The accounts/Circles/community API now passes formatting and strict TypeScript checks, 19 HTTP/adapter cases and 17 integration scenarios against PostgreSQL 17.11/PostGIS 3.6.2. These exercise real migrations, RLS/column grants, a restricted API role, concurrency, quotas, invitation consent/revocation and report withdrawal. Supabase Auth transport is mocked in adapter tests; a fresh hosted project's Auth/pooler/Data API integration remains a gate. [Full backend evidence and reproduction](BACKEND_VERIFICATION.md). The first-slice records below describe the earlier baseline.

## Subsequent UI overhaul

The refreshed Flutter UI has now been audited against actual Uber, Life360 and Citymapper screenshots and substantially redesigned. The final complete Flutter run passes **22 tests**, static analysis reports **no issues**, and the release web build succeeds. New checks include map controls, destination shortcuts, Community filters, scroll reset, persistent demo status and the remaining Community/Circle/Report large-text layouts. Browser review covers phone and desktop, English/Bangla, journey/check-in/SOS, the report form and Circle. See [UI plan and all screen evidence](ui-redesign/PLAN.md) for current token contrast and previews. The original first-slice records below describe the earlier composition; Figma has not been synchronized to this subsequent redesign because the connector is unavailable.

## Confirmed checks at the original slice

- Flutter 3.47.7, Dart 3.13.5; framework revision `abaf9c523780a608bd46686fd5e53740a07077f8` from the official stable channel.
- `flutter analyze`: no issues.
- Flutter tests: 18 passing cases (17 in the complete run plus the subsequently added destination-filter case).
- A* matches an independent Dijkstra implementation across 90 seeded graph/weight combinations. Tests also cover access modes, closures, incoming-edge turn penalties, forbidden turns, unknown evidence penalties and invalid heuristic bounds.
- Deviation checks cover sustained reliable samples, stale/noisy fixes, gaps, isolated spikes, stationary samples, duplicate timestamps and the latched acknowledgement state.
- Journey tests preserve the original baseline until explicit detour acceptance, ignore stale route responses, confirm SOS previews without sending, and end the session.
- Report tests require consent, distinguish private drafts from publication, persist drafts through a new view model, delete local data and surface storage failure.
- English/Bangla views tested at 320 and 1024 logical pixels with 200% text scaling. A real header overflow was fixed; primary journey actions are now fixed above navigation. SOS is available from the journey header.
- Node 24.19.0; Fastify 5.12.5, Supabase JS 2.117.3, TypeScript 7.0.2. `pnpm check` and all five API tests pass.
- Original API tests covered verified sessions, ownership spoofing, categories/coordinates/time validation, pilot bounds, idempotent replay/conflicts and honest storage failures. At that checkpoint the service adapter was only type checked. The current restricted adapter and real database checks are documented above.
- `flutter build web --release` succeeds, including the SDK's Wasm dry run. The font scanner reports a Cupertino font-family warning; this app uses Material icons and both bundled text fonts render in the browser.
- Figma: eight editable 390 × 844 views, 12 prototype links, 17 shared component roots, 20 semantic variables, aliased primitives, shared text styles and no flattened-screen/image UI. Manrope and Noto Sans Bengali were explicitly checked. The final composition was visually reviewed after correcting Material colours and button widths.
- Browser review uses the release build at localhost:8765. It verifies phone layout, visible primary actions, route loading, journey start, deviation, header SOS confirmation/cancellation, explicit detour acceptance and journey end. `app-preview.jpg` records the final phone route view. The temporary viewport override was reset, and the preview tab remains open for review.

## Contrast checks

Calculated from the actual theme token values using WCAG relative luminance (normal-text AA threshold 4.5:1): ink/canvas 12.88, muted/surface 6.18, muted/tint 5.17, primary/white 6.45, warning/warning tint 6.34, danger/white 6.40. This is token evidence, not a full accessibility certification.

## Material limits

- At the original slice there was no Android APK/device run because the toolchain was outdated. This is superseded by the Android increment above. Release signing remains deliberately unconfigured.
- At the initial slice, PostGIS/RLS were unverified because Docker was unavailable. The subsequent increment verifies all three migrations in a portable local PostgreSQL/PostGIS cluster. Actual hosted Supabase Auth/Data API/pooler checks still precede real accounts or deployment.
- Flutter is still connected to demo repositories. Supabase Auth, public report upload, circles, live/ offline maps, GraphHopper, Kotlin foreground monitoring, push/SMS delivery, moderation and ML remain integration work.
- The planar fixture graph and simulated GPS exercise implementation logic; they do not demonstrate Dhaka street coverage, travel-time accuracy, real incident risk, background delivery, battery consumption or protection from harm.
- Local drafts use preferences only for the demo. Production-sensitive data needs encrypted storage, explicit retention and deletion controls.
- Figma's primary account reached the Starter MCP quota after the visual review. One empty construction wrapper remains. Sticky Flutter actions and header SOS added during browser QA are documented improvements; they are not yet synchronized back into Figma.

## Reproduce

Run `scripts/check.ps1` with the explicit Flutter path and `-BuildWeb`. It resolves the mobile dependencies, analyzes/tests/builds the refreshed app, and performs frozen-lockfile install/type/test checks for the API. See the root README and backend README for setup. No change has been pushed, no service deployed, and no old cloud project contacted by the refreshed app.
