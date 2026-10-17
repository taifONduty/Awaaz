$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path $PSScriptRoot -Parent
$taskRouting = Join-Path $taskRoot '.local\routing'
$taskStarted = Get-Content -LiteralPath (Join-Path $taskRouting 'process.json') -Raw | ConvertFrom-Json
$taskCache = Join-Path $taskRouting $taskStarted.graphVersion
$taskWorker = Get-CimInstance Win32_Process -Filter "ProcessId=$($taskStarted.pid)"
if (-not $taskWorker) { Write-Output 'Owned router is already stopped'; exit 0 }
if ($taskWorker.CommandLine -notlike "*$taskCache*" -or $taskWorker.CommandLine -notlike '*graphhopper-web-11.1.jar*') { throw 'Saved PID now belongs to another process; refusing to stop it' }
Stop-Process -Id $taskStarted.pid -ErrorAction Stop
Write-Output "Stopped the owned GraphHopper process $($taskStarted.pid). Immutable graph data is retained."
