# Foreground location reporting — 13 October 2026

## Current implementation

Configured users with an adult profile and phone-confirmed account can open the report composer from My reports or the Community report action. Unconfigured previews retain their explicitly local draft flow. Location acquisition begins only after “Use my current location.” The user chooses a category, describes an observed condition and separately consents to submitting that text/location for private review. The client never publishes it directly.

The composer requires a precise fix with known estimated accuracy at most 50 metres, captured within two minutes (up to five seconds of clock skew), inside the existing Dhaka pilot bounds. Stale, approximate, missing-accuracy, uncertain, outside-pilot and mocked fixes block live submission. Mock acceptance is enabled only in the synthetic Android test factory. A mock flag is not server-side location attestation; verified-account input remains untrusted and needs moderation.

Geolocator 14.1.1 uses the production platform adapter. A one-shot stream is cancelled after its first result or a 20-second timeout. The UI/view model cancel acquisition and clear fix/consent when the route closes, the app is hidden/paused or its account changes. Permission dialogs may make a still-visible activity inactive, so that state alone does not cancel the permission request. Account changes also clear private form text. Returning to the app does not silently reacquire a location or restore submission consent.

Only foreground coarse/fine permissions are requested by this increment. It does not implement a background journey monitor. Android can grant approximate access even when precise access is requested; the UI explains the limitation and offers app settings through an explicit action. Permission denial leaves the rest of the app usable. Defaults follow [Android permission guidance](https://developer.android.com/develop/sensors-and-location/location/permissions/runtime) and [Geolocator's package documentation](https://pub.dev/packages/geolocator).

## Receipt reconciliation

`GET /v1/report-requests/:clientRequestId` returns the authenticated account's existing receipt without report text/location or a write. It remains usable when the original observation is too old to POST. A withdrawn receipt comes from the retained retry tombstone and cannot restore deleted data. Unknown and foreign requests return the same 404. Public/client database roles cannot execute the dispatcher or read the ledger; the old dispatcher is not executable by the restricted API role. Readiness checks require the fourth migration and its permission boundary.

An explicit saved-report retry checks this endpoint first. An existing receipt resolves the local request without another POST. If no receipt exists and the original observation is still allowed, it sends the original request UUID/time. Older unknown requests remain saved with an explanation; no fresh UUID or observation time is substituted.

## Verification status

Both corrected Android phases passed all four cases, including this composer through the production default adapter with synthetic Dhaka fixes and real local SQL. Screenshots show consent unchecked/submit disabled before writing and a private pending receipt afterward. Receipt recovery after a confirmed process restart did not send another report POST. The fixture explicitly handled Google Location Accuracy's opt-in; human runtime permission dialogs and physical-phone behavior remain unverified.

The complete Flutter suite passes **64 tests** and static analysis is clean. Checks cover receipt outcome/withdrawal, old unknown requests, failed lookups, GPS quality, explicit capture/consent, edits, background/account changes, late fixes, ambiguous submission and English/Bangla narrow layouts at 200% text. The API passes 19 existing HTTP/adapter tests and 18 real database scenarios (19 nodes including their parent). The new scenario verifies old receipts, withdrawals, actor isolation, no private payload leakage and denied execution of the legacy dispatcher.

The Android fixture route can enable location permissions/services and inject a predetermined Dhaka GPS fix only in the exact isolated Awaaz AVD. The device test uses the **production default location source**, tests consent before a real local SQL submission, checks pending/private status and withdraws the synthetic report afterward. This route is test-only and is absent from production. Native execution results are recorded in the development loop after the APK run. Programmatic fixture permission grants do not constitute verification of a human permission-dialog flow or a physical phone's GPS accuracy/battery behavior.
