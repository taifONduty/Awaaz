$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path $PSScriptRoot -Parent
$taskRouting = Join-Path $taskRoot '.local\routing'
$taskManifestPath = Join-Path $taskRouting 'manifest.json'
$taskManifest = Get-Content -LiteralPath $taskManifestPath -Raw | ConvertFrom-Json
$taskStarted = Get-Content -LiteralPath (Join-Path $taskRouting 'process.json') -Raw | ConvertFrom-Json
if ($taskManifest.graphVersion -ne $taskStarted.graphVersion) { throw 'Manifest does not describe the started graph' }
$taskWorker = Get-CimInstance Win32_Process -Filter "ProcessId=$($taskStarted.pid)"
$taskCache = Join-Path $taskRouting $taskManifest.graphVersion
if (-not $taskWorker -or $taskWorker.CommandLine -notlike "*$taskCache*") { throw 'The owned routing process is not running' }
$taskListener = Get-NetTCPConnection -LocalPort 8989 -State Listen -ErrorAction Stop
if ($taskListener.OwningProcess -ne $taskStarted.pid) { throw 'Router HTTP port belongs to another process' }
$taskInfo = Invoke-RestMethod -Uri http://127.0.0.1:8989/info -TimeoutSec 5
if ($taskInfo.version -ne '11.1' -or -not $taskInfo.import_date -or $taskInfo.profiles.name -notcontains 'car' -or $taskInfo.profiles.name -notcontains 'foot') { throw 'Unexpected routing service metadata' }
$taskManifest | Add-Member -NotePropertyName importDate -NotePropertyValue $taskInfo.import_date -Force
$taskManifest | Add-Member -NotePropertyName graphBounds -NotePropertyValue $taskInfo.bbox -Force
$taskManifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $taskManifestPath -Encoding utf8
Write-Output "Ready: $($taskManifest.graphVersion), GraphHopper 11.1 car/foot, import $($taskInfo.import_date). No safety evidence is attached."
