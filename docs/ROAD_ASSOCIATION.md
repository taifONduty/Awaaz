# Real road association and publication

Implemented 14 October 2026. Approved reports can now be associated with actual edges from the pinned Dhaka GraphHopper graph and published as coarse, fixed-vocabulary community events. Association requires explicit moderator selection; it does not calculate a safety score or change routing.

## Data provenance

`backend/routing/ExportEdges.java` loads GraphHopper 11.1's persisted `BaseGraph` with `DAType.MMAP_RO`, using its stored encoding manager. It exports full `FetchMode.ALL` geometry and forward/reverse edge keys, with car/foot access matching the configured access restrictions and excluding profile subnetworks. It does not rebuild the graph or its routing algorithm.

The verified graph has 100,648 nodes and 128,613 base edges. The spatial registry contains 125,679 traversable edges. Of the 126,116 accessible edges, 437 have point-only quantized geometry, including 1 mm connector edges; those remain in the router but are excluded from spatial report association. Restricted/inaccessible edges are also excluded. Export checksums prove that no source graph file changed.

Current graph version: `dhaka-gh11.1-80d5af1d40ad02d9949c-ee27cfede41c`. OSM data timestamp: `2026-10-13T18:46:47Z`; import timestamp: `2026-10-14T06:19:35Z`. See [geographic routing provenance](REAL_ROUTING_INTEGRATION.md) for engine, input and configuration digests and ODbL attribution. The export adds an artifact digest and individual graph-cache file digests. A graph ID is bound to this exact imported cache: registering different metadata under an existing version is refused, even if a rebuild uses the same OSM/configuration inputs.

## Offline graph registration

```powershell
.\scripts\export-routing-edges.ps1
# From apps/api, using an ignored .env.evidence:
node --env-file=.env.evidence scripts/register-road-graph.ts
```

Set `AWAAZ_EVIDENCE_DATABASE_URL` to a separately provisioned `awaaz_evidence` login and `AWAAZ_ROAD_EDGES_FILE` to the absolute exported `.edges.jsonl` path. Migration `202610140006_road_association.sql` creates the role without login or inheritance; an administrator provisions its password. It has one scoped import RPC and no direct table grants, consumer commands, private submissions or moderator privileges. The loader rejects unsafe role capabilities/memberships/table grants. Remote connections verify TLS, with the existing optional CA bundle; SSL URL overrides are refused. The consumer API's `awaaz_api` role cannot import graphs.

The loader checks engine/input/configuration/cache/artifact digests, metadata, edge keys, coordinates and direction flags. It streams batches of 500 with backpressure, on a single connected client in one transaction. It verifies the artifact digest again while streaming. Database constraints independently validate geometry and accessible directions. Finalization requires the exact expected edge count. Failure rolls back the complete import; an incomplete graph cannot be used by moderation. Ready graphs cannot accept additional edges or changed metadata. A matching registered artifact is an idempotent replay.

## Review and publication

After approval through the [moderation workflow](REPORT_MODERATION.md), the operator requests candidates:

```powershell
node --env-file=.env.moderation scripts/moderation.ts candidates <reportId> <graphVersion>
node --env-file=.env.moderation scripts/moderation.ts publish <reportId> <graphVersion> <edgeId> <requestId>
```

`GET /v1/moderation/reports/:reportId/road-candidates?graphVersion=...` returns at most five actual edges within 35 metres of the private observation. The response includes geometry, distance and direction/mode access, and always says `requiresHumanSelection: true`. Pending reports may be inspected before approval. Rejected, withdrawn, self-authored or unauthorized submissions are unavailable. Several nearby roads are not resolved automatically; a future console must display them for review. Reports without a nearby usable edge cannot be published through this workflow.

