# Expiring reviewed-evidence snapshots

Implemented 14 October 2026 after [real-road association](ROAD_ASSOCIATION.md). Migration `202610140007_evidence_snapshots.sql` adds versioned, expiring evidence aggregation and fixes public coordinate precision at the database boundary. The subsequent [reported-route integration](REPORTED_ROUTE_INTEGRATION.md) consumes snapshots behind an experimental flag; geographic routing continues to report unknown safety.

## Baseline semantics

Only live publications with a matching original reviewed submission, approval record, category, observation time, graph version and edge association contribute. The effective expiry is the earliest of publication, event and approval expiry. Original observation time drives decay; repost/publication time cannot reset it.

The transparent experimental baseline uses exponential half-lives: accident 30 minutes; theft/harassment/other one hour; obstruction three hours; lighting six hours. Each contributor has at most one unit of combined influence on an edge across categories. Within an edge/category, incident observations separated by at most 30 minutes are conservatively grouped; lighting and obstruction observations share a group over the live window. A group contributes its strongest capped observation, rather than adding potentially correlated witnesses. Stable ordering includes the unique event ID, preventing equal timestamps from splitting a group nondeterministically.

Total attention is capped at four units and mapped with `x / (1 + x)`. Separate incident and environmental indices and category counts are retained. These are policy-defined evidence indices, not probabilities, independent incident counts, exposure-adjusted rates or calibrated safety metrics. The database column now says `event_cluster_count`; confidence remains zero and uncertainty one. Half-lives/caps/grouping require independent pilot evaluation. No model has been trained.

Unobserved edges use the explicit default `{evidenceIndex: null, confidence: 0, uncertainty: 1, eventClusterCount: 0}`. Sparse storage keeps only observed edges; the registered edge count and default define the rest. A bounded edge-probe RPC returns this same unknown state for a real registered edge without evidence. An empty snapshot is all unknown, never all safe. The representative Dhaka fixture stores one evidence row for 125,679 registered edges.

## Consistency, privacy and lifetime

A snapshot has an opaque UUID, scoring version `reviewed-decay-v1`, exact graph metadata digest and evidence epoch. The builder locks the graph and serializes builders for that version. Publication/edit/withdrawal epoch updates invalidate the snapshot transactionally. Reads check the current locked graph epoch/digest and wall-clock expiry; they do not trust an exported file as a revocation oracle. The maximum snapshot lease is two minutes, shortened to its earliest contributing expiry. A recent matching build may be reused for 30 seconds.

Supabase RLS excludes stale/expired snapshots and their edge rows. Eligible snapshot IDs are computed once per statement, avoiding a private lookup for every edge. Public coordinates are rounded to three decimals by a trigger on every writer, and direct authenticated reads of the centroid column are revoked. Original precise submission coordinates remain private and are erased on withdrawal through the existing workflow. Snapshots/exported artifacts contain no reporter ID, original narrative or precise report point; contributor identities are used transiently for capping inside SQL.

The restricted `awaaz_evidence` worker can build/prune/export through scoped RPCs and cannot read source tables or consumer commands. The API can read snapshots but cannot build them. Worker role checks inspect catalog OIDs, so checking an inaccessible Auth table does not require granting Auth-schema access. Expired derived database snapshots are removed in bounded batches after five minutes; source reports and moderation ledgers retain their separately documented erasure/retention semantics.

## Worker and artifact contract

From `apps/api`, using an ignored `.env.evidence`:

```powershell
node --env-file=.env.evidence scripts/build-evidence-snapshot.ts
```

Configure `AWAAZ_EVIDENCE_DATABASE_URL` with the separately provisioned worker login, `AWAAZ_EVIDENCE_GRAPH_VERSION` with the registered graph ID and `AWAAZ_EVIDENCE_OUTPUT_DIR` with an absolute private output directory. Remote database TLS is verified; SSL URL overrides and unsafe worker privileges are refused.

The worker writes sparse JSON Lines with a metadata header, explicit unknown default, source graph-file digests and observed edge records. Bounded pages are checked for stable metadata, ascending IDs, exact counts, valid flags/indices/categories and expiry. A final live check precedes file promotion; partial failures remove only the newly created partial artifact. A SHA-256 manifest accompanies the output. [Supervised refresh and bounded artifact retention](EVIDENCE_WORKER.md) now provide the persistent worker implementation; actual deployment/monitoring remain unconfigured. Routing must recheck live epoch/expiry before and after using an artifact; an already exported file is not proof that evidence is still current.

`GET /v1/routing/evidence/status` reports availability/counts for the configured graph and always returns `safetyAssessment: unknown`. It does not expose a safety percentage or enable risk routing. The Android fixture server refreshes synthetic snapshots every minute with one in-flight job; shutdown waits for it and restores/discards its temporary worker-role connection safely. Production worker supervision and hosted credentials are not configured.

## Verification and next work

The extended real-graph disposable-database diagnostic checks worker isolation, sparse known/unknown states, separate evidence dimensions, artifact export, coarse stored coordinates, denied direct coordinate reads, withdrawal invalidation through API/RLS, empty state and expired-read refusal. It uses synthetic reports on actual graph geometry and drops its owned database. The initial SQL dimension handling was corrected so an absent category remains null; no incident evidence is inferred from a lighting-only report.

Strict TypeScript/formatting checks pass, alongside all 22 existing API checks and 20 database test nodes. All six existing Android cases pass in both restart phases against the snapshot-enabled fixture backend, including publication/withdrawal, receipt recovery and native screen-off monitoring. The unchanged integration APK was reused; no Android cases or application UI changes were added. This is emulator/local-SQL evidence with synthetic identities/incidents, not hosted Auth, real incident calibration or physical-device proof.

The regular Google Maps preview was restored after the cycle. API and street-router readiness passed; the refreshed snapshot had zero evidenced edges after fixture withdrawal and continued to report unknown safety. The native trip monitor was absent. The current ignored screenshot is `.local/android-evidence/101-normal-preview-after-snapshots.png`.

The subsequent [GraphHopper extension](EVIDENCE_ROUTING_ENGINE.md) and [API/mobile integration](REPORTED_ROUTE_INTEGRATION.md) preserve access constraints, handle virtual snap edges, use an immutable snapshot, validate live leases and compare A* with Dijkstra. Remaining work includes independent moderation/calibration checks, report-location accuracy and transport applicability, and actual deployment/monitoring of the [implemented refresh/retention worker](EVIDENCE_WORKER.md). Fastest routing and safety uncertainty remain explicit. Hosted Auth, physical-device/OEM validation, sharing and emergency delivery remain separate release work.
