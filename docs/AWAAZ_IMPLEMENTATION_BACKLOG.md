# Awaaz implementation backlog

Prepared 12 October 2026. Companion to `AWAAZ_UPDATE_PLAN_2026.md`. This is a proposed work breakdown, not a set of completed tasks or tickets created in an external system.

Scope: public Android launch for adults in Bangladesh. Keep Flutter. First-release core: trusted circles, SOS, time-limited journeys/check-ins, localized help, and clear delivery/response status.

Updated scope: all old data is mock data; no legacy-user migration. Use fresh Supabase Auth, MapLibre/OSM and custom GraphHopper routing. Dhaka city community reports, transparent risk/coverage scoring and native route monitoring join the release scope. The G–J work streams below extend this backlog; `AWAAZ_ROAD_SAFETY_DESIGN.md` defines their contracts and release gates.

Owner labels describe disciplines, not assigned people: Product/UX, Flutter/Android, Backend, QA, Operations, and qualified Legal/Security reviewers. A small team can combine roles, but every critical responsibility needs a named owner before pilot.

## Delivery rules

- Implement one vertical flow at a time. A usable two-device drill is more valuable than completing every screen independently.
- Build backend authorization and device failure behavior with the feature, not as a final cleanup.
- Migrations start in staging with synthetic data; production changes have backup and rollback evidence.
- An estimate is not an acceptance criterion. A phase ends when its demonstrated behavior passes.
- Keep optional features behind flags. Emergency dialing and clear failure information remain available when a nonessential feature is disabled.
- New features do not require a framework rewrite. Keep Flutter and move domain logic out of screen widgets incrementally.

## Milestones

| Milestone | Required demonstration |
| --- | --- |
| M0 — agreed product and environment | Adult scenarios, recipient expectations, reproducible toolchain, backend inventory and hosting review path |
| M1 — secure usable baseline | Signed test build, account recovery, trusted invite/accept/revoke, authorization isolation |
| M2 — complete emergency flow | Incident accepted by server, recipients notified, acknowledgment recorded, cancellation persisted, retries controlled |
| M3 — ordinary safety session | Journey/check-in deadline, screen-lock tracking, stale-state handling, completion stops access |
| M4 — pilot ready | Bangla/English, verified directory, SMS contract/tests, support ownership, deletion, restore and device evidence |
| M5 — public release candidate | Controlled pilot gates passed; current Play requirements/disclosures complete; rollback/runbooks exercised |

## A. Discovery and baseline

| ID | Work | Owner | Depends on | Acceptance evidence |
| --- | --- | --- | --- | --- |
| A01 | Interview adult users and potential alert recipients | Product/UX | — | 12–20 interviews across commuting/student/family contexts; documented scenarios, consent concerns and alert comprehension; no unsupported market-size claims |
| A02 | Inventory mock environments, settings and reusable assets | Backend | — | User-confirmed mock-data status recorded; existing project ownership/configuration and useful assets documented; fresh environments planned; no unrelated cloud deletion |
| A03 | Approve launch service/privacy scope and vendor evaluation | Product, Legal, Operations | A01, A02 | Hosting/data transfer review, recording boundaries, adult eligibility, retention decisions and SMS shortlist recorded; no dispatch promise without agreement |
| A04 | Restore reproducible Android builds and fix broken imports | Flutter/Android | — | Chosen compatible Flutter/Dart/dependency/toolchain versions documented; main app builds and opens; ringtone/team/sidebar imports resolved; invalid active widgets checked |
| A05 | Consolidate active routes and initialization | Flutter/Android | A04 | One active auth/home flow; setup failures produce usable retry/error screens; obsolete duplicate paths no longer participate in launch navigation |
| A06 | Introduce module boundaries and meaningful baseline tests | Flutter/Android, Backend | A04, A05 | Auth, circle, session, incident and notification repositories/interfaces exist; critical logic testable without live services; old counter test replaced |

## B. Identity, data, and circles

