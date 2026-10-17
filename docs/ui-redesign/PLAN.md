# Awaaz UI overhaul — 12 October 2026

## Existing app audit

The running build is the Flutter v2 slice in `apps/mobile`, not the old root prototype. It already supports English/Bangla, destination search, car/walk choices, route comparison, journey start/end, explicit detour check-ins, confirmed SOS previews, community fixture reports and consented private drafts. Domain routing/monitoring and API work remain intact.

Existing visual tokens: Manrope/Noto Sans Bengali; muted teal `#126A60`; warm canvas `#F6F7F2`; 16–20 px rounded surfaces. Explore, Community and Circle are the established navigation labels. The current UI is dominated by large headings, repeated white cards, explanatory text and a sparse four-road diagram. It feels like a form with a map illustration rather than a travel companion.

## Screenshot references inspected

- [Uber's official App Store screenshots](https://apps.apple.com/us/app/uber-rides-eats-hotels/id368677368): observed pickup map, prominent position/route markers, floating map controls and an attached action sheet. Borrow map hierarchy and separation of map/actions, not driver branding or ride-booking semantics.
- [Life360's official App Store screenshots](https://apps.apple.com/us/app/life360-family-safety-gps/id384830320): observed family selector, avatar markers, check-in/SOS controls and a People panel below the map. Borrow recognizable people and sharing-state hierarchy; retain Awaaz's explicit sharing-off demo semantics.
- [Citymapper's official Seattle route screenshot](https://content.citymapper.com/news/1465/a-letter-from-an-ex-seattleite-to-all-seattleites): observed compact mode choices and route rows with large minutes and smaller secondary details. This is an older screenshot used for its comparison pattern, not claimed as its latest interface.

Mobbin's connector required a paid plan. Official Apple lookup metadata and publisher-hosted screenshots were used instead, and actual images were inspected in the browser. References are credited, not shipped as Awaaz assets.

## Design direction

An Android safety companion with a confident, map-first travel language. Use Flutter Material 3 foundations, Manrope/Noto Sans Bengali, deeper teal, brighter mint highlights, white surfaces and a richer street illustration. Reserve red for SOS and amber for caution. Design variance 5, motion intensity 3, density 5: a visible overhaul, short state-transition motion, and useful compact information.

## Implementation sequence

1. Replace the sparse diagram with a detailed schematic street surface: blocks, parks, water, named areas, route alternatives, destination pin and location marker. Clearly label it illustrative and keep geographic claims out of the mock scene.
2. Recompose Explore around the map and a compact destination planner. Keep search and selected destinations functional, with mode choices and a visible journey action.
3. Give Routes a distinct origin/destination summary, prominent time comparison, selected route emphasis and readable coverage uncertainty.
4. Rework active journey/check-in states with a journey timeline and deliberate alert hierarchy. Keep SOS confirmation and explicit detour acceptance.
5. Replace anonymous repeated cards in Community/Circle with category visuals, source/review badges, avatars, relationship metadata and a clear sharing-off state. Refine the report form without changing consent or validation.
6. Rework navigation, typography, borders/shadows and motion consistently. Support small screens and 200% text.
7. Run existing interaction/domain tests, add meaningful checks for any new interactions, analyze/build, then review the running app at phone and desktop sizes. Save before/after evidence.

The current Figma connector returned an unavailable-tool error during this turn. Implementation is proceeding in Flutter; any Figma synchronization will be reported accurately.

## Implemented in Flutter

- Replaced the four-road graphic with a custom-painted city diagram, parks/water, route alternatives, origin halo, destination pin and community markers. Zoom operates around the map centre; reset restores the initial view. Community does not display a selected journey route. All geometry is fictional, clearly labelled and has accessible control names.
- Rebuilt Explore with a compact search panel, three functional destination shortcuts, selected destination, and car/walk modes. The smaller phone map leaves room for the planner; large screens use a map/planner split.
- Rebuilt route cards with prominent minutes, distance, preference, a radio selection indicator and coverage limits. Phones put the choices before the map; desktops retain the side-by-side map and choices.
- Added a distinct dark journey summary and clearer check-in hierarchy. Journey controls appear early on phones, and header SOS remains accessible across tabs during a trip. Existing confirmation and baseline state transitions are preserved.
- Community now has functioning category filters, category icons, review-status badges and separated private drafts. Its report action is visible before the feed. Circle uses initials, relationship rows, a privacy illustration and explicit sharing-off status rather than implied live locations.
- Refined the report form with a private-draft introduction. Field order, validation, consent and deletion remain intact.
- Applied deep teal `#0C5B49`, ink `#163C32`, mint `#D3EDAB`, 24–26 px panel/map corners, stronger type, subtle borders/shadows and 180 ms view transitions respecting reduced motion. Material 3, locally bundled fonts and English/Bangla remain the foundations.
- Adapted the brand header for narrow large-text layouts. Fixed action panels and navigation provide consistent reachability.
- Made demo/error status persistent above the scroll area. New screens reset their scroll position; destination typing and category-filter changes keep the current view stable.

## Validation evidence

The final full Flutter suite has 22 passing cases: 12 domain/view-model cases and ten UI cases. New UI checks exercise map zoom/reset, destination shortcuts, category filters, navigation scroll reset, persistent demo status and Community/Circle/Report at 320 px with 200% text in both languages. Existing journey, consent, deletion, offline/empty, 320/1024 px and language checks continue to pass. Static analysis is clean. The final release web build succeeds; the existing SDK font-scanner warning about an unused Cupertino family remains, while the actual Material icons and English/Bangla fonts render correctly.

Calculated token contrast ratios: ink/canvas 11.26, muted/white 5.65, muted/tint 4.79, primary/white 8.05, warning/caution surface 6.01, danger/white 5.88. These clear the normal-text AA threshold for the listed pairs; they are not a claim of complete accessibility certification.

The initial screen is preserved as `before-home.jpg`. Final previews are recorded beside this plan. They show the actual Flutter web build, not separate HTML mockups. Android device performance, production maps, real location sharing and emergency delivery remain the integration gates documented in the main development plan.

| View | Evidence |
| --- | --- |
| Original Explore | [Before](before-home.jpg) |
| Explore, phone | [English](after-home-phone.png), [Bangla](after-home-bangla-phone.png) |
| Explore, desktop | [After](after-home-desktop.jpg) |
| Route comparison | [Phone preview](after-routes-phone.png) |
| Active journey | [Phone preview](after-journey-phone.png) |
| Deviation check-in | [Phone preview](after-check-in-phone.png) |
| SOS confirmation | [Phone preview](after-sos-phone.png) |
| Community | [Phone preview](after-community-phone.png) |
| Report composer | [Phone preview](after-report-phone.png) |
| Circle | [Phone preview](after-circle-phone.png) |

Phone captures use a 390 × 844 browser viewport. The browser's temporary override was cleared after review; the running app is left at its normal desktop size, in English, with no active trip. Figma still contains the original prototype and has not received this overhaul because its connector returned unavailable-tool errors.
