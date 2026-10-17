# Real geographic routing, 14 October 2026

The app now has a geographic routing path independent of its demo adapter. A pinned local GraphHopper 11.1 service imports public OpenStreetMap highway geometry and turn-restriction relations for Dhaka with a boundary buffer. Google Maps remains the Android renderer. The Android Maps credential is not used by the router.

The first real routing service returns one fastest route under its static OSM car/walking profile. Safety coverage is **unknown**, not zero risk. It does not use synthetic community reports, invent safety scores, train a model or claim that a route is safest. Road evidence association, scoring snapshots, risk weighting and reviewed alternatives remain unfinished.

## Data and engine

- Engine: GraphHopper 11.1, checked against Maven Central's published SHA-256 `8462f758d9ea49edaded557cec5c687a0a24f004ec371cd4daaeb0534824ea33`.
- Extract: one cached bulk Overpass request, 461,264 OSM nodes, 59,244 ways and 42 relations; source timestamp `2026-10-13T18:46:47Z`. Extract SHA-256 `80d5af1d40ad02d9949cc22b4c93ecb0fbd1d9651262b6f96407dd09e5ef92c8`.
- Imported graph: 100,648 graph nodes and 128,613 edges. Current graph version: `dhaka-gh11.1-80d5af1d40ad02d9949c-ee27cfede41c`. Cache directories are immutable by version, and old graphs are retained.
- Both profiles use zero distance influence and static speed costs. Car routing includes imported turn restrictions and a 60-second U-turn penalty; only `road_access=YES` is admitted. Walking admits missing/public/designated access and excludes other access categories and hiking ratings outside this profile. Awaaz does not assume that a user has delivery, customer, destination-only or private-road access. This does not establish that OSM contains every local access rule or restriction.
- CH/landmark preparation is disabled for this baseline. The gateway explicitly uses flexible `astarbi`; flexible `dijkstrabi` is used only by the local diagnostic oracle.
- Road extraction is bounded to `(23.60,90.15)–(24.05,90.63)`; complete ways/relation members can extend beyond it. Public route requests and every returned corridor point are restricted to the existing Dhaka pilot `(23.62,90.20)–(24.02,90.58)`. Geometry outside the pilot is rejected, not clipped.