| ID | Work | Owner | Depends on | Acceptance evidence |
| --- | --- | --- | --- | --- |
| B01 | Create dev/staging/prod configuration and SQL migrations | Backend | A02, A03 | Fresh synthetic staging database reproducible from migrations; privileged secrets never in client; reviewed setup instructions and config |
| B02 | Implement fresh Supabase Auth and profile ownership | Backend, Flutter/Android | B01, A06 | Google/email login, refresh/recovery and verified UUID ownership; wrong/expired tokens rejected; phone verification for public reporting; no Firebase UID migration |
| B03 | Implement RLS, Storage and Realtime authorization | Backend, Security | B02 | Stranger/other-circle/expired-grant/revoked-contact cases denied; test coverage for verified subjects, internal IDs and server-privileged paths |
| B04 | Build expiring invites and accepted trusted relationships | Backend, Flutter/Android | B02, B03 | Invite expires; acceptance requires intended account/contact control; cannot silently link someone by email; duplicate/replayed acceptance is safe |
| B05 | Build circles and explicit sharing grants | Backend, Flutter/Android | B04 | Adult can assist/share with multiple groups; membership does not imply all-time location rights; purpose/recipient/expiry shown before sharing |
| B06 | Build leave, revoke, block and report | Backend, Flutter/Android | B05 | Active channels/pages stop receiving new data after revocation; blocked contact cannot create new unwanted interactions; support route exists |
| B07 | Build account recovery and device registration/revocation | Backend, Flutter/Android | B02 | Several device tokens per profile; refresh/logout/deletion invalidation; lost-device recovery tested; stale token removed after provider response |
| B08 | Add contact opt-in and readiness drill | Product/UX, Flutter/Android | B04, B07 | Recipient agrees to channel use; readiness screen explains actual permissions/device state; explicit test alert never mistaken for real distress |

## C. Incidents and delivery

| ID | Work | Owner | Depends on | Acceptance evidence |
| --- | --- | --- | --- | --- |
| C01 | Define incident lifecycle and command schemas | Backend, Product/UX | B05 | Active/cancelled/resolved independent of delivery/response; authenticated actor and idempotency contracts; version and timestamp conventions documented |
| C02 | Implement create/cancel/resolve/ack commands | Backend | C01, B03 | Recipients derived from valid server-side relationships/grants; one logical incident per command ID; ack never closes incident automatically; competing updates tested |
| C03 | Implement transactional outbox and notification jobs | Backend | C02 | Incident commit and jobs cannot diverge; lease/visibility and due-time indexes; per-recipient/channel deduplication; dead-letter state and restart recovery |
| C04 | Implement FCM adapter and Android notification handling | Backend, Flutter/Android | C03, B07 | Same channel IDs, intended TTL/version, urgent visible rendering; foreground/background/opened/terminated flows; invalid token handling; no "delivered" label from send acceptance |
| C05 | Evaluate/contract and implement SMS adapter | Backend, Operations | A03, C03 | Opt-in carrier test matrix, sender registration, unicode segmentation, fixed-egress needs, receipt/callback semantics, retry/cost limits and support arrangements documented |
| C06 | Build scoped non-app recipient page | Backend, Web, UX | C02, B03 | Expiring/revocable recipient token; no indexing/referrer/token analytics leakage; acknowledgments require explicit state-changing POST; GET/prefetch produces no acknowledgment |
| C07 | Build SOS interface and local outbox | Flutter/Android, UX | A06, C02 | Fast understandable trigger; unknown/stale GPS does not block incident; local pending distinct from server receipt; expired/cancelled queued alerts not blindly replayed |
| C08 | Build escalation, retries and callback processing | Backend | C03–C06 | Pilot timing policy documented; recheck current incident before each attempt; provider timeouts/replays/worker crash after send bounded; no uncontrolled alert storms |
| C09 | Build recipient incident and response interface | Flutter/Android, UX | C04, C06, C07 | Shows who requested help, dated position and uncertainty; distinct acknowledgment/help/resolution; resync on reconnect; cancelled alerts don't appear active |

## D. Android lifecycle and journeys

