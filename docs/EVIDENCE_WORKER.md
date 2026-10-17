# Supervised evidence refresh and artifact retention

Implemented 14 October 2026. `EvidenceRefreshWorker` runs the restricted snapshot builder/exporter continuously, instead of depending on the Android fixture's former one-minute timer. The fixture now uses this same component through an explicitly test-only scoped role connection. The production CLI connects directly as `awaaz_evidence`; it accepts neither API-role nor administrator database credentials.

## Runtime contract

The worker refreshes 30 seconds after a completed cycle. Concurrent cycle requests share one promise. A session-level advisory lock for the configured graph permits one refresh/export/cleanup leader in that database; a competing instance reports standby. SQL's existing build transaction locks still protect snapshot capture. The connection has an eight-second statement timeout and two-second lock timeout. Worker pools use two connections. Connections are reset/discarded correctly, and the leader lock is released before a connection returns to the pool.

Database/build/export failures produce a fixed unavailable state and exponential retry delay, capped at 30 seconds. The worker does not invent evidence or extend a lease. It validates live snapshot state after export and again after retention work. API routing continues to check database epoch/expiry around each calculation; an exported file or worker health record is never proof that a withdrawn snapshot remains valid.

SIGINT/SIGTERM request graceful shutdown: no next cycle starts, pending work completes, directory handles close and the final health record says stopped. A trusted supervising Node parent can use the owned IPC message `awaaz.evidence.stop` on Windows; IPC disconnect also stops the worker. There is no network stop endpoint. The Windows diagnostic verified this IPC path, not Linux service-manager signals. Fatal configuration or health-file failures exit nonzero for a supervisor to handle.

## Private health and retention

Health is promoted atomically and contains graph/snapshot identifiers, timestamps, status, failure count and bounded cleanup counts; it contains no credentials, reporter identities, narratives or route coordinates. Use a separate health file for each replica sharing an artifact directory. `evidence:health` checks readiness, including a heartbeat no older than 60 seconds and a still-live snapshot. `--live` checks process heartbeat instead, allowing standby or a worker that is retrying an outage. A stale or stopped record fails. An exited `--once` job deliberately leaves a stopped record.

Retention scans a configured absolute, canonical directory without following a symlink/junction. It removes at most 50 artifacts per cycle while scanning at most 1,000 entries, preserving its directory cursor between cycles. A paired manifest may be removed with its artifact, so this is an artifact cap, not a cap of 50 individual unlink operations. Completed JSONL must have the reserved UUID name, matching graph/id header and a valid maximum two-minute lease; deletion waits at least five minutes after expiry. Orphan manifests and reserved UUID crash partials wait fifteen minutes. Partials also require fifteen minutes since their last write, allowing removal of an empty file left by an interrupted export.

Current leases, foreign graph artifacts, malformed completed files, unrelated files, links and multiply-linked files remain untouched. Deletion is shallow and checked again before unlink; no recursive deletion occurs in the runtime worker. Unexpected permission/I/O failures make the cycle unavailable. Malformed/unrecognized files require operator review rather than automatic deletion. Storage quotas and alerting still need deployment configuration.

JSONL and manifest exports use private files and atomic promotion. On POSIX, exports request mode 0640; new artifact directories request 0770, subject to umask. For separate API/worker OS users, provision a shared routing group and a private setgid directory (2770) so both can read artifacts and atomically replace files. Health files request 0600. Windows permission bits do not establish ACL protection: provision and verify the actual ACL on the deployment volume. No deployment permissions are claimed verified here.

## Configuration and supervision

Copy `apps/api/.env.evidence.example` to ignored `.env.evidence`. Supply the restricted worker database URL, confirmed absolute graph manifest, and private absolute output directory. The graph must already be registered through the audited import workflow. Optional graph-version configuration must match the manifest. Remote database TLS uses the existing verified-CA contract. Do not put Auth, invitation or Android Maps credentials in this worker environment.

Configure `AWAAZ_EVIDENCE_OUTPUT_DIR` to the same directory in the route API environment. The API's Java worker now accepts this explicit location; its default local path remains `.local/evidence`. Production should use a distinct directory for each graph generation. The worker never imports a graph or updates graph files during refresh.

From `apps/api`:

```powershell
pnpm evidence:worker
pnpm evidence:health
pnpm evidence:health --live
# Optional single cycle; this is not a continuously running healthy daemon.
node --env-file=.env.evidence scripts/run-evidence-worker.ts --once
```

`backend/deploy/awaaz-evidence.service` is a reviewable Linux supervision template with a restricted user, explicit paths, restart limits and bounded memory. It is not installed or validated on this Windows host. Its process state does not replace the worker's readiness probe. Review users/groups, Node 24 path, CA, private volume ownership and health monitoring before deployment. The directives follow the [official systemd service reference](https://github.com/systemd/systemd/blob/main/man/systemd.service.xml) and [execution reference](https://github.com/systemd/systemd/blob/main/man/systemd.exec.xml).

No Windows startup task, Linux service, public listener, hosted project or production credentials were installed/configured by this increment.

## Verification

Strict TypeScript and formatting checks pass. All 23 API cases and 20 real database test nodes pass. Only one case was added, covering the consequential deletion boundary: current/foreign/malformed/unrelated/hardlinked files survive, stale partials and completed pairs are removed within the bounds, scanning resumes, and a junction redirect is refused.

`scripts/verify-evidence-worker.ts` imports the actual 125,679-edge graph into an owned disposable database. It temporarily provisions a generated credential for the test cluster's otherwise unconfigured worker role, verifies direct restricted LOGIN and denied Auth-table access, then restores NOLOGIN/no password and drops its owned database. Concurrent cycles coalesce; an externally held leader lock produces standby, release allows readiness, revoking a scoped function produces unavailable, and restoring it recovers. Expired leases/stale heartbeat fail readiness. The actual CLI runs as an owned child, becomes ready, stops gracefully through IPC with exit zero, writes stopped health and releases its session lock. The database has zero observations, explicitly null safety coverage and unknown defaults: this verifies operational behavior, not incident scoring calibration. Ignored evidence: `.local/routing/evidence-worker-verification.json`.

The updated fixture worker reports ready with zero failures, and its real health/readiness commands both pass. Successive snapshots/health timestamps confirm the refresh loop continues. A consented emulated origin and selected map pin return Fastest (5 min / 3.2 km, observations on 54% of geometry) and Fewer reported issues (6 min / 2.9 km, observations on 2%) through this new refresh path. Selecting the second choice changes actual returned geometry. English/Bangla installed review preserves explicit test-report labeling and unknown safety. The percentages describe reviewed observations, not safety probability. The app is returned to English Explore with no native trip service, while the fixture routing worker is ready.

Installed evidence: [worker-backed choices](ui-redesign/worker-route-choices-android.png), [selected reported path](ui-redesign/worker-reported-selected-android.png), [Bangla choices](ui-redesign/worker-route-choices-bangla-android.png). Mobile source/APK and native monitor logic are unchanged in this backend increment; the six-case Android restart suite is not presented as a new run. Hosted worker/TLS/pooler checks, production service installation, load/soak and storage monitoring, calibration, and physical-device startup/background validation remain release gates.
