# Android emulator development loop — 12–13 October 2026

## Objective and order

Run the refreshed app on an actual Android emulator and repeat implement/test/fix cycles. Keep the existing domain/UI separation and current design. Existing cloud mock credentials are not reused.

1. Restore the Android build toolchain: verified current command-line tools, patched JDK, Android 36 platform/build tools, Flutter-pinned NDK, compatible Google APIs image and a hardware-accelerated emulator. Reduce the generated Gradle memory budget for this laptop.
2. Build/install/run the current application. Exercise navigation, the software keyboard, English/Bangla, the journey/SOS preview and draft persistence. Capture device screenshots/logs. Fix Android-specific failures before adding broader features.
3. Implement typed HTTP contracts and Supabase Auth/session storage, profile setup and consented Circle operations in the mobile data/repository/view-model layers. Configuration is explicit; incomplete configuration does not invent a live backend. Add meaningful authorization/retry/session-change tests.
4. Integrate private report history/submission/withdrawal and published-event data. Use explicit coordinates/observation times and consent; pending submissions never become public by client action. Preserve request IDs across ambiguous retries.
5. Run service/view-model/widget tests plus Android integration tests on the emulator. Rebuild/reinstall and repeat when failures or new changes justify it.
6. Continue with native monitoring, revocable journey sharing, moderation and SOS/outbox features under their documented contracts. Real maps/provider/OTP/cloud configuration and representative physical-device behavior remain separate evidence requirements.

## Test boundaries

The emulator demonstrates an Android OS execution environment; it does not certify OEM force-stop behavior, battery consumption on phones, Dhaka map coverage or emergency delivery. Production Auth uses Supabase; tests may inject synthetic repositories/identities only in test code. No development authentication bypass is added to the production API.

A fresh cloud project's configuration is required for actual SMS OTP and hosted Auth/pooler tests. Local Postgres integration remains reproducible. Do not send emergency drills to official numbers or real contacts.

## Skills applied

Flutter architecture, Dart static analysis and Flutter widget testing. Follow view models/repositories and injected services rather than UI-owned network calls.

## Evidence to update after each cycle

Toolchain/AVD/device IDs and commands; build/test results; discovered defects and fixes; screenshot/log paths; external configuration limits; the next implementation slice. All release claims must match measured behavior.

## Current implementation and checks

The user selected local fixture testing. The test-only entry point `apps/api/test/android-fixtures.ts` starts a disposable database through the integration harness and binds only `127.0.0.1:3031`. Three synthetic accounts and a synthetic reviewed road event are provided to the Android test entry point. Neither production `src/index.ts` nor mobile `lib/main.dart` exposes synthetic login. Restart this fixture server before a new device run because tests mutate its data.

The mobile app now includes a typed API repository, explicit backend configuration, Supabase phone OTP adapter, encrypted native session storage, profile/adult attestation, consented Circle/invitation management, private report history/withdrawal and expiring published-event retrieval. There are no automatic report-publication privileges. Unconfigured startup keeps the preview usable. Configure a fresh cloud project through an ignored `config/backend.local.json` copied from the example and `--dart-define-from-file`; only a publishable key belongs in the app. Web sessions are memory-only.

Verified locally: Flutter analysis clean; **45 unit/widget tests pass** in the complete suite; **19 API tests pass**, and **17 database scenarios pass** (18 Node test nodes including their parent). API type/format checks pass after the test transport update. Device tests are defined in `apps/mobile/integration_test/android_loop_test.dart`.

The first complete Android run passed all three functional cases (the driver reports four nodes including teardown): native encrypted-session storage, the journey/Bangla/native draft cycle, and real restricted-SQL account/Circle/report operations. These verified intended-recipient consent, outsider denial, leaving a Circle, reviewed-report withdrawal removing its public event, and a new submission remaining private/pending. The log is `.local/android-integration.log`. **This was not clean visual/native-input evidence:** all six checkpoint screenshots showed an Android System UI ANR dialog. Flutter test pointers can operate underneath that native dialog. The checkpoint now also requires the Awaaz window to have native focus, so that condition fails future runs rather than silently producing misleading screenshots.

