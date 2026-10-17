# Awaaz development plan — 12 October 2026

## Decisions

- SOS incident/inbox/outbox commands now implement separate recipient consent, frozen retries, cancellation before delayed activation, explicit responses, expiring location access and membership/block revocation. The whole backend passes 27 API checks and 38 database nodes; the final acknowledgment-suppression refinement passes the five SOS nodes. Actual push/SMS senders, mobile SOS controls and the other launch requirements remain unfinished. [Contract and complete SOS work list](SOS_DELIVERY.md).

- Temporary trip sharing now has a private latest-point backend and explicit recipient grants. Membership epochs and block/closure triggers prevent old access from reviving; stop, point expiry and bounded cleanup are implemented. Migration 10 adds a single scoped native publisher; all 27 API checks and 33 real database nodes pass. Public background consent, foreground/native handoff, pause/resume, screen-off upload and notification Stop pass the 108-second consumer Android cycle. [Sharing contract](TRIP_SHARING.md), [native integration record](NATIVE_TRIP_SHARING.md).

- Explicit monitored-route replacement now has a temporary comparison, fresh origin consent, native acceptance-time lease checks and session/revision-bound reconciliation. The real-graph emulator flow verifies expired-plan refusal, accepted revision 2 in the same session, a display-off check-in, baseline-preserving acknowledgement and verified stop. Feedback/alert-visibility refinements pass focused checks; the final APK is installed and its actual startup-status Retry is reviewed. Startup remains unresolved. [Contract and exact verification scope](ROUTE_REPLACEMENT.md).

- Named destination lookup now uses a checksum-verified 36,563-record public OSM catalogue, bounded anonymous search API, bilingual picker and explicit map-point confirmation. Actual keyboard/search/pin/route and background/retry flows are reviewed on the emulator. Search is partial imported data, not comprehensive address geocoding or verified entrances. [Named-place implementation](NAMED_PLACE_SEARCH.md).

- Evidence refresh now has a restricted standalone worker, serialized leadership, failure backoff, private live/ready health checks and bounded artifact retention. A real-graph disposable-database diagnostic verifies role isolation, standby/recovery and graceful owned IPC shutdown. The Android fixture uses the same component; hosted deployment and operational monitoring remain gates. [Worker contract](EVIDENCE_WORKER.md).

- Startup renders before account/session work and owns its created services. A later named-search build reproduced the cold-start ANR. Matching-engine symbolization now identifies debug JIT compilation in the sampled stack, without proving the cause. Native status lookup failures have explicit unknown status and owner-binding recovery instead of claiming monitoring is off. [Startup evidence](STARTUP_LIFECYCLE.md).

- The GraphHopper evidence-weighting worker and live-epoch coordinator now execute on the real graph. Six A* costs match Dijkstra, a synthetic corridor changes a route, and virtual snap fragments inherit their original edge penalty. Experimental API/mobile wiring now exposes fastest and reported-evidence choices with explicit unknown safety assessment. [Integration and release boundaries](REPORTED_ROUTE_INTEGRATION.md).

- Reviewed evidence now has sparse, graph/epoch-bound two-minute snapshots, conservative grouping/contributor caps and explicit unknown defaults. Withdrawal revokes API/RLS reads. Public coordinate precision is enforced in SQL. These uncalibrated indices feed the experimental route comparison; they do not establish safety. [Snapshot contract](EVIDENCE_SNAPSHOTS.md).

- Real-road publication uses a checksum-verified registry of 125,679 usable Dhaka edges, explicit moderator association and fixed-vocabulary summaries. Withdrawal removes the event and invalidates its graph evidence epoch. Experimental snapshots and reported-evidence routing are implemented locally; safety remains unknown. [Road association](ROAD_ASSOCIATION.md).

- On 14 October, the backend gained administrator-provisioned moderation, a private pending queue and audited approval/rejection decisions. Approval remains private until association with the real graph. Verified account status does not verify an allegation. [Implementation and operator workflow](REPORT_MODERATION.md).

- On 13 October, the user supplied a Google Maps key for real map integration. Explore now uses the official Google Maps Android SDK when configured, with consented foreground location and optional traffic. The remaining real routing/risk backend is independent from this renderer. See [configuration and limits](GOOGLE_MAPS_INTEGRATION.md); web and fixture builds retain the schematic adapter.

