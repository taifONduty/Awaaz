param(
  [string]$PgBin = 'C:\Users\User\.codex\toolchains\postgres-17.11\pgsql\bin',
  [int]$Port = 54329
)
$ErrorActionPreference = 'Stop'
if ($Port -lt 1024 -or $Port -gt 65535) { throw 'Use a non-privileged test port' }
$workspaceRoot = Split-Path $PSScriptRoot -Parent
$testRoot = Join-Path $workspaceRoot '.local\backend-postgres'
$clusterPath = Join-Path $testRoot 'data'
$adminFile = Join-Path $testRoot 'admin.password'
$apiFile = Join-Path $testRoot 'api.password'
if (-not (Test-Path -LiteralPath (Join-Path $PgBin 'initdb.exe'))) { throw 'PostgreSQL binaries not found; supply -PgBin' }
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
foreach ($passwordFile in @($adminFile,$apiFile)) {
  if (-not (Test-Path -LiteralPath $passwordFile)) {
    [Convert]::ToHexString([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32)).ToLowerInvariant() |
      Set-Content -LiteralPath $passwordFile -Encoding ascii
  }
}
if (-not (Test-Path -LiteralPath (Join-Path $clusterPath 'PG_VERSION'))) {
  & (Join-Path $PgBin 'initdb.exe') -D $clusterPath -U postgres -E UTF8 --locale=C -A scram-sha-256 --pwfile=$adminFile
  if ($LASTEXITCODE -ne 0) { throw 'Test cluster initialization failed' }
}
& (Join-Path $PgBin 'pg_ctl.exe') -D $clusterPath status *> $null
if ($LASTEXITCODE -ne 0) {
  & (Join-Path $PgBin 'pg_ctl.exe') -D $clusterPath -l (Join-Path $testRoot 'postgres.log') -o "-h 127.0.0.1 -p $Port -c cluster_name=awaaz-integration-only" -w -t 60 start
  if ($LASTEXITCODE -ne 0) { throw 'Test cluster startup failed; inspect .local/backend-postgres/postgres.log' }
}
$startupOptions = Get-Content -LiteralPath (Join-Path $clusterPath 'postmaster.opts') -Raw
$postmasterInfo = Get-Content -LiteralPath (Join-Path $clusterPath 'postmaster.pid')
if ($startupOptions -notmatch 'cluster_name=awaaz-integration-only' -or [int]$postmasterInfo[3] -ne $Port) {
  throw 'Existing cluster is not the expected integration-only instance/port; no test environment was written'
}
$adminPassword = (Get-Content -LiteralPath $adminFile -Raw).Trim()
$apiPassword = (Get-Content -LiteralPath $apiFile -Raw).Trim()
$testEnvironment = @"
# Synthetic localhost integration cluster only. Never point these at production.
AWAAZ_TEST_ADMIN_URL=postgresql://postgres:$adminPassword@127.0.0.1:$Port/postgres
AWAAZ_TEST_API_PASSWORD=$apiPassword
"@
$environmentPath = Join-Path $workspaceRoot 'apps\api\.env.test'
$routingOptions = if (Test-Path -LiteralPath $environmentPath) {
    Get-Content -LiteralPath $environmentPath | Where-Object { $_ -match '^AWAAZ_(GRAPHHOPPER_URL|ROUTING_MANIFEST|ROAD_EDGES_FILE|ROUTING_JAVA|EXPERIMENTAL_EVIDENCE_ROUTING|PLACE_CATALOG_FILE|EVIDENCE_OUTPUT_DIR)=' }
} else { @() }
@($testEnvironment) + @($routingOptions) | Set-Content -LiteralPath $environmentPath -Encoding utf8
Write-Output "Local test Postgres is available on 127.0.0.1:$Port. Test credentials are in the ignored apps/api/.env.test."