| ID | Work | Owner | Depends on | Acceptance evidence |
| --- | --- | --- | --- | --- |
| D01 | Implement native session location service | Flutter/Android | B05, C07 | Eligible user-initiated foreground service; declared types/permissions; persistent notification; tested app lifecycle; location stops on ended grant; no power-button claims |
| D02 | Implement location snapshot and access-controlled updates | Backend, Flutter/Android | D01, B03 | Capture/receipt/accuracy/sequence recorded; old samples cannot overwrite newer snapshot; stale/unknown explicit; valid zero coordinates accepted |
| D03 | Implement durable journey/check-in session commands | Backend | C01, B05 | Start/extend/complete/expire commands idempotent/versioned; recipient policy and deadline stored on server; no indefinite sharing default |
| D04 | Implement deadline scheduler and recovery sweep | Backend | D03, C08 | Reminder/escalation work survives client death and worker restart; late completion/extension races safe; scheduler resolution/delay measured |
| D05 | Build journey/check-in UX and recipient view | Flutter/Android, UX | D02–D04 | Destination or timer flow; recipients know expected action; extension/completion clear; user understands what happens when the phone loses connectivity |
| D06 | Implement cache, deferred sync and offline fallback | Flutter/Android | C07, D05 | Contacts/directory/session status available offline; retryable work persists; dialer/SMS composer reachable; no false claim of cloud SMS without data |
| D07 | Integrate MapLibre and compatible place-search provider | Backend, Flutter/Android | A06 | Licensed tiles/geocoder, Dhaka/Bangla search benchmark, attribution/offline terms, separate route interface and credential scopes; no legacy Google route dependency |
| D08 | Test packaging and native dependencies | Flutter/Android, QA | A04, D01, D07 | Android 16 target; chosen minimum/device range; 16 KB environment compatibility; signed AAB installs through test track; dependency risks recorded |

## E. Localization, privacy, and operational readiness

| ID | Work | Owner | Depends on | Acceptance evidence |
| --- | --- | --- | --- | --- |
| E01 | Build Bangla/English and accessible critical screens | Product/UX, Flutter/Android | C07, C09, D05 | Human-reviewed critical translations; text scaling, screen readers, contrast, non-color status cues; representative users complete the drill |
| E02 | Build verified local help directory | Product, Operations, Flutter/Android | A03, D06 | Official provenance and last verification; offline cache and call actions; no unconfirmed police integration; corrections and maintenance owner |
| E03 | Implement private media and retention controls | Backend, Security | B03, A03 | Public attachment paths removed from launch flow; grants and expiry enforced; local encryption deliberately configured; no misleading E2EE claim |
| E04 | Implement export, deletion and recovery effects | Backend, Flutter/Android, Web | B07, C02, E03 | In-app/web deletion route; sessions/grants/jobs/media revoked or deleted per policy; backup retention explanation; no orphaned alert delivery |
| E05 | Add diagnostics, monitors and operational runbooks | Backend, Operations | C08, D04 | Queue-age/provider-failure alerts, test incident traces, scoped access and secret/location redaction; named duty/support owners and outage actions |
| E06 | Establish backups and exercise restore | Backend, Operations | B01, E05 | Database and object/media recovery assessed separately; chosen RPO/RTO supported by purchased capabilities and restore evidence; rollback compatibility verified |
| E07 | Complete device/network/security exercises | QA, Security | C09, D06, D08, E01–E06 | Matrix covers permissions, Doze, force-stop, multiple devices, slow/no networks, replay/auth failures, cancellation races and load; critical failures resolved |
| E08 | Prepare Play policies, public documents and support | Product, Operations, Legal | E07 | Current release-time target/permission rules checked; privacy/Data Safety/deletion/terms/support URL; background-use evidence; store copy matches real scope |

## F. Fresh-build pilot and launch

