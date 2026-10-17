# On-device Android journey monitor

Implementation increment: 13 October 2026. Device verification is recorded in `ANDROID_DEVELOPMENT_LOOP.md`; the presence of this implementation does not mean public street routing is ready.

## What can arm it

The user must explicitly start a journey while Awaaz is visible. Flutter first requests notification access and a fresh precise foreground location, then passes an approved corridor containing immutable latitude/longitude geometry, a graph version, risk version, route ID, session UUID and revision. The Kotlin bridge independently checks the owner, visible activity, precise permission, notification channels, bounded geometry and approval flag. A start retry retains its UUID only for the identical complete corridor intent. A conflicting request cannot replace or stop an active trip.

The initial native status lookup runs after the first Flutter frame, and resume polling waits for initialization. Account changes still clear private state and bind immediately. A terminal native event or refresh also discards the previous start nonce: notification Stop, expiry or permission loss must not reuse the previous UUID for a later trip.

Current demo routes contain **no geographic corridor**, so they cannot arm this service. Synthetic geometry is accepted only by an explicitly injected test view model and a debug native build. There is no fixture login, GPS trace injection or mock acceptance switch in the production entry point. A real graph-backed route adapter must supply audited geometry before this becomes a consumer flow.

## Native execution and reliability

`TripMonitorService` is a non-exported location foreground service, started using AndroidX while the activity is visible. Its ongoing notification provides a stop action. It uses Google Play Services fused location at a requested five-second interval, with a GPS provider fallback if fused services fail or no trusted fix arrives. Android can schedule updates differently from the requested interval. Flutter frames and timers do not drive the native engine. This design follows the [Android location foreground-service requirements](https://developer.android.com/develop/background-work/services/fgs/service-types#location) and [LocationRequest scheduling contract](https://developers.google.com/android/reference/com/google/android/gms/location/LocationRequest.Builder).

The monitor first requires a reliable fix on the approved corridor. A later departure needs accuracy greater than zero and at most 35 m, fix age at most eight seconds, valid speed, movement of at least 0.8 m/s, and distance from the corridor minus reported uncertainty greater than 80 m. At least three outside samples must persist for 20 seconds, with no gap exceeding 12 seconds. Duplicate or out-of-order fixes cannot extend a candidate. Unreliable or stationary samples reset the candidate. These are conservative starting thresholds, not validated Dhaka safety metrics.

The resulting notification asks whether the detour was expected. It does not identify driver intent or claim that a crime occurred. A check-in remains latched until an explicit acknowledgement. “Keep watching the original route” clears the current alert and applies a two-minute cooldown without changing geometry or revision. Only an explicit replacement command with the same session/owner and the next revision can change the baseline. The current demo detour controls are disabled for geographic corridors; public rerouting remains unfinished.

This is distance-to-polyline monitoring, not road-level map matching. Parallel roads, junctions, building GPS multipath, legitimate turns and vehicle types need real traces and false-alert evaluation. Low-speed walking departures do not satisfy the current movement gate. Provider or notification access loss, expiry and process interruption must remain visibly distinguishable from successful monitoring.

## Privacy, stopping and interruption

The approved corridor is stored in an app-private AtomicFile encrypted with an Android Keystore AES-GCM key. No raw live location history is persisted or passed to Flutter. Stop removes the geometry and leaves only minimal terminal state; account changes stop the previous owner’s service and clear private route state. Android backup remains disabled.

There is no network upload, Circle sharing, contact delivery or escalation in this service. Status and alert notification text avoid destination names and coordinates and use private lock-screen visibility. The default trip expires after two hours; the bridge caps accepted duration at four hours. Native heartbeat checks are best effort, not a wall-clock guarantee during device suspension.

The service is `START_NOT_STICKY`, has no boot receiver and does not restart itself after force-stop or reboot. A cold read of an encrypted active record becomes an interrupted terminal record, discards its corridor and asks the user to start again. Android's task manager, battery restrictions and OEM process killing can still interrupt it. Emulator screen-off tests cannot establish physical-phone or Doze reliability; those remain release gates.

## Verification structure

Pure Kotlin tests cover corridor distance/bounds, uncertainty, baseline arming, persistence, gaps, duplicates, stationary samples, latching and cooldown. Flutter tests cover permission denial, owner changes during asynchronous prompts/location acquisition, complete-intent retry IDs, explicit baseline revisions, stale owner events and a narrow Bangla check-in panel with enlarged text.

The separate Android integration entry uses the production method/event bridge, default location adapter, native service and notifications. A fixture-only API restricts SDK operations to the exact disposable Awaaz AVD, injects emulator GPS with a velocity expressed in knots, verifies the native foreground service, backgrounds the app and confirms the screen is asleep before a sustained departure trace. It checks the actual notification record before reopening Awaaz. The two-phase driver retains installation/private storage and deliberately force-stops the app between phases. Synthetic tests exercise mechanics; they do not establish real road accuracy, delivery, emergency response or account verification.
