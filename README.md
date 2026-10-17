# Awaaz

The refreshed mobile app now encrypts native private drafts and pending backend requests. Explicit retries preserve their original IDs/times across restarts and isolate accounts/backends. [Storage and retry contract](docs/PRIVATE_STORAGE_AND_RETRIES.md).

A Dhaka safety companion for adults in Bangladesh. The refreshed application is in **apps/mobile**. The original Flutter project at the repository root remains a historical prototype; its cloud configuration is not used by the new app.

## What works in the first slice

- SOS backend: separate recipient opt-in, atomic incident/notification jobs, explicit responses, immutable retries and withdrawal of unknown requests. Flutter now includes receiving preferences, named-audience confirmation, receipts, explicit responses, foreground location and resolution. The local Android consumer scenario passes, including lost-acknowledgment recovery and a Bangla terminal view. Push/SMS senders remain unfinished. [Contract and remaining work](docs/SOS_DELIVERY.md).

- English/Bangla UI, adaptive navigation and locally bundled fonts.
- Real Google Maps on Android Explore, with optional traffic and consented foreground location. [Local key setup and verified behavior](docs/GOOGLE_MAPS_INTEGRATION.md).
- Explicit monitored-route replacement: fresh origin consent, temporary comparison, expiring native acceptance and session/revision-bound confirmation. The real-graph emulator cycle includes a revision-2 screen-off alert, acknowledgement and verified stop. [Implementation and exact limits](docs/ROUTE_REPLACEMENT.md).
- Configured real OSM/GraphHopper car/walking routing, map-pinned destination and consented GPS origin. Unknown safety coverage, static estimates and explicit native arming. [Configuration and emulator evidence](docs/REAL_ROUTING_INTEGRATION.md).
- Destination selection, lower-reported-risk/fastest route comparison and a user-controlled journey.
- Risk-weighted A* on a clearly labelled fixture graph; sustained GPS-quality-gated deviation logic; explicit detour acceptance.
- Private help-request controls and a separate 999 system-dialer fallback. Push/SMS delivery is explicitly unavailable.
- Account-backed published Community reports, actual Circle memberships/invitations, private report history and local preview drafts. [Integration evidence](docs/COMMUNITY_CIRCLE_INTEGRATION.md).
- Private contact blocking, versioned decisions, invitation revocation and non-restoring unblock, with English/Bangla member/sender controls and a blocked-accounts list. [Contract and verification scope](docs/CONTACT_BLOCKS.md).
- Private trip sharing with explicit temporary grants, latest-point expiry, irreversible revocation and bounded retention. Flutter includes named recipients, foreground sharing and explicit background consent/pause/resume. The consumer Android cycle passes screen-off upload, recipient access, acknowledged notification Stop and account-change shutdown against local HTTP/SQL. [Sharing contract](docs/TRIP_SHARING.md), [native transport and exact evidence](docs/NATIVE_TRIP_SHARING.md).
- Normal, offline, route-error and empty-report demo scenarios.
- Typed Fastify API for profiles, consented Circles/invitations, private report history/withdrawal and a bounded published-event feed.
- Online Supabase session verification, phone-confirmed reporting, durable account quotas, idempotent writes and a restricted PostgreSQL role.
- Fresh PostGIS/RLS schema, verified against actual PostgreSQL/PostGIS separately from the old mock data.

**This is a development preview.** Configured geographic routing uses actual OSM streets with unknown safety assessment; the labelled demo adapter remains separate. Account services support profiles, consented Circles/invitations, foreground private reporting, receipt reconciliation and published-event retrieval. [Moderation](docs/REPORT_MODERATION.md) has a database-authorized private queue and audited decisions; separate [real-road association](docs/ROAD_ASSOCIATION.md) requires moderator selection and publishes sanitized evidence. [Evidence snapshots](docs/EVIDENCE_SNAPSHOTS.md) expire and invalidate on withdrawal. An implemented [refresh/retention worker](docs/EVIDENCE_WORKER.md) maintains snapshots and cleans private expired artifacts; production supervision is not configured. Experimental [reported-route choices](docs/REPORTED_ROUTE_INTEGRATION.md) now connect those snapshots to the routing engine and Flutter picker behind a default-off flag. The [on-device monitor](docs/NATIVE_JOURNEY_MONITOR.md) requires approved geometry and verified stopping. A real-corridor alert/stop loop has been reviewed with emulated GPS. [Named-place search](docs/NAMED_PLACE_SEARCH.md) now supports imported public OSM names with explicit pin review. Hosted Auth, independent scoring calibration, comprehensive address geocoding, sharing, emergency delivery, a moderation console/appeals and physical-device validation remain unfinished.

## Run

Use Flutter 3.47.7 / Dart 3.13.5 (the verified toolchain for this iteration):

```powershell
cd apps/mobile
flutter pub get
flutter run -d chrome
```

On this laptop Flutter is installed at `C:\Users\User\.codex\toolchains\flutter`; it is not added to the global PATH. Use its `bin\flutter.bat` directly if needed. The Android development toolchain now uses portable Microsoft OpenJDK 21, Android 36 and an accelerated Android 36 AVD. [Android development evidence and local fixtures](docs/ANDROID_DEVELOPMENT_LOOP.md) records build/device status. Release signing is intentionally unconfigured.

The review server serves the release web build at [localhost:8765](http://127.0.0.1:8765). To recreate it:

```powershell
cd apps/mobile
flutter build web --release
cd build/web
python -m http.server 8765 --bind 127.0.0.1
```

## Verify

```powershell
./scripts/check.ps1 -Flutter C:/Users/User/.codex/toolchains/flutter/bin/flutter.bat -BuildWeb
```

Node 24+ and pnpm are required for API checks. Use `./scripts/check.ps1 -BackendOnly` for API checks alone, or start the local test cluster and add `-DatabaseTests`. [Backend setup and remaining integration gates](backend/README.md) explains the fresh Supabase configuration and restricted database role.

## Design and plan

- [Figma](https://www.figma.com/design/8C7LHBjpEzvRXol0XuPd1R?node-id=9-119) — original eight-view prototype in the primary account. The subsequent Flutter UI overhaul is not yet synchronized: the Figma connector was unavailable during that work.
- [UI overhaul, screenshot references and implementation plan](docs/ui-redesign/PLAN.md)
- [Development plan](docs/DEVELOPMENT_PLAN.md)
- [Research and complete update plan](docs/AWAAZ_UPDATE_PLAN_2026.md)
- [Road safety, A*, background monitoring and ML design](docs/AWAAZ_ROAD_SAFETY_DESIGN.md)
- [Implementation backlog](docs/AWAAZ_IMPLEMENTATION_BACKLOG.md)
- [Installed skills and pinned provenance](docs/SKILL_SOURCES.md)
- [Verification evidence](docs/VERIFICATION.md)
- [Backend implementation and database evidence](docs/BACKEND_VERIFICATION.md)

There is no migration dependency on the old mock users. The account/Circle/community backend is implemented and locally database-tested. Production work next requires hosted Auth/API wiring, moderation and sharing/SOS workflows, maps/routing, real-phone monitor validation, durable delivery and operations, then a Dhaka closed pilot. ML follows reliable labels and independent evaluation.
