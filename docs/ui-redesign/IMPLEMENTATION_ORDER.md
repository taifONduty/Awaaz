# UI implementation order, 13 October 2026

The user requested implementation over additional test scaffolding, a substantial visual upgrade grounded in established apps, and completion of remaining flows one at a time. Retain focused checks for changed behavior and actual emulator review.

## Audit and direction

The 360 dp Android home capture (`.local/android-evidence/20-before-redesign.png`) shows a large brand bar, amber demo card, marketing heading/subtitle, inset map and another rounded planner. The primary footer is visible but destination choices require scrolling. Teal text on a green canvas and repeated 24 px containers make every element appear equally important.

Preserve Awaaz's wordmark, teal accent, bundled Manrope/Bengali fonts, Explore/Community/Circle navigation, consent, uncertainty and preview labeling. Apply the taste skill's audit, hierarchy, restraint, accessible controls and state handling to Flutter Material 3. Its landing-page effects and React defaults do not fit this mobile product. Design variance 4, motion 2, density 5.

Publisher screenshots inspected in the browser:

- [Uber](https://apps.apple.com/us/app/uber-rides-eats-hotels/id368677368): map with an attached confirmation surface and separate map controls.
- [Google Maps](https://apps.apple.com/us/app/google-maps/id585027354): map dominates navigation; compact route times and secondary details; actions are grouped near the bottom.

These are visual references, not shipped assets or copied brands. Mobbin's callable tools returned unavailable-tool errors in this session. No claim of Mobbin research or current Figma synchronization is made.

## Sequence

1. **Explore → destination → route choice.** Replace the stacked marketing layout with full-width map context and one planning surface. Add a dedicated destination picker with explicit selection, bilingual filtering and keyboard/back handling. Use compact route rows, a single coverage explanation, and a reachable start action. Keep all fixture geography labeled, with no route drawn before planning.
2. **Community → report → receipt.** Make reports the main content, move the illustrative map into a secondary view, integrate the real published feed, and present pending/private/reviewed states clearly. Preserve consent and account requirements.
3. **Circle → member detail → invitation.** Replace decorative mock people as the main content with account-backed memberships and explicit invitation status. Sharing remains off until delivery and revocation are implemented.
4. **Active trip → check-in → finish.** Compose the native monitor state, uncertainty, route and recovery actions into one journey surface. Avoid duplicate alerts and preserve explicit baseline approval.
5. **Real map and routing.** Integrate licensed geographic data and a versioned routing contract before enabling ordinary routes for background monitoring. Do not substitute invented road safety data.
6. **Hosted authentication, moderation and delivery.** Complete production-only service integration and operational gates after the local flows are cohesive. Physical-phone/OEM validation remains separate from emulator proof.

The 14 October backend increment implements the private moderation queue, audited decisions and explicit publication onto registered real graph edges. The existing Android Community/withdrawal/restart flows pass against that pipeline. A full operator console, appeals, evidence snapshots and risk-aware routing remain unfinished. [Workflow and Android evidence](../ROAD_ASSOCIATION.md).

## Step 1 implementation

`explore_page.dart` owns the bounded home layout and destination picker. Phones use map plus planning sheet; wide views put planning beside the map; short screens and larger text use normal scrolling. Shortcut destinations remain horizontally scrollable with full labels. Search filters fixtures only and never treats them as saved personal places, GPS results or recent history. Search requires selecting a result, with a single-result keyboard submit shortcut; cancel preserves the previous selection.

The shell removes the duplicate home footer action and inactive monitor explanation card, while retaining actual active/interrupted/error monitor controls. Routes use selected rows with duration, distance and time tradeoff, followed by one uncertainty statement. Colors shift to neutral gray surfaces and near-black text with teal reserved for selection/actions. Buttons use 12 px corners, inset maps 16 px, and the home planning surface 24 px top corners.

The selected destination is repeated inside the search control, so the primary action has a visible destination even when its shortcut is outside the horizontal viewport. Launcher and launch-screen resources reuse the existing Apache-2.0 Material shield from `design/icons/shield.svg`. Android 12+ uses explicit platform splash attributes; older supported Android versions use a centered vector layer. No bitmap generation, new logo or runtime splash dependency was introduced. [Android platform guidance](https://developer.android.com/develop/ui/views/launch/splash-screen/migrate).

Installed-build review: the complete planning surface is visible at 360 dp in English and Bangla. Typing University with the real keyboard returns the expected result; explicit result selection changes the target. Route rows plus the start action are visible. Selecting Fastest updates the selected row, starting uses its 20 min / 5.4 km fixture, and ending restores Explore. Cold launch displays the teal shield, with compiled launcher resources pointing to `awaaz_launcher.xml`. The emulator is left on Explore with no active native monitor.

Twenty existing UI/account checks pass; the 11 existing general UI checks pass again after the final refinement. Static analysis is clean. Final Android build succeeds in 179.3 seconds. Preview APK SHA-256: `57fd281e290149ba53514230916be29d0bb7fab4f671048aeee234ef0b6ec792`. This increment does not rerun the backend, native unit suite or full Android integration suite because their logic was unchanged. No test cases or fixture scaffolding were added.

Review evidence: [English home](home-v3-android.png), [Bangla home](home-v3-bangla-android.png), [destination search with keyboard](destination-v3-android.png), [route comparison](routes-v3-android.png), [branded launch](launch-v3-android.png). These show the installed Android app, not generated mockups. The Figma file remains the older design and needs synchronization when its connector is available.

Step 1 is complete. Steps 2 and 3 are implemented in the main tabs: Community selects published backend events when configured, and Circle uses real memberships/invitations with direct detail navigation. Private report history and preview drafts remain separate. Their current verification and remaining production gates are recorded in [Community/Circle integration](../COMMUNITY_CIRCLE_INTEGRATION.md).

Step 4 composes the active journey and native monitor state, with explicit arming consent and verified stop handling. [Journey UI scope and evidence](../JOURNEY_UI_INTEGRATION.md). Step 5 now integrates actual street routing: a versioned OSM/GraphHopper API, map-pinned destination, fresh consented origin, geographic route summary and fixed native trip controls. [Installed evidence and limits](../REAL_ROUTING_INTEGRATION.md). Experimental reviewed-report alternatives now connect the evidence worker to the API and Flutter picker, retaining unknown safety assessment. Native status/check-in controls precede the map after installed review. [Route integration and current performance finding](../REPORTED_ROUTE_INTEGRATION.md). Independent calibration, named-place lookup, user-approved replacement geometry and the remaining production/device gates are still outstanding.
