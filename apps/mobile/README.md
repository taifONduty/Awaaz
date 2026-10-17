# Awaaz mobile v2 — development preview

Native preview drafts and pending Circle/invitation/report requests now use encrypted storage. Saved live requests are scoped to the backend/account, survive restarts, and resend only after an explicit retry using the original UUID/time. Web data is memory-only. See [private storage and retry behavior](../../docs/PRIVATE_STORAGE_AND_RETRIES.md).

This is the refreshed Flutter entry point. Use Flutter 3.47.7 / Dart 3.13.5. The original root package is a preserved prototype.

Run `flutter pub get`, `flutter analyze`, `flutter test`, and `flutter run -d chrome` from this directory. English/Bangla UI, journey choices, fixture A*, simulated detour prompts, SOS previews and private local drafts work without cloud credentials.

Routing and journey monitoring remain explicitly in preview mode. Profile/Circle screens, the foreground location-backed report composer and receipt reconciliation are implemented. Configure a fresh Supabase project and API using `config/backend.example.json` as a template for an ignored `backend.local.json`, then pass `--dart-define-from-file=config/backend.local.json`. Native sessions use encrypted storage; web sessions remain memory-only. Real maps, background tracking and contact delivery remain unfinished. Release Android signing remains unconfigured. [Current report contract and evidence](../../docs/LOCATION_REPORT_COMPOSER.md).

The user selected synthetic local fixtures for ongoing development. Start `../../scripts/start-test-postgres.ps1`, then run `pnpm test:android-fixtures` in `../api`. The Android integration test uses `10.0.2.2:3031` and injects synthetic sessions from test code only. See [Android development loop](../../docs/ANDROID_DEVELOPMENT_LOOP.md) for toolchain, network fallback and measured results.

See [development plan](../../docs/DEVELOPMENT_PLAN.md), [verification](../../docs/VERIFICATION.md), [production architecture](../../docs/AWAAZ_ROAD_SAFETY_DESIGN.md), and [Figma](https://www.figma.com/design/8C7LHBjpEzvRXol0XuPd1R?node-id=9-119).