Manual ADB input after dismissing the System UI dialog verified that the software keyboard opens (`mInputShown=true`, `mIsInputViewShown=true`) and Android Back dismisses it. Clean screenshots are `07-native-keyboard.png` and `08-native-back.png`. Input was sluggish and some injected characters were dropped; the native experience has not met a smoothness/performance gate. System UI/background-service ANRs and a cold activity-launch timeout remain emulator-environment defects to investigate. The host had roughly 0.4 GB available RAM during this run; this is evidence of resource pressure, not proof of the sole cause.

Fixed during this cycle: previous-account responses could start unnecessary private reads; invitation secrets could remain under another selected Circle; Android system Back did not navigate internal tabs/route selection; Android network/backup configuration lacked explicit restrictions. Private form contents now clear on account change. English/Bangla profile layout is checked at 320 pixels and 200% text.

The subsequent repair separates Circle detail from the creation/list screen, resets scroll on selection, and makes native Back return to the list while clearing invitation codes. Selection generations prevent a late detail/invitation response from restoring a closed view. Report receipt statuses are now allowlisted. These changes pass the complete host suite.

**Second device cycle: all three Android integration cases passed again**, with the native-window focus guard enabled, software keyboard enabled, and optional fixture-unrelated packages disabled. The functional cases completed in 74 seconds; this excludes installation, boot and driver connection time. `.local/android-integration-cycle2.log` records the successful driver exit. All six checkpoints passed the native focus check; the Bangla, consented Circle detail and private pending-report images were also visually inspected and are clean. Their filenames are `03-bangla-android.png`, `05-circle-consented-local-sql.png` and `06-private-report-pending-local-sql.png`. The second run overwrote the original six screenshots, so the original overlay evidence is retained separately in `current.png` and `cycle2-before-input.png`.

The lighter emulator still showed a System UI ANR during boot; it was manually dismissed **before** device test execution. The successful run does not establish a reliable cold-boot experience or production performance. Updated preview/test builds completed in 151.9 and 51.2 seconds respectively, with Gradle stopped before boot. The regular preview APK was reinstalled after the tests and its activity restarted; synthetic login remains confined to the test APK.

Post-test preview check: its native focused window was Awaaz and `12-final-preview.png` shows clean home rendering. An ADB-injected native tap opened route selection (`13-native-route.png`), independently of Flutter test pointers. Debug-kernel inspection confirms the regular preview does not contain `FixtureSessions` or the Android test entry path; the separate test APK contains both. The current preview is 106,525,950 bytes and the test APK 107,984,722 bytes; these are development debug builds, not release download sizes.

## Toolchain and network evidence