- Public consumer app for adults in Bangladesh; Dhaka is the first pilot.
- Retain Flutter. Mock user data needs no migration.
- Fresh production target: Supabase Auth/Postgres/PostGIS, Fastify API, durable notification outbox, MapLibre, GraphHopper routing, Kotlin trip monitor, FCM plus explicit contact escalation. See `AWAAZ_ROAD_SAFETY_DESIGN.md` for the full design and rollout gates.
- This iteration implements a reviewable first vertical slice. It is a demo, not a functioning emergency service. No live location, contact delivery, or safety guarantees will be implied.

## First iteration, in order

1. Install reviewed, pinned skills; record provenance.
2. Create Figma foundations and reusable controls, then eight editable phone views: Explore, route comparison, active journey, deviation check-in, Community, report composer, Circle, SOS confirmation.
3. Preserve the original prototype at the repository root as a historical reference. The refreshed executable is `apps/mobile`, with immutable domain models, a repository interface/demo adapter, a journey view model and reusable Material 3 views. New services live under `apps/api`; do not run the old root Flutter package for v2.
4. Build the journey loop and locally persisted report drafts. Demonstrate route choices and an acknowledged deviation without inventing real map coverage or notifying contacts.
5. Implement and test an independent risk-weighted A* reference and deviation state machine with GPS quality and persistence gates. These fixtures validate logic only; production street graphs and a Kotlin foreground service remain separate work.
6. Add a fresh PostGIS/RLS schema and a typed Fastify reporting API with Supabase Auth and idempotent persistence. No cloud deployment in this iteration.
7. Verify formatting, static analysis, domain and interaction tests, responsive/large-text layouts, a release web build and Android build if the SDK is usable. Capture the resulting app for review.

## UX acceptance

- Visible demo label on every app view; schematic map labelled as such.
- Route copy says “lower reported risk”, never promises “safe”. Coverage uncertainty remains visible.
- No-report areas are unknown. Verified accounts are distinct from reviewed reports.
- Reports describe observable behaviour/events, never publicly identify people.
- User controls trip start/end and any change to the monitored baseline.
- Explicit named-recipient confirmation before saving a help request; inbox, provider and human-response status remain distinct.
- Minimum 48 dp controls; scrollable content under text enlargement; English/Bangla selector.
- Loading, empty, error and offline demo states are reviewable.

## Production gates after this slice

Physical-phone/Doze/OEM foreground-service validation; hosted Auth integration; moderation and appeals; licensed maps/geocoding; route graph audits; durable notification receipts; abuse/privacy review; incident response and restore drills; Dhaka closed pilot. ML training begins only after reliable labels and independent evaluation exist.

## Progress

- [x] Geographic routing increment on 14 October: pinned GraphHopper/OSM import, versioned bounded API, current-origin consent, map-pinned destinations and actual returned geometry. English/Bangla Android review and a real-corridor native screen-off check-in/stop loop verified. Safety remains unknown; road association, scoring, route replacement, named-place lookup and production gates remain unfinished. [Evidence and configuration](REAL_ROUTING_INTEGRATION.md).

- [x] Active-journey composition verified on 14 October: compact planned-route summary, one native status, arming consent, baseline-preserving check-in and verified stop handling. English/Bangla emulator review, 22 existing focused checks and a clean Android build. [Evidence and cold-boot limits](JOURNEY_UI_INTEGRATION.md). Real routing and production-service integration remain outstanding.

- [x] Main Community/Circle integration verified on 14 October: SQL-backed published-event feed, private report-history entry, actual memberships/invitations, direct detail/back navigation and expiry-aware invitation actions. Existing focused checks and both six-case Android restart phases pass; see [scope, evidence and remaining gates](COMMUNITY_CIRCLE_INTEGRATION.md).

- UI implementation priority updated on 13 October: complete Explore/destination/route choice first, then Community/reporting, Circle, active trips, real geography, and hosted production services. Use existing focused checks and emulator review, without expanding test scaffolding for cosmetic changes. See [implementation order](ui-redesign/IMPLEMENTATION_ORDER.md).

- [x] Subsequent Android integration: encrypted sessions/drafts/requests, profiles/Circles, foreground location-backed private reporting, old-request receipt reconciliation and a native on-device corridor monitor. Current mobile checks: 75 Flutter cases, four Kotlin cases, and all six Android cases in both patched process-restart phases. Screen-off alerts, explicit baseline replacement, the actual notification Stop action, fresh trip UUIDs and non-resumption after force-stop are verified with synthetic geometry. [Monitor contract](NATIVE_JOURNEY_MONITOR.md), [GPS patch](../third_party/geolocator_android/PATCH.md) and [device evidence](ANDROID_DEVELOPMENT_LOOP.md). Hosted Auth, real street routing/maps, sharing, moderation, delivery and physical-phone validation remain unfinished.