| ID | Work | Owner | Depends on | Acceptance evidence |
| --- | --- | --- | --- | --- |
| F01 | Run controlled consent-based pilot | Product, QA, Operations | E08 | Start with 50–100 adults; test alerts clearly labeled; recipient exercises; permission/device/network-stratified data; issues triaged against gates |
| F02 | Review readiness and perform staged public rollout | Product, Engineering, Operations | F01 | Pilot thresholds met for agreed observation window; critical issues closed; ownership/funding exists; small percentage rollout with defined stop/rollback signals |
| F03 | Prepare synthetic fixtures and fresh-release reset procedures | Backend, Operations | A02, B03, C02 | Synthetic users/incidents/reports/routes; staging recreation documented; production secrets/data isolated; no mock-data migration or unrequested cloud deletion |
| F04 | Rebuild retained chat/community/private-storage paths | Backend, Flutter/Android | F03, G03 | Single Supabase source of truth; structured reports/moderation before public community; private attachment ownership/deletion; duplicate Firebase domain paths removed |

Dependency shorthand such as `C03–C06` means all listed tickets in the range. Public Dhaka road-risk routing/monitoring requires the G–I pilot gates in addition to E08. J-series trained-model promotion is optional and evidence-gated; it does not block the transparent baseline pilot.

## First two-week iteration

1. Run A01/A02/A03 discovery alongside A04 build restoration.
2. Write the adult consent/incident model and document actual deployed state.
3. Produce a signed internal build with working login/home navigation and no dead controls in the demo path.
4. Establish a fresh Supabase Auth/staging schema and narrow ownership proof before broad feature work.
5. Demonstrate authenticated own-profile reads and rejected stranger access; prove the Dhaka graph/tile pipeline can run and record mapping/provider gaps.

End-of-iteration deliverables: reproducible setup, discovery notes, architecture decisions, backend inventory, build/test evidence, and an implementation-ready circles/SOS contract. Do not promise full SOS delivery and vendor setup within this first iteration.

## G. Community road intelligence — expanded release scope

| ID | Work | Owner | Depends on | Acceptance evidence |
| --- | --- | --- | --- | --- |
| G01 | Define report taxonomy, status and publication policy | Product, Moderation, Legal | A01, A03 | Event/perception/infrastructure separated; account verification distinct from report review; behavior-based categories; no appearance/person watchlists |
| G02 | Implement structured private submissions and redacted public views | Backend, Flutter/Android | G01, B02, B03 | Event/submission timestamps, geometry uncertainty, correction/withdrawal; public output excludes reporter/victim identities and private attachments |
| G03 | Build moderation, disputes and abuse handling | Backend, Operations | G02, B06 | Queues, audited decisions, withdrawal/appeal, staffed ownership; provisional versus reviewed status; coordinated-posting and duplicate tests |
| G04 | Import/version Dhaka graph with boundary connectivity | Geospatial, Routing | A03, D07 | OSM provenance, mode access and turns audited; graph buffer sufficient; old sessions cannot reference remapped edge IDs silently |
| G05 | Associate reports with roads and event clusters | Backend, Geospatial | G03, G04 | Flyover/parallel-road cases; uncertain associations retain weights/confidence; copies become one bounded event, not independent incidents |
| G06 | Implement baseline risk dimensions, coverage and expiry | Backend, Data | G05 | Zero-report roads remain unknown; mode/time-specific decay and caps; corrected/expired reports reverse their influence; independent coverage retained |
| G07 | Publish immutable snapshots and bounded map/corridor deltas | Backend, Routing | G06 | Graph/risk compatibility checks; atomic complete publication; expiry refresh; public tile privacy; region/corridor resync on reconnect |
| G08 | Build community map/report UX and pilot coverage audits | Flutter/Android, UX, Geospatial | G07, E01 | Age/status/reasons/unknown coverage visible; no city-wide reliability claim from one area's reports; Bangla field audits and abuse drills |

## H. Risk-aware routing

