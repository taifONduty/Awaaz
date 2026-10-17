# Community and Circle integration, 13 October 2026

The main Community and Circle tabs now use the account repository and existing backend contracts. They no longer show fixture reports or mock people when a configured account is active.

## Community

Published events from `GET /v1/road-events` appear as a compact feed with category, server summary, actual observation time and published status. The contract has no public location name or coordinates, so the client does not invent either or draw geographic markers. Category filtering, refresh, loading, sign-in/profile setup, errors and empty conditions are handled directly in the main tab. Expired events disappear through the existing model timer. Unknown conditions are not presented as safe.

Report submission still requires a verified phone, profile, foreground location and consent. The report action opens the existing private composer; its receipt/history path is accessible from My reports. Private submissions never become feed rows by client action. Anonymous preview drafts remain distinctly labeled as device-only data. Without backend configuration, fixture reports are explicitly labeled and the illustrative map sits in a collapsed secondary section.

## Circles

The main tab lists actual owned/joined Circles and incoming invitations. It exposes management, an empty setup state, loading/error states and a truthful sharing-off state. The old decorative mock contacts are retired. Selecting a Circle loads its restricted detail and opens the existing member/invitation controls directly. Back clears the transient detail/secret and returns to the main Circle tab in one action.

Incoming invitations are filtered by expiry, and the model's existing timer covers both invitations and published events. Generated invitation secrets also expire from the UI. Copy/revoke callbacks capture the shown invitation and check that it is still current, so a delayed confirmation cannot dereference an expired token or revoke a replacement invitation.

Sign-out/account changes clear private state and reconstruct the Community view. Existing session epochs, restricted SQL, explicit membership changes, durable request IDs and receipt reconciliation remain in use. This increment does not enable location sharing, public publishing, emergency delivery or hosted phone login.

## Verified 14 October 2026

Thirty-two existing UI/account checks pass, including the account-backed main tabs, direct Circle back navigation and sign-out cleanup. The 12 existing account-model checks pass again with incoming/generated invitation expiry. No new test cases or fixture frameworks were introduced. Final static analysis is clean.

Both Android process-restart phases pass all six cases: phase one runs for 3:04 in PID 2242, then the host confirms force-stop; phase two runs for 2:11 in PID 3694 using the same marked database and actors. The extended backend case checks the actual SQL-published summary in Community, absence of fixture report text, Circle creation, overview-to-member navigation and one-action back. Existing native report consent, encrypted journals, old receipt recovery without a new POST, screen-off alerts, baseline approval, notification stop and interrupted-state checks remain passing.

The final integration APK builds in 260.4 seconds; regular preview builds in 117.5 seconds. Test APK SHA-256: `72cb04d6831aeca20f0c39b6e224ba8f080959ccd4d92de0cd64bc64a45eaec6`. Preview APK SHA-256: `892ee6df4d462e6f846b8c455cffc08d644258239a4b08d9707ed7b7ca114b42`.

Device evidence: [published feed](ui-redesign/community-backend-android.png), [restricted member detail](ui-redesign/circle-detail-backend-android.png). These contain synthetic local data, not hosted user reports or contacts. Logs are `.local/android-storage-phase1-kept.log` and `phase2-kept.log`; the preceding logs were preserved separately before this run. Hosted Supabase configuration, actual Circle location sharing, moderation/publishing workflows, delivery, real routing and physical-phone/OEM validation remain unfinished.

Flutter's integration-test dependency ranges triggered a failed daily Google Maven metadata refresh. The project now resolves those open-ended ranges to current stable AndroidX runner/rules `1.7.0` and Espresso core `3.7.0`, without modifying the Flutter SDK or global caches. [Official AndroidX release reference](https://developer.android.com/jetpack/androidx/releases/test).
