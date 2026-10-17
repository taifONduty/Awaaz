# GraphHopper evidence weighting extension

Implemented and locally verified 14 October 2026. `backend/routing/EvidenceRouter.java` and `apps/api/src/evidence_router.ts` provide a private routing worker and a database-gated caller. The subsequent [reported-route integration](REPORTED_ROUTE_INTEGRATION.md) connects this extension to the API and mobile picker behind an experimental flag. All app routes retain unknown safety assessment.

## Cost and heuristic

The extension wraps GraphHopper 11.1's configured `CustomWeighting` through its supported `createWeightingFactory` hook. It uses flexible routing with CH/LM disabled, the existing car/foot profiles and ferry snap prevention. The source graph loads read-only; all graph-file digests must match the evidence artifact. [GraphHopper weighting documentation](https://github.com/graphhopper/graphhopper/blob/master/docs/core/weighting.md).

For a traversed edge, the experimental policy is:

```text
cost = base_static_time_cost * (1 + 2 * reviewed_evidence_index)
```

An unobserved edge has no added evidence penalty and remains unknown. This optimization can prefer roads with fewer reviewed observations; it does not establish that they are safer. Reporting bias, missing coverage and the uncalibrated policy remain release concerns. The snapshot/index semantics are described in [Evidence snapshots](EVIDENCE_SNAPSHOTS.md).

Base road-access restrictions and infinite weights remain intact. Turn weights, turn travel time and physical travel-time estimates delegate to the original weighting. Added edge cost is nonnegative, so the original minimum weight per distance remains an admissible heuristic bound. The engine's weighting version is `reviewed-time-v1-alpha2`; every response says `safetyAssessment: unknown`.

## Virtual edges and request consistency

GPS origin/destination snapping creates virtual fragments. Search can expose them through an iterator wrapper, whereas path extraction can expose the concrete virtual-edge state. The first implementation checked only the concrete class and missed the wrapped search case. The fix detaches only virtual edge IDs, recovers the original stored edge key and applies its index to the fragment. Ordinary edges do not allocate copies on every expansion. Zero-length geometry intervals from connector edges are permitted without inventing spatial evidence.

Each search owns one immutable snapshot map; no global overlay changes underneath it. Artifact UUIDs/digests, graph-file hashes, format, scoring version, expiry and edge bounds are validated. The digest is checked again after parsing. The caller validates returned geometry, edge intervals, endpoint snap distances and distance consistency.

`EvidenceRoutingCoordinator` reads the live database state before export and checks it again after search. Withdrawal or publication changing the epoch during calculation rejects the result. An exported artifact is never a revocation oracle. The experimental API adapter invokes this coordinator and rechecks evidence while capturing route coverage.

## Worker boundary

The Java worker has no HTTP listener. Its bounded JSON-lines protocol is carried over an owned child process, with a 512 MiB heap and two processors. The Node adapter pins the engine checksum, uses explicit argument arrays, hides the helper window, passes no database/Auth/Maps credentials, validates the startup handshake and correlates responses by request UUID. At most two requests may be pending. Canceled/late responses cannot satisfy another request. Library stderr is drained without logging private coordinates; worker errors expose fixed codes. Process failure rejects pending requests and stops only the owned child.

## Verification

Run from `apps/api` with the existing marked local cluster and verified graph export:

```powershell
node --env-file=.env.test scripts/verify-evidence-routing.ts
```

The diagnostic imports the real graph into an owned disposable database, submits/reviews/publishes synthetic observations on actual route edges and exports a real snapshot. Six car/walking A* costs match Dijkstra within the stated numerical tolerance. A corridor fixture changes the selected car route: baseline cost `276.71433141526154`; weighted optimum `354.481411923449`, distance about 3.15 km and static time estimate 355 seconds. A single reported short segment previously changed cost but did not justify a detour; the policy was not increased merely to force a route change.

The virtual-origin check uses stored edge `102008`. Its clipped fragment's cost changes from about 19.2338 to 38.4675, matching `1 + 2 * index` within `1e-6`, while travel time stays identical. A wrong artifact digest is refused. A publication withdrawal deliberately injected after search causes the coordinator to refuse the result. The diagnostic drops its database, stops its child and writes ignored evidence to `.local/routing/evidence-routing-verification.json`.

Strict TypeScript and formatting checks pass, alongside all 22 existing API checks. No mobile source or APK changed and Android cases were not rerun for this isolated engine increment. The prior emulator proof remains the mobile baseline; weighted-route mobile behavior is still unverified.

## Subsequent integration

The [reported-route integration](REPORTED_ROUTE_INTEGRATION.md) now exposes fastest versus reviewed-report choices, deduplicates identical paths and binds graph/snapshot provenance and plan expiry to the approved native corridor. It preserves unknown safety assessment without silently changing an active baseline. Independent calibration, hosted Auth, physical-device validation, sharing and emergency delivery remain unfinished.
