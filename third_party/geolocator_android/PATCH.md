# Awaaz downstream patch

Upstream: Baseflow `geolocator_android` **5.1.1+1**, distributed through [pub.dev](https://pub.dev/packages/geolocator_android/versions/5.1.1+1). The upstream MIT license and package source are retained. Package examples and upstream tests are omitted from this runtime source copy.

Downloaded from `https://pub.dev/api/archives/geolocator_android-5.1.1%2B1.tar.gz` over verified TLS. Archive SHA-256: `1be90ea8aaaf9db8e7816b4fe0387f082ee8b5cf03355912dad90fb0a75717fa`, verified against the pre-existing hosted dependency lock. The original archive remains in ignored `.local` for comparison. No global Pub cache file was modified.

The first change is in `android/src/main/java/com/baseflow/geolocator/location/NmeaClient.java`. The original release registers NMEA and GNSS callbacks even when `useMSLAltitude` is false. An Android 36 emulator stall was traced to its main thread in `LocationManager.removeNmeaListener` / `unregisterGnssNmeaCallback` during `FusedLocationClient.stopPositionUpdates`. Native and Java thread dumps are retained in ignored local evidence.

The patch makes the supplementary GNSS subscription opt-in through the existing `useMSLAltitude` setting, skips stopping a listener that was never started and skips extra metadata enrichment when the listener is off. Awaaz keeps that setting false and uses no altitude, satellite counts or NMEA vertical-speed data. Fused location, precise permissions, timestamps, coordinates, horizontal accuracy and mock detection retain the existing provider path. This is the production adapter and the device-test adapter, not a test-only alternate GPS provider.

Optional satellite/NMEA metadata now remains absent/default until enabled. Do not enable the altitude mode without separate device testing: the underlying platform unregister behavior remains outside this patch. Replace this override only after comparing a suitable upstream fix and rerunning both Android phases. The public consumer release still requires physical-phone/OEM/Doze validation.

## Foreground-only consumer configuration, 15 October 2026

`GeolocatorPlugin.java` now reads the `geolocator_bind_foreground_service` boolean resource. Its library default is true, retaining the upstream service behavior. Awaaz overrides it to false in its application resources: Flutter requests foreground fixes only, and Awaaz's separate native `TripMonitorService` owns background GPS and notification/session stopping. No global Pub cache is changed.

The plugin tracks successful binding, skips unbinding when no binding exists, and ignores a stale connection callback after detach. `StreamHandlerImpl.java` requires the service only for requests with `foregroundNotificationConfig`. The foreground-only client path can start and cancel without a service. An attempted foreground-service stream with no service returns the existing explicit acquisition error rather than hanging silently or falling back to unnotified background GPS.

This removes an unnecessary eager service start from Awaaz's engine attachment. It does not establish that all startup ANRs are fixed. Rebuilt artifacts have been inspected: the merged flag is false; the focused Android foreground capture/cancel/reacquire and native monitor arm/stop cycle passes in 47 seconds; all five existing native tests pass. Runtime inspection confirms the plugin service stays absent while Awaaz's own native monitor can run independently. Artifact hashes, the separate remaining focus ANR and verification boundaries are recorded in [startup lifecycle](../../docs/STARTUP_LIFECYCLE.md).