The public Overpass service is used for one development extraction, never for app-user requests. Production refreshes need a sustainable versioned extract/import process. [Overpass policy](https://dev.overpass-api.de/overpass-doc/en/preface/commons.html), [GraphHopper source/release](https://github.com/graphhopper/graphhopper/releases/tag/11.1), [OSM license and attribution](https://www.openstreetmap.org/copyright).

## Runtime and configuration

Run `scripts/prepare-routing.ps1`, then `scripts/start-routing.ps1` and, after the engine starts, `scripts/confirm-routing.ps1`. Confirmation verifies that the owned process serves loopback 8989, records its import date and checks its profiles/version. Starting a process alone is not readiness. `scripts/stop-routing.ps1` checks the actual process command line before stopping that exact worker. Artifacts, logs, extract and manifest stay in ignored `.local/routing`.

GraphHopper binds application/admin ports 8989/8990 to loopback, with a 1 GiB heap and two processors. API integration requires `AWAAZ_GRAPHHOPPER_URL` and an absolute `AWAAZ_ROUTING_MANIFEST` path. Other API functions can remain available when the configured router stops. Remote router endpoints require HTTPS; redirects are rejected. Provider route/request logs are disabled to avoid recording precise journeys.

The existing disposable Android fixture gateway can enable this real graph through its ignored `.env.test`. Its account/report identities remain synthetic; routing uses the real OSM graph and always returns unknown safety. This entry point is never a production Auth provider.

The Android preview reads the non-secret routing endpoint from ignored `.local/routing.mobile.properties`, under `AWAAZ_ROUTING_API_URL`. This emulator uses `http://10.0.2.2:3031`. The normal build script passes the endpoint into Dart; deterministic `-Integration` builds disable both real routing and the Google Maps credential. Release parsing rejects plaintext transport. Without routing configuration the explicitly labelled demo adapter remains available; invalid or failed configured routing does not silently substitute it.

## API and mobile behavior

`POST /v1/routes` takes an explicit origin, destination and `car`/`walk` mode. It is an ephemeral public geographic calculation: no Auth session, report write or trip history is created. The gateway validates bounds, rejects near-identical endpoints, limits route requests per IP and caps concurrent searches at two. Requests have an eight-second provider deadline, bounded streamed JSON, disconnect cancellation and graph/import checks before and after the search. Route geometry, distance and endpoint snapping are checked. A start snap over 50 m or destination snap over 75 m is rejected. API logs keep route templates/status, never coordinates or request bodies.

Responses carry the immutable graph version, `unknown-v1` risk version, null evidence coverage, source timestamp, OSM attribution, `trafficAware=false`, a static-speed duration model and a five-minute start lease. A graph replacement, bad response or unavailable provider yields an error. Google traffic colors do not feed these estimates.

The real mobile mode removes demo destinations. Users long-press the map to select a road/entrance; coordinate entry is a fallback when geographic display is unavailable. The subsequent [named-place integration](NAMED_PLACE_SEARCH.md) adds imported OSM lookup with explicit pin review. Planning asks for one fresh precise origin fix and permission to send it with the destination to the Awaaz router. Cancelling, account changes, leaving planning or backgrounding discard pending fixes/results and abort HTTP. Route DTO validation checks intent, source, expiry, geometry, endpoint distance and unknown-coverage semantics.

The comparison/active route map uses the actual returned geographic polyline, with visible OSM attribution and license access. No schematic path or invented Farmgate origin is substituted. Estimates are explicitly static and safety coverage is unknown. Native arming still requires user approval, a fresh reliable fix and notification access; an expired plan cannot start or replace the monitored baseline. Debug emulator GPS can preview routes, while production background-monitor mock rejection remains intact.

## Verification and remaining work

All 22 API tests passed after the gateway was added. The later three focused routing cases and strict TypeScript/format checks pass. Six actual car/walking queries—including reverse directions—matched the Dijkstra oracle's cost on the imported graph. These are representative checks, not proof of all graph/profile behavior. The gateway returned a real 3,828.818 m car route with 47 points and an estimated 277 seconds, unknown coverage and the pinned graph version.

All 78 Flutter tests pass after the main integration, with clean analysis. A later focused run of 25 cases passes after loading/expiry refinements; final analysis is clean. Three small new client cases cover malformed/displaced/expired geometry, late-GPS cancellation and unavailable-backend behavior. The existing native command test now checks expired-plan rejection before GPS acquisition.

The first geographic APK built in 225.8 seconds. Installed Android 36 review confirms map-long-press selection, explicit origin consent, fresh emulated GPS, a backend-generated 3.1 km / 4 min car route, actual street geometry, unknown safety copy and static-ETA wording. The revised access profiles were reimported and all six representative Dijkstra comparisons still matched.

The same real street corridor armed the native foreground monitor. Eight emulated off-route GPS updates over 35 seconds produced private notification 7102 while `mWakefulness=Asleep`. Returning displayed the check-in; acknowledging cleared notification 7102 and restored active checks. End journey returned to Explore, and service inspection showed no TripMonitorService. This uses hardware GPS emulation, which is not proof of Android mock-provider rejection or physical-phone behavior. Previous explicit mock/Doze/OEM limitations still apply.

This boot also showed the existing emulator System UI ANR. Its observed Wait action recovered the app. Early frame captures can show stale overlays during transitions; current screenshots and hierarchy were checked before acting. The initial route presentation hid much of the map; it was replaced with one compact geographic route summary. Real-trip End/SOS controls now use a fixed footer, and the existing native widget case verifies that footer's stop failure/delayed response handling. Demo controls are hidden in real routing mode.

The final APK builds in 171.3 seconds. SHA-256: `1a6e89d618996d9cfeec150cfcc76ebb119e2a0f0c4d93b4b9ac04c0c1666a09`. Installed review confirms that English/Bangla comparison views show the complete path and estimates in the first viewport, and both active-trip languages keep End/SOS visible in the fixed footer. The final APK armed the real corridor and ended through that footer; service inspection confirms no active TripMonitorService afterward. The existing 11 monitor cases pass again with the fixed-footer route metadata enabled in their widget flow.

Evidence: [English route](ui-redesign/geographic-route-android.png), [Bangla route](ui-redesign/geographic-route-bangla-android.png), [fixed trip controls](ui-redesign/geographic-trip-android.png), [Bangla trip controls](ui-redesign/geographic-trip-bangla-android.png), [screen-off check-in](ui-redesign/geographic-screen-off-checkin-android.png), [check-in controls](ui-redesign/geographic-checkin-controls-android.png). These are installed emulator captures, not mockups.

The local gateway and graph are running for development; the emulator is left on English Explore with monitoring off. No production route, physical-phone/OEM behavior, hosted Auth, risk model, destination-search service or delivery service is claimed complete. Figma synchronization remains pending. Next work is road association/moderation/scoring, approved route replacement, place lookup, GPS-jump/map-matching quality and remaining production/device gates.