- [x] Seven skills installed at pinned commits.
- [x] Figma file created and Material 3 library/font discovery completed.
- [x] Figma views and component review (eight views, 12 links, editable components and tokens).
- [x] Flutter slice and domain implementation (English/Bangla, actual A* on a fixture graph, local drafts).
- [x] Backend API/schema foundation, followed by account/Circle/community operations, restricted SQL access, durable quotas and native PostgreSQL/PostGIS integration tests.
- [x] Initial verification and review evidence: Flutter analysis, 18 cases, five API cases, release web build, responsive/text-scale checks and browser QA. Subsequent UI/backend evidence is recorded below. Actual Android and hosted Supabase checks remain integration gates.
- [x] Subsequent UI overhaul: established-app screenshot references, richer interactive map, compact planner, clearer routes/journey controls, Community filters, Circle/report styling, persistent status and navigation scroll reset. Final Flutter analysis is clean, all 22 cases pass, and the release web build succeeds. [UI plan and screen evidence](ui-redesign/PLAN.md). Figma synchronization is pending connector availability.
- [x] Backend-first increment: 19 HTTP/adapter cases and 17 real database scenarios pass, with strict TypeScript/formatting checks and generated OpenAPI. [Backend evidence](BACKEND_VERIFICATION.md). Fresh hosted Auth integration, Flutter wiring and the remaining release gates are pending.

## Contact blocking, 15 October 2026

The backend now has private versioned block decisions, pair-serialized Circle access changes, revoked conflicting invitations, bounded outgoing lists and non-restoring unblock. Flutter includes member/sender controls, an account list, explicit confirmation and account-lifetime isolation. Lost acknowledgements reconcile through reads; unchanged reads leave an explicit check/retry notice, and no mutation is resent automatically. All 25 API checks, 24 real database nodes and 34 focused Flutter account checks pass; analysis is clean. The actual Android cycle passes against local HTTP/PostgreSQL and the Maps preview is restored. [The blocking record](CONTACT_BLOCKS.md) records artifact hashes, screenshots and the pre-test System UI ANR. Hosted Auth, production operations, location sharing/delivery, Figma synchronization and the other release gates remain open.

Figma: https://www.figma.com/design/8C7LHBjpEzvRXol0XuPd1R

## Foreground sharing, 16 October 2026

Flutter now connects to the authenticated sharing backend: named Circle recipients, fixed duration, explicit foreground location consent, pause/resume, irreversible stop/revoke, incoming pagination and recipient decline. An expired or unavailable recipient fix is removed from the map; account changes clear private state and invalidate late completions. Lost start acknowledgements retain the identical consent request. English and Bangla copy explicitly limits updates to the open screen. The native route monitor still operates independently.

The foreground client passes its real Android/HTTP cycle (60 seconds), including lost acknowledgements, explicit pause, recipient access removal and Bangla stop. The native transport diagnostic passes in 91 seconds; public background consent/handoff/pause/resume and the full screen-off/notification-stop/account-change cycle pass in 108 seconds. Next implementation order: (1) implement the remaining SOS delivery/outbox and moderation/account-deletion flows; (2) collect process/reboot stop-delivery, permanent-refusal recovery and Bangla native-notification evidence; (3) connect fresh hosted Auth and production operations; (4) complete physical-device background/release checks and synchronize updated screens to Figma. Hosted credentials, physical-device evidence and the unresolved emulator startup ANR remain explicit release gates. [Sharing contract](TRIP_SHARING.md), [native integration and exact evidence](NATIVE_TRIP_SHARING.md).

## SOS consumer increment, 17 October 2026

Implemented recipient opt-in, named-audience review, a private encrypted frozen activation/withdrawal journal, read-only lost-acknowledgment recovery, explicit response and irreversible owner resolution, leased foreground position and a 999 system-dialer fallback. The real Android consumer scenario passes in 146 seconds; no provider delivery or real emergency call was tested. Screenshot review prompted automatic reveal of opened/responded request details. Next delivery work is the restricted push-device/worker/provider boundary, followed by separately consented escalation and moderation/account lifecycle work. Native background SOS, hosted credentials, physical-device/release checks and Figma synchronization remain open. Cold-start/ANR and severe host memory pressure remain performance gates. [Scope and evidence](SOS_DELIVERY.md).