- Flutter 3.47.7 / Dart 3.13.5, Microsoft OpenJDK 21.0.12.1+1, Android command-line tools 22.0, platform/build tools 36, platform-tools 37.0.1, emulator 37.2.12.0, Flutter-pinned NDK 28.2.13676358.
- AVD `awaaz_dhaka_api36`: Google APIs x86_64 Android 36, 2048 MB requested RAM, 720×1560 screen, WHPX acceleration, four cores. `scripts/start-android-emulator.ps1 -LeanFixtures` disables Search/Assistant, Wellbeing, Safety Hub, Photos, Messages, Android System Intelligence, Android Auto and Chrome only in this disposable Awaaz test device. It verifies the exact device identity before setting animation/keyboard options or disabling packages. Play Services, location, the keyboard and accessibility remain enabled. Package changes can be reversed with `adb shell pm enable <package>` or by recreating the test AVD. This is a local fixture resource configuration, not a consumer-phone configuration. Compile before boot and stop Gradle before device tests. Performance on this laptop is not a phone benchmark.
- Gradle 9.3.1 distribution verified against publisher SHA-256 `b266d5ff6b90eada6dc3b20cb090e3731302e553a27c5d3e4df1f0d76beaff06`. Wrapper checksum enforcement is configured.
- Google Maven requests repeatedly time out on this network. `AWAAZ_USE_GOOGLE_MAVEN_MIRROR=true` enables an optional HTTPS Aliyun mirror scoped to Android groups; normal builds retain Google/Maven Central. This is a local build workaround, not an app service dependency.
- The same opt-in uses the [Flutter-documented CFUG mirror](https://docs.flutter.dev/community/china) exclusively for the `io.flutter` engine group. This avoids unnecessary Maven Central probes and the stalled primary engine download. The engine commit/version is unchanged.
- An optional ignored `.local/android-maven` contains annotation-jvm 1.8.2 (JAR verified against the SHA-256 in Google's cached module metadata) and annotation 1.0.0 (original cached Google POM; JAR byte-for-byte cross-checked between Aliyun and Huawei Cloud mirrors). Their exact SHA-256 values are enforced in the build script. The latter cross-check is **not** publisher signature verification. No annotation version was overridden.
- JNI requires CMake 3.22.1. Google's official `redirector.gvt1.com/edgedl/android/repository/cmake-3.22.1-windows.zip` downloaded successfully; its SHA-1 `292778f32a7d5183e1c49c7897b870653f2d2c1b` matches Google's cached SDK repository XML. The official archive is installed in the SDK with its original source.properties. Emulator JNI builds are restricted to x86_64; phone builds retain their regular ABIs.
- **Preview debug APK built successfully** on 13 October. After the network/CMake fixes the build completed in 238.8 seconds; `.local/awaaz-android-preview.apk` is 80,254,880 bytes. This confirms compilation, separately from device execution.
- The preview was installed and visibly ran on Android 36, captured in `.local/android-evidence/00-preview-after-system-ui.png`. The native screenshot exposed poor status-icon contrast; explicit dark system-bar icons are now configured and both APKs rebuilt. The native encrypted-storage test passed. The SDK integration-test surface-to-image conversion then stalled/blackened rendering; test checkpoints now request guarded ADB captures from the fixture server instead, preserving normal app rendering. Its device-name parser handles Windows ADB's doubled carriage returns.

Native build logs are under ignored `.local/android-build*.log`; device screenshots will be under `.local/android-evidence`. Release signing, cloud OTP, maps, background monitoring and emergency delivery remain unverified. Report submission currently exists in the repository/view model; the location-backed public report composer is still unfinished. Retry IDs survive ambiguous responses while the view model lives; restart-safe encrypted command persistence remains unfinished.

## Encrypted storage and retry increment

Native preview drafts and account/backend-scoped Circle, invitation and report requests now use encrypted storage. Requests persist before HTTP, keep their original UUID/time across restarts, and resend only through explicit user action. Storage/corruption failures do not invent replacement IDs or send HTTP. Cleanup failures preserve safe replay IDs. The client now accepts the backend's withdrawn replay receipt. [Full contract, retention and boundaries](PRIVATE_STORAGE_AND_RETRIES.md).

The complete host suite passed **55 tests**, then the updated account widget file passed all **9 cases**, including the additional account-change removal-confirmation test: **56 distinct passing cases**. Static analysis is clean and fixture API type/format checks pass. Preview/test APK builds completed in 163.6 and 30.8 seconds. The first native storage/lost-ack phase passed all three cases in 55 seconds, including real SQL and secure draft persistence.

That first attempt exposed a test procedure defect: Flutter `drive` uninstalls the application by default at completion. The attempted subsequent recovery run correctly failed because no saved request remained after uninstall. Flutter's local `commands/drive.dart` and `drive/drive_service.dart` confirm this behavior. `scripts/test-android.ps1` uses `--keep-app-running`, verifies that the app is installed, confirms the force-stopped process is gone, and keeps the same fixture database/accounts across both phases.

**The corrected two-phase native run passed completely.** Phase one passed all three cases in 50 seconds, left a committed report with its acknowledgement deliberately lost, and retained its encrypted request. The script confirmed process 3568 was stopped; phase two ran in a new process (3841), recovered the saved UUID/time, retried it explicitly through the UI and verified that exactly the same two server report IDs remained. Phase two's three cases passed in 31 seconds. Logs: `.local/android-storage-phase1-kept.log`, `.local/android-storage-phase2-kept.log`. These durations exclude installation/driver startup.

While the request remained pending, a read-only check of the app's native `FlutterSecureStorage.xml` found its journal key and no plaintext synthetic report description or `observedAt` JSON field. The installed plugin's local README documents default RSA OAEP/AES-GCM storage. This supports the native at-rest behavior; it is not a cryptographic audit. `07-saved-report-lost-ack.png` and `08-report-after-process-restart.png` passed the native focus guard and were visually inspected without overlays. This emulator boot completed in 51.9 seconds, and no System UI modal was observed during these corrected phases; earlier boot instability and phone performance gates remain relevant. The regular preview APK was reinstalled after testing.

## Receipt reconciliation and location composer increment

Authenticated receipt reconciliation now resolves received/withdrawn requests without another POST, including requests older than 72 hours. Unknown old requests keep their original UUID/time and remain saved with an explanation. A fourth migration preserves the two exposed restricted-role dispatchers, removes restricted-role access to the legacy dispatcher and is required by readiness checks.

The configured report composer now captures a foreground location through Geolocator 14.1.1's default adapter, checks precision/accuracy/freshness/pilot bounds, requires explicit text/location consent and submits privately for review. Location/consent clear on background or account change; closing the route cancels acquisition. [Full implementation contract and limits](LOCATION_REPORT_COMPOSER.md).

Current checks: **64 Flutter tests pass**, analysis is clean; **19 API cases pass**, **18 database scenarios pass** (19 nodes), and API format/type checks pass. OpenAPI was regenerated. Initial preview/test builds took 301.9/39.5 seconds with the new native dependencies; final test rebuild took 117.6 seconds. Nonfatal SDK XML/deprecated vendor Java warnings remain in build logs.

The first native attempt exposed a Google Play Services Location Accuracy opt-in dialog not handled by the test driver. The subsequent attempt captured a valid synthetic fix (estimated accuracy 5 m), but an exact text assertion rejected longitude 90.379998 instead of 90.380000. The test now checks captured state and validates persisted coordinates with a tolerance of 0.00001 degrees. The isolated fixture helper handles only the observed English opt-in button in the exact GMS settings window/AVD; this does not change production permission behavior. The default production location adapter remains in use, with no forced alternate provider in the device test.

**The corrected native run passed all four cases in both phases.** Phase one completed in 71 seconds. The script confirmed process 2195 was stopped; phase two ran in process 3248 and passed in 51 seconds. Saved report recovery used receipt GET with **no new report POST** and preserved the same server IDs. The new case verified no write before consent, native location capture, private/pending real SQL submission, and withdrawal returning the report list to its original IDs. Logs are `.local/android-storage-phase1-kept.log` and `.local/android-storage-phase2-kept.log`. Durations exclude boot/install/driver startup.

`09-native-location-composer.png` and `10-native-composer-private-receipt.png` passed native focus checks and were visually inspected without overlays. This test AVD's Google Location Accuracy setting was explicitly enabled in the fixture flow; ordinary runtime permission dialogs were programmatically pre-granted. Physical-phone accuracy/battery and human permission-dialog behavior remain separate evidence requirements. The regular preview APK was restored after testing. Hosted Auth/OTP, real routing/maps, native background journey monitoring, revocable sharing, moderation and SOS delivery remain unfinished.

## Native journey monitor increment — 13 October 2026

The new non-exported Kotlin location foreground service runs independently of Flutter frames, requires approved geographic geometry and explicit foreground start, and keeps Circle sharing/escalation off. Current schematic routes cannot arm it. [Contract, thresholds and remaining physical-device gates](NATIVE_JOURNEY_MONITOR.md).

The host suite passes **74 Flutter tests** with clean analysis. All **four Kotlin JVM tests** pass (`build/app/test-results/testDebugUnitTest/TEST-app.awaaz.awaaz.TripEngineTest.xml`, zero failures/errors). Run `./scripts/test-native-trip.ps1 -UseMirrors` before booting the emulator. The initial direct Gradle invocation unnecessarily resolved ARM engine artifacts; the helper uses the installed `android-x64` ABI and bounded network timeouts.

Host DNS resolution also prevented fetching JUnit 4.13.2. Its unmodified POM and JAR were fetched from `https://repo.maven.apache.org/maven2/junit/junit/4.13.2/` over verified TLS using curl's per-command DNS-over-HTTPS option. No system resolver setting changed. The optional ignored `.local/android-maven/junit/junit/4.13.2` cache is restricted to this exact artifact/version and checked against SHA-256 in the Gradle script: POM `569b6977ee4603c965c1c46c3058fa6e969291b0160eb6964dd092cd89eadd94`, JAR `8e495b634469d64fb8acfa3495a065cbacc8a0fff55ce1e31007be4c16dc57d3`. Ordinary builds without this cache still use Maven Central.

The expanded native suite contains six cases. The first device attempt caught a bridge decoding defect: `StandardMessageCodec` returns maps with object keys, while the HTTP JSON helper requires a string-keyed map. Both native method responses and event values now convert and validate their map before decoding a trip snapshot. The four earlier device cases passed during that failed attempt; the two new monitor cases failed as expected when the bridge rejected their state. Full corrected device evidence is recorded after the rerun.

The next attempt passed the first five cases and reached native tracking, but the fixture checked sleep immediately during Android's `Dozing` transition. Read-only power inspection confirmed `Asleep`, `mWakefulnessChanging=false` and `mHalInteractiveModeEnabled=false` after the transition. The fixture now polls for those observed states instead of assuming the sleep key has completed. Only this long-running fixture socket gets a 90-second idle limit; production API timeouts remain unchanged. Phase one explicitly force-stops any app/service left by a failed previous attempt while retaining private storage.

**The corrected run passed all six cases in both phases.** Phase one completed in 132 seconds and left an encrypted active synthetic monitor plus a committed report whose acknowledgement was deliberately lost. The driver confirmed process **4153** was stopped without uninstalling the app. Phase two ran in process **4665**, completed in 113 seconds, proved the native record became interrupted without resuming, recovered the original report using receipt GET with no new POST, and repeated the screen-off native notification check. Both phases verified one check-in alert, unchanged original session/route/revision after acknowledgement, an explicit replacement at revision two and a successful stop. Durations exclude installation/driver startup.

The fixture confirmed the native location foreground service before the trace, waited for actual sleep, injected seven moving off-corridor fixes over approximately 35 seconds and checked Android's notification record **7102 before foregrounding Awaaz**. `12-native-background-check-in.png` passed native focus checks and was visually inspected without overlays; its original-route acknowledgement and stop controls were readable. Logs are `.local/android-storage-phase1-kept.log` and `.local/android-storage-phase2-kept.log`. Earlier failed logs were retained separately for diagnosis. These are synthetic emulator mechanics, not real road, human permission-dialog, physical-phone/Doze or emergency delivery evidence.

### Follow-up startup, notification and location cleanup checks

The normal preview's first cold launch showed an unavailable status lookup; its explicit Stop recovery worked and a process relaunch was clean. Initial native binding now follows the first Flutter frame, and resume polling waits for initialization. A later cold boot produced a clean, focused preview (`16-native-preview-deferred-cold-start.png`). This is observed emulator improvement, not a physical-phone startup benchmark.

A native stop event or refresh now discards the old start UUID, so a notification Stop, permission loss or expiry cannot reuse that session for a later journey. The additional regression test passes; the host suite now contains **75 passing Flutter tests**. The device case has been expanded to operate the actual observed Awaaz notification Stop control rather than only call the Flutter stop method.

The expanded rerun stalled in foreground GPS cleanup. Native and Java thread diagnostics identified Android's main thread blocked in `unregisterGnssNmeaCallback` from Geolocator's `NmeaClient.stop` / `FusedLocationClient.stopPositionUpdates`. A diagnostic root session was used only on the exact isolated AVD and was reverted before reboot; no host privilege or other device changed. This explains the blocked cancellation path; it is not evidence of a Dart timer failure.

The official `geolocator_android` 5.1.1+1 archive was downloaded and matched the existing hosted lock SHA-256. Its source and MIT license are retained in a narrowly patched dependency override. Supplementary GNSS/NMEA data is now opt-in; Awaaz explicitly leaves it off and keeps the default fused provider for coordinates/accuracy. No global Pub cache file or test-only provider switch was used. [Patch provenance and limitations](../third_party/geolocator_android/PATCH.md). Patched preview/test APKs build and Flutter analysis is clean. Device rerun results follow below.

**Both final patched phases passed all six cases.** Phase one completed in 138 seconds in process **3787**. The driver confirmed that process was stopped while keeping the app and database. Phase two completed in 125 seconds in process **4357**. Foreground location capture/submission finished without the former cleanup stall. Both phases again checked a screen-off native check-in notification and explicit baseline replacement, then operated the actual notification Stop control. Phase one rearmed the same corridor with a different UUID; phase two verified the previous force-stopped active record became interrupted without resuming and recovered the committed report without another POST.

The notification helper initially checked focus too early. It now polls for the observed `NotificationShade` window, reads the exact Awaaz notification row from the native hierarchy, expands only its observed control and taps only its Stop action. `18-native-notification-shade.png` records the observed row. The final cold-boot test ran with ordinary shell UID **2000**, confirming diagnostic root was reverted. Screenshot `12-native-background-check-in.png` records the final check-in; regular preview restoration is recorded separately. All coordinates, identities and incidents remain synthetic.

The regular preview was reinstalled and launched after the final phases. After the native startup focus transition, `19-native-patched-preview-restored.png` passed the focus check and was visually inspected: clean Explore view, no monitoring error, no overlay. Read-only service inspection found no active trip monitor. Preview SHA-256: `c7b07ef64fa719c8e4027a571efcc58ecaf7ce3f902479d967db351608d000c7`; test SHA-256: `dcc4d7d65158d3a26a46194ee570cadf1216b0612f7192d783d87eb9cccd7463`. The disposable fixture API was stopped; the emulator remains open with the regular preview.

## Reproduce device tests

Build before booting the emulator on this limited-RAM host:

```powershell
./scripts/test-native-trip.ps1 -UseMirrors
./scripts/build-android.ps1 -UseMirrors
./scripts/build-android.ps1 -UseMirrors -Integration -StopBuildDaemon
./scripts/start-test-postgres.ps1
# In apps/api, keep the isolated fixture API running:
pnpm test:android-fixtures
# In the repository root, boot the test AVD:
./scripts/start-android-emulator.ps1 -LeanFixtures
# From the repository root, run both native phases with a real process restart:
./scripts/test-android.ps1
```

The script copies preview and test APKs into distinct ignored filenames. Reinstall `awaaz-android-preview.apk` after testing; the test APK contains synthetic identities in its separate test entry point and must not be distributed. Cloud SMS login is deliberately outside this fixture run.

The fixture checkpoint route validates a bounded filename, exact Awaaz AVD identity, resumed Awaaz activity and native focused window before calling ADB without a shell. Screenshots go to ignored `.local/android-evidence`. The route exists only in the disposable fixture entry point, not the production API. Window focus is a useful native-overlay guard; inspect the images as well, because it is not a complete visual or responsiveness assertion.