| ID | Work | Owner | Depends on | Acceptance evidence |
| --- | --- | --- | --- | --- |
| H01 | Pin GraphHopper and prototype custom weighting | Routing | G04, G06 | Legal directed/turn-aware graph; external request-scoped risk arrays; no claim stock JSON is a live arbitrary per-edge risk store |
| H02 | Implement exact A* and proven lower-bound heuristic | Routing, QA | H01 | Nonnegative seconds-equivalent cost; edge-based state; A*/Dijkstra agreement; virtual endpoints and rounding checked; h=0 fallback |
| H03 | Implement fastest/balanced/safety-focused options | Routing, UX | H02 | Separate ETA/risk objective; geometry deduplication; confidence/reasons; detour-cap candidate method labelled honestly; no guaranteed-safe claim |
| H04 | Implement resident graph/overlay versions and safe swaps | Routing, Backend | H03, G07 | No per-expanded-edge SQL; frozen request snapshot; concurrent compatible updates; retain graph for active sessions; mismatch rejected |
| H05 | Package authorized route-corridor bundles | Routing, Backend | H04, B03 | Selected and plausible alternate road geometry/direction/risk; baseline/current-route versions distinct; bounds/memory/checksum and expiry |
| H06 | Validate local profiles and route legality | Geospatial, QA | H03, H05 | Walking/car first; motorcycle/CNG only after checks; bus monitoring uses expected itinerary; known illegal turns/roads never proposed |
| H07 | Benchmark and isolate routing capacity | Routing, Operations | H04, H06 | Dhaka latency/visited-node/load bounds; timeout not labelled optimal; routing overload cannot starve core SOS commands/delivery |

## I. Local trip matching and deviation alerts

| ID | Work | Owner | Depends on | Acceptance evidence |
| --- | --- | --- | --- | --- |
| I01 | Build bounded native matcher and replay harness | Android, QA | H05, D01 | Rolling GPS sequence with accuracy/heading/topology; nearby alternatives not just selected route; ambiguous/outside-bundle state |
| I02 | Implement deviation state machine and baseline acceptance | Android, Product | I01 | Sustained credible departure; hysteresis/cooldowns; reroute cannot silently erase baseline; acceptance explicit/versioned |
| I03 | Implement local alerts and chosen contact escalation | Android, Backend, UX | I02, C08 | Prompt while UI hidden; usable response actions; no cloud dependency for local decision; no automatic accusation; escalation requires pre-trip policy |
| I04 | Persist service state and offline corridor behavior | Android | I03, D06 | Screen-off tests; no fresh reports/online reroute claim offline; service stop/force-stop produces reduced/stale monitoring rather than false live status |
| I05 | Calibrate thresholds and evaluate labelled trip traces | QA, Data, Android | I04, H06 | Parallel roads/flyovers/tunnels/legitimate detours; recall/precision/false alarms per trip-hour; confidence intervals and device/mode stratification |
| I06 | Profile frames, battery, heat and upload policy | Android, Flutter, QA | I05, G08 | Release-build frame/latency budgets; vector layers instead of thousands of widgets; local processing off UI thread; adaptive sampling benchmark |
| I07 | Execute Dhaka controlled pilot and release gates | Product, QA, Operations | I06, H07, G08, E08 | Users understand unknown risk and notifications; moderation funded; observed legal routes/deviations; public rollout stops on critical leakage/false-alert defects |

## J. Trained model — evidence-gated follow-up

| ID | Work | Owner | Depends on | Acceptance evidence |
| --- | --- | --- | --- | --- |
| J01 | Define model target and independent audit/label program | Data, Product, Geospatial | G08 | Label is measured outcome/condition; exposure/missingness documented; no crime probability from subjective votes; sufficient independent evidence assessed |
| J02 | Build availability-time-safe dataset and combined holdouts | Data, QA | J01 | Temporal cutoff plus spatial blocks/buffers plus grouped events; no later review leaks; governed consent/export provenance |
| J03 | Compare transparent baselines and LightGBM candidate | Data | J02 | Appropriate ranking/calibration metrics, uncertainty, area/mode/time slices; monotonic constraints justified; formula mimicry identified |
| J04 | Shadow-score, review route effects and plan rollback | Data, Routing, Operations | J03, H04 | Candidate does not control live routes until gates passed; route-level explanations; compatible versioned arrays; baseline fallback |
| J05 | Promote and monitor model under explicit approval policy | Data, Product, Operations | J04 | Stable independent results, drift/coverage and feedback-loop checks; rollback exercised; no emergency path depends on model availability |

