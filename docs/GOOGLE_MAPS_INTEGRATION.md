# Google Maps Android integration, 13 October 2026

Explore uses the official Flutter Google Maps plugin, pinned to `2.18.2`, when the Android build has a configured SDK key. Android native configuration supplies the credential. The build script derives a non-secret `AWAAZ_GOOGLE_MAPS` Dart flag from that configuration; the native capability channel is a fallback for manual builds and returns only a boolean. Hosts without a configured Android key, web previews and local integration fixtures retain the labeled schematic map. The flag avoids depending on native channel availability during a resource-constrained cold start. The first installed build stayed on the fallback despite the native flag being true; the supported build script now selects the renderer deterministically.

## Local configuration

The supplied key is saved in ignored `.local/maps.android.properties`, under `GOOGLE_MAPS_ANDROID_API_KEY`. Gradle reads that file or the `AWAAZ_GOOGLE_MAPS_ANDROID_API_KEY` environment variable. No credential belongs in Dart, committed Android manifests, screenshots, documentation or sample configuration. Run `scripts/build-android.ps1 -UseMirrors -StopBuildDaemon`, then install `.local/awaaz-android-preview.apk` on the owned emulator.

SDK credentials can be extracted from an APK; keeping the configuration out of Git does not replace provider restrictions. Restrict this Android key to **Maps SDK for Android**, package **`app.awaaz.awaaz`**, and this machine's debug signing SHA-1:

`08:72:56:73:75:56:D4:B9:42:9C:72:09:91:C0:00:99:B3:73:AF:2D`

Production release signing will require its own certificate fingerprint. The Google Cloud project must have billing and Maps SDK for Android enabled. These settings are not changed by local code. [Google setup](https://developers.google.com/maps/flutter-package/config), [key restrictions](https://developers.google.com/maps/api-security-best-practices).

## Behavior and privacy

- Real geographic pan/zoom, Dhaka reset, Google attribution, and an optional traffic layer.
- Location is enabled only through a visible control and consent dialog. A fresh foreground fix and permission check precede the SDK's location layer. Map browsing accepts approximate fixes and uses a wider camera view for them; reporting/monitoring precision rules are unchanged. Report and trip location requests have separate ownership; this map cannot cancel them.
- Full-page navigation over the map and application backgrounding cancel its pending acquisition and disable its location layer. Account changes recreate the map without the previous location layer or camera state. Returning does not silently restart it; its active control can also turn location off explicitly. No trip monitor, Circle sharing or escalation is armed by viewing this map.
- Debug emulator mock fixes are accepted for map display only. Existing report/monitor acceptance rules remain separate. No location persistence or upload to Awaaz is added by this map integration; Google processes SDK map/location traffic as explained in the product's consent dialog.
- The live Explore map contains no fictional polylines, report pins or heatmaps. Geographic builds now obtain real route geometry from the separate Dhaka routing backend; fixture builds retain their labeled demo graph. See [real routing](REAL_ROUTING_INTEGRATION.md) and [route replacement](ROUTE_REPLACEMENT.md) for the later implementation and verification scope.

The SDK integration does not supply traffic-aware route estimates, destination geocoding, risk scoring or safety-weighted navigation by itself. Those require a real routing/data contract and separately enabled services. An Android-restricted SDK key must not be reused as an unrestricted server credential for Routes or Places. [Official plugin](https://pub.dev/packages/google_maps_flutter).

`-Integration` builds explicitly disable Google Maps and omit its key, preserving deterministic, isolated fixtures. The local key file remains ignored.

## Verification

The supplied key is absent from application source, scripts and documentation; its local file and generated manifests are ignored. The resolved Android adapter is `google_maps_flutter_android 2.21.0`, using Maps SDK `20.0.0`. Eleven existing UI cases pass, without adding test cases. Final static analysis is clean (60 seconds). The final native Maps build succeeds in 175.3 seconds; APK signature verification confirms the debug SHA-1 above. Preview APK SHA-256: `cb6a2e5c6b76979100ef1df182fe63d8603931e9b0a9c3214200c3e1cbc4d8c9`.

Installed emulator review confirms real Dhaka tiles, colored provider traffic, consented location centering and a location dot that moves as synthetic GPS updates. No SDK authorization failure was observed. The initial vertical drag moved the outer scroller rather than the map; the corrected APK pans the map while keeping the planner fixed. Explicit location stop, covering the map with the account page, and backgrounding/resuming each return the control to its off state; the location dot disappears. The emulator is left on Explore with location off and no native trip service active.

The owned emulator produced a System UI ANR dialog during a cold boot. It was recovered with its Wait action before the final gesture checks. An early UIAutomator dump also returned a null root during a transition; a fresh capture was used instead of its stale XML. These do not establish physical-phone or OEM performance. No hosted Auth, routing, emergency-delivery, full backend or native-monitor integration suites were run for this renderer increment.

Evidence: [live map](ui-redesign/google-maps-android.png), [location with synthetic GPS](ui-redesign/google-maps-location-android.png), [corrected vertical pan](ui-redesign/google-maps-pan-android.png). Native map construction alone was not treated as proof of successful tile loading. Approximate-fix acceptance is implemented but has not been validated on a physical device.

The 14 October journey UI build also loads real Dhaka tiles and provider traffic lines with this local configuration. [Current map](ui-redesign/google-maps-current-android.png), [latest APK and UI verification](JOURNEY_UI_INTEGRATION.md). The location/gesture checks above describe the earlier renderer run; cloud credential restrictions have not been inspected or changed.

## Configuration recheck, 15 October 2026

The ignored Android configuration matches the user-supplied key. A scan of tracked and non-ignored source files found no copies of that key. Generated Android manifests contain it as expected for the native SDK. The installed emulator APK matches `.local/awaaz-android-preview.apk`, SHA-256 `8652b6eaface3f96d6a43e84298bce6dbe84e0eb9a3416af3b1575c1d7476238`.

A fresh emulator screenshot confirms real Dhaka tiles on Explore: [verified map](ui-redesign/google-maps-verified-2026-10-15.png). No trip-monitor service was active during this check. This recheck did not repeat the earlier traffic, consent or background-location scenarios, and did not inspect Google Cloud restrictions or billing. The Android SDK credential remains separate from server routing and geocoding credentials.

The later contact-block increment restored a newer Maps-enabled preview, SHA-256 `81c8b4ab22d82935e1324bae70ca0b7a58a58e5244b4f9e557960c7df3954011`. Its installed hash and native key configuration match, and real Dhaka tiles were reviewed again. [Current preview](ui-redesign/contact-block-final-preview.png), [build and verification record](CONTACT_BLOCKS.md).