`POST /v1/moderation/reports/:reportId/publications` accepts only a request UUID, graph version and integer edge ID. SQL rechecks moderator access, approval, original evidence expiry, real graph readiness and the 35 metre bound. Public text comes from six fixed category templates; original free text, names, reporter identity and precise submitted coordinates are never copied. The public event's position is projected onto the selected edge using UTM 46N, and the consumer feed rounds coordinates to three decimals. `roadSegmentId` includes the exact graph version and undirected edge ID. Direction keys are retained privately for future routing integration.

The operation locks the submission, serializing publication against competing reviewers and withdrawal. New commands return 201, identical retries 200; changed payloads conflict. Publication does not extend the approval expiry. A minimal ledger survives report withdrawal for retry reconciliation, returning `withdrawn` without recreating evidence. Expired receipts return `expired`. The event is removed by the existing report FK cascade.

Each graph tracks an evidence epoch. Publication increments it; event edits/deletion invalidate it transactionally. Future snapshots must match that epoch and expire no later than their earliest contributing evidence expiry. No snapshot consumer is enabled yet; this foundation alone does not make an existing overlay safe to serve.

## Local verification

`scripts/verify-road-association.ts` imports the real graph into a newly owned, marked disposable database and submits synthetic reports. It exercises role isolation, immutable registration/replay, moderator-only candidates, approval and nearby-edge requirements, publication/replay/conflicts, public feed sanitization, withdrawal and evidence-epoch invalidation. The representative synthetic point produced three nearby candidates; explicitly selected edge `102008` was 19.25 metres away. The database is removed after verification. The ignored result file is `.local/routing/association-verification.json`; it explicitly records that the reports are synthetic and safety scoring is disabled.

The Android fixture server now imports this verified registry and seeds its synthetic Community event through the actual review/candidate/publication APIs, replacing direct status/event insertion. Its test-only moderator exists solely in the owned disposable database. Configure `AWAAZ_ROAD_EDGES_FILE` in ignored `.env.test`; the cluster startup script preserves it. This fixture server is bound to loopback and must not be deployed.

Strict TypeScript and formatting checks pass; all 22 existing API checks and 20 database test nodes pass. The integration harness now holds a root-session advisory lock while provisioning cluster-wide roles; two database test processes were also run concurrently and passed. Flutter analysis is clean. The Android integration APK builds in 317.5 seconds, SHA-256 `F1FDB3A9E7229E0DC52951A86E23818802FC4FC0807749648F36C3FCD0153C5D`. All six existing Android cases pass in both process-restart phases, including Community publication, withdrawal, receipt recovery and native screen-off monitoring. No Android cases were added. These tests use synthetic accounts/incidents and emulated GPS, not physical-phone or hosted-Auth proof.

The first Android attempt was covered by an emulator System UI ANR dialog; screenshot/foreground guards refused to report success. After inspecting and dismissing that dialog, both phases passed on the same emulator and APK with fresh disposable fixtures. The runner now rejects an existing ANR dialog before changing test state. This does not establish a fix for emulator/host responsiveness. [Reviewed Android Community screenshot](ui-redesign/road-association-community-android.png).

After the cycle, the unchanged regular preview APK (`1A6E89D618996D9CFEEC150CFCC76EBB119E2A0F0C4D93B4B9AC04C0C1666A09`) was restored. Its live Google Maps tiles were reviewed; the native trip monitor was absent, and API/database/router readiness passed. The fixture API remains on loopback 3031 and GraphHopper on 8989. [Restored preview screenshot](ui-redesign/road-association-preview-android.png). These services and this emulator are development infrastructure.

## Remaining release work

An operator console, appeals, independent moderation quality review and retention/erasure policy remain unfinished. Report-location uncertainty and transport applicability need explicit handling before automated association. Public source refresh needs an operated, sustainable OSM pipeline. Risk snapshots, duplicate/independent-evidence handling, an evaluated GraphHopper risk extension and ML labels/evaluation are still pending. Routing continues to report unknown safety coverage. Hosted Auth and physical-device validation remain separate gates.
