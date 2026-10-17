param([string]$PgBin = 'C:\Users\User\.codex\toolchains\postgres-17.11\pgsql\bin')
$ErrorActionPreference = 'Stop'
$workspaceRoot = Split-Path $PSScriptRoot -Parent
$clusterPath = Join-Path $workspaceRoot '.local\backend-postgres\data'
$control = Join-Path $PgBin 'pg_ctl.exe'
if (-not (Test-Path -LiteralPath $control)) { throw 'PostgreSQL binaries not found; supply -PgBin' }
if (-not (Test-Path -LiteralPath (Join-Path $clusterPath 'PG_VERSION'))) {
  Write-Output 'No local Awaaz test cluster exists.'
  return
}
$optionsFile = Join-Path $clusterPath 'postmaster.opts'
if (-not (Test-Path -LiteralPath $optionsFile) -or
  (Get-Content -LiteralPath $optionsFile -Raw) -notmatch 'cluster_name=awaaz-integration-only') {
  throw 'Refusing to stop a cluster without the integration-only startup marker'
}
& $control -D $clusterPath status *> $null
if ($LASTEXITCODE -ne 0) { Write-Output 'Local Awaaz test Postgres is already stopped.'; return }
& $control -D $clusterPath -m fast -w -t 20 stop
if ($LASTEXITCODE -ne 0) { throw 'Test cluster shutdown failed' }
Write-Output 'Local Awaaz test Postgres stopped. Data and synthetic credentials were preserved.'
