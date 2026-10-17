# Backend verification — 12 October 2026

## Receipt reconciliation increment — 13 October 2026

The fourth migration adds authenticated, account-scoped receipt reconciliation while retaining only the two exposed restricted-role dispatchers. The legacy dispatcher is not executable by that role, and readiness checks require this boundary. The current database run passes **18 scenarios (19 nodes)**, including old/withdrawn receipts, foreign-request denial and minimal receipt payloads. HTTP/adapter tests remain **19 passing**; type/format checks pass and OpenAPI has been regenerated. [Full reporting contract](LOCATION_REPORT_COMPOSER.md). Older counts below describe the earlier three-migration increment.

## Result

The account/Circle/community increment passes formatting and strict TypeScript checks, **19 HTTP/adapter/security test cases**, and **17 database integration scenarios** against actual PostgreSQL/PostGIS. Node's database runner reports 18 passing test nodes because it also counts the enclosing test. There are no skipped cases in these runs.

The generated OpenAPI document describes the server's runtime schemas. The local checks do not require cloud credentials. No fresh Supabase project has been configured or deployed; Flutter remains on demo repositories.

## Verified environment

| Component | Version |
| --- | --- |
| Node.js | 24.19.0 |
| pnpm | 11.25.0 |
| Fastify | 5.12.5 |
| Supabase JavaScript SDK | 2.117.3 |
| TypeScript | 7.0.2 |
| node-postgres / types | 8.23.1 |
| Fastify CORS / Swagger | 11.3.1 / 9.9.2 |
| Prettier | 3.9.10 |
| PostgreSQL | 17.11 |
| PostGIS | 3.6.2 |

Dependencies are resolved through the checked-in API lockfile. The production API checks Auth online and uses the dedicated restricted database role. The integration harness substitutes synthetic Auth identities only inside test code; no development authentication bypass was added to the runtime.

## HTTP and adapter evidence

The tests cover online Auth requests through the real SDK with a mocked transport; invalid-token rejection; email confirmation distinguished from phone confirmation; protection of all authenticated routes; ownership binding; parameterized SQL; strict types and body allowlists; response allowlists; pilot bounds and observation ages; replay/conflict behavior; bounded pagination/viewports; configured CORS; readiness versus liveness; sanitized storage errors; and logs that omit private names, IDs, bodies and tokens.

A shared-IP test verifies that each of two users can make twenty report attempts, the first user's report limit returns 429 without consuming the other's allowance, and the account limit also executes. Health remains independent of an account's exhausted allowance. Tests also reject connection-string options that could replace the verified remote TLS configuration, and check stable, scoped invitation-secret derivation.

These are functional transport tests, not a penetration test, load benchmark or full accessibility/device assessment.

## Real database scenarios

The harness applies the test Auth bootstrap and all three real migrations to a newly created disposable database, then queries through the restricted API role and through simulated client roles.

1. Six concurrent distinct Circle creations respect the five-owned-Circle cap. Closure frees capacity but does not reset the ten/day creation quota.
2. The twentieth invited member cannot partially join a full Circle. Removing a member frees a slot; invitation creation still respects its twenty/day quota.
3. PostGIS functions/operators run, the migrations apply, and the API role cannot read Auth/raw reports or directly insert application data. Client roles cannot execute scoped commands.
4. Own-profile RLS and strict adult attestation reject forged identities and direct client writes.
5. Six concurrent retries of one Circle command produce one Circle and charge one quota unit; changed payload conflicts.
6. Only the intended account with the correct secret accepts; retries are stable, hashes remain hidden and strangers cannot read the Circle.
7. Expired invites fail, non-owners cannot invite, unknown recipient accounts return 404, and expired invitations leave the inbox.
8. Secret rotation prevents regeneration of an old creation token; previously issued tokens still require explicit expiry/revocation.
9. A concurrent accept/revoke race ends revoked, and a copied or previously accepted token cannot rejoin afterward.
10. Leaving and closing are idempotent; owners cannot silently leave; closure revokes access.
11. The database rejects an unconfirmed phone even when a deliberately dishonest test transport marks it verified.
12. Eight simultaneous report retries create one report/receipt and charge once; altered content conflicts.
13. Private keyset pages isolate users. Strangers cannot withdraw another report. Published-event reads filter expiry, round coordinates and hide submission/reporter IDs.
14. Withdrawal atomically deletes private and linked public payloads. An identical replay returns withdrawn and cannot recreate them.
15. Twenty report creations/withdrawals exhaust a durable daily quota; rejected attempts roll back without corrupting the counter.
16. Outbox and retry metadata are isolated; unobserved risk edges must use null risk/zero confidence/full uncertainty rather than invented zero risk.
17. Deleting a synthetic Auth user cascades their profiles, owned Circles, memberships, reports and private retry/quota records while preserving unrelated owners.

Database deletion cascades are tested. A consumer-facing account-erasure endpoint and real Auth session revocation are not yet implemented.

## Reproduce

From the repository root:

```powershell
./scripts/start-test-postgres.ps1
./scripts/check.ps1 -BackendOnly -DatabaseTests
./scripts/stop-test-postgres.ps1
```

The scripts retain the ignored local cluster and synthetic credentials. The harness only drops its newly generated `awaaz_test_<random>` database. It refuses a non-local cluster or one without the `awaaz-integration-only` marker.

For isolated API commands see [backend setup](../backend/README.md). `pnpm openapi` builds a documentation-only server that rejects all tokens and never connects to Auth or SQL; this is not a usable backend or an authentication mode for development.

## Toolchain provenance

Docker was installed but its daemon could not be started in this session. Verification therefore used a portable Windows PostgreSQL installation with the official PostGIS core binaries and dependencies. No system service, firewall change or global PATH change was required.

- PostgreSQL binaries: [official PostgreSQL Windows downloads](https://www.postgresql.org/download/windows/) and [EDB binary downloads](https://www.enterprisedb.com/download-postgresql-binaries), release file `postgresql-17.11-3-windows-x64-binaries.zip`.
- Recorded local download SHA-256: `4B8DB0930C38F6EF845DB919551DEDDA3B6B845AEB0927B3D79A6E8E9E4537CF`.
- PostGIS source: [official Windows release instructions](https://postgis.net/documentation/getting_started/install_windows/released_versions/) and [the OSGeo release archive](https://download.osgeo.org/postgis/windows/pg17/), file `postgis-bundle-pg17-3.6.2x64.zip`.
- The core extension, versioned SQL, projection database and DLL dependencies were extracted using HTTP ZIP ranges and per-entry CRC checks. Installed file SHA-256 records are at `C:\Users\User\.codex\toolchains\postgres-17.11\postgis-core-provenance.json`.
- The recorded hashes document local provenance; they are not a publisher signature. Runtime tests query the installed extension version and exercise actual PostGIS geography operations.

## Remaining release evidence

A disposable fresh Supabase project must verify the actual Auth/OTP/revocation flows, pooler role login and server TLS, PostgREST column grants/RLS and any future Realtime subscriptions. Hosted database defaults can differ from the minimal local test bootstrap.

Flutter Auth/API wiring, account blocking/erasure, moderation/audits/appeals, sensitive-data retention, consented journey sharing, SOS transactions/workers/provider receipts, production maps/routing, native screen-off monitoring, restore drills, load/soak tests and a Dhaka pilot remain necessary. No message or live emergency alert has been sent, no production risk overlay has been generated, and this work does not establish real-world safety or notification delivery.