These work streams revise the original narrow release estimate to approximately 24–36 weeks with two to three engineers plus geospatial/data/QA/moderation support. ML promotion depends on dataset maturity; it has no automatic delivery date. I07 augments the core F01/F02 pilot/rollout gates, and the baseline pilot does not require J-series completion.

## Further release backlog

| Release gate | Features | Additional acceptance before release |
| --- | --- | --- |
| After reliable pilot | Geofences, arrival/departure alerts, battery/lost-contact status, richer private chat, fake-call customization, quick tile/widget | Battery and false-alert evidence, revoked-access tests, realistic lock-state behavior, private media and reporting |
| After baseline road release | Broader audits, partner hazard feeds and moderated community discussions | G-series controls retained; measured local data coverage; no exposed victim journeys or unreviewed person accusations |
| After partner validation | Help venues and additional transport profiles | Coverage/confidence/age displayed; venues verified/rechecked; local access/itinerary checks |
| After recording/privacy review | Optional evidence capture, incident export, later live streaming | Platform permissions, encryption/retention, user action and consent, upload/recovery tests, responder capacity |
| After language/model evaluation | Resource search, report transcription, incident-summary drafts, moderation assistance | Bangla/English quality benchmarks, human correction, no emergency transmission gate, no unnecessary location/cloud disclosure |
| After device/operations proof | BLE/Wear OS, experimental voice/shake/fall detection, response-center integration | Device compatibility, disconnect/false-positive trials, trained staff/contract, coverage/response disclosures |

## Risk register

| Risk | Effect | Mitigation / gate |
| --- | --- | --- |
| A contact sees location without valid consent | Stalking or other harm | Sharing grants, mutual acceptance, immediate revocation, expiry and negative auth tests are launch requirements |
| Push/SMS is accepted but no person responds | False reassurance | Show measured states; explicit acknowledgment, multi-contact escalation, dialer access and honest nonresponse |
| Android/OEM stops location work | Stale tracking presented as live | Native lifecycle handling, dated/accurate snapshots, representative device tests and force-stop disclosure |
| GPS cannot be obtained quickly | SOS never leaves device | Submit unknown/last-known position immediately and enrich later |
| Cancellation races with a notification job | Old emergency alert persists or restarts | Version checks, bounded retries, cancellation updates and durable re-fetch on notification open |
| Cloud/provider outage or exhausted budget | Alerts fail during demand | Queue health, vendor escalation, cost alerts, restore drills, second-adapter design and offline contact actions |
| SMS provider requires registered sender/fixed egress | Integration fails late | Procurement and carrier tests before launch architecture is locked |
| Inappropriate cross-border processing/recording | Legal/user harm | Bangladesh-specific review before real-user hosting and recording; documented vendors/data paths |
| Legacy account or media migration loses ownership | Broken access, leakage, lost records | Inventory, identity mapping, verified backups, staged cutover and rollback |
| Public community reports expose victims/accuse individuals | Abuse and moderation load | Defer; coarse reporting, moderation and policy enforcement before launch |
| AI misinterprets a Bangla emergency | Delay or wrong action | AI optional and outside transmission/dispatch decisions; correction and fallback |
| Team has no ongoing service owner | Unhandled outages/support | Name operational responsibility and fund it before pilot expansion |

## Definition of done for the core flow

Using two test devices and a non-app recipient, demonstrate: adult registration -> accepted trusted link -> time-limited sharing -> journey start -> SOS while location is stale -> server receipt -> push/SMS attempts -> explicit recipient acknowledgment -> continued authorized location updates -> cancellation/resolution -> no further escalation -> sharing revoked -> old recipient link stops working.

Repeat relevant portions with network loss, a worker restart, duplicate commands, the app locked/killed, denied permissions, another signed-in account and an expired/revoked viewer. Retain measured results and known supported conditions. Do not perform emergency drills against real official emergency numbers.
