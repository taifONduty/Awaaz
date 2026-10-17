param([string]$Jdk = (Join-Path $env:USERPROFILE '.codex\toolchains\jdk-21.0.12.1\jdk-21.0.12.1+1'))
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path $PSScriptRoot -Parent
$taskRouting = Join-Path $taskRoot '.local\routing'
$taskJava = Join-Path $Jdk 'bin\java.exe'
$taskManifest = Get-Content -LiteralPath (Join-Path $taskRouting 'manifest.json') -Raw | ConvertFrom-Json
$taskJar = Join-Path $taskRouting 'graphhopper-web-11.1.jar'
$taskOsm = Join-Path $taskRouting 'dhaka.osm'
$taskConfig = Join-Path $taskRoot 'backend\routing\graphhopper.yml'
foreach ($taskFile in @(@($taskJar,$taskManifest.engineSha256), @($taskOsm,$taskManifest.extractSha256), @($taskConfig,$taskManifest.configSha256))) {
  if ((Get-FileHash -LiteralPath $taskFile[0] -Algorithm SHA256).Hash.ToLowerInvariant() -ne $taskFile[1]) { throw 'Routing artifact changed; prepare a new graph version before starting' }
}
if (-not (Test-Path -LiteralPath $taskJava)) { throw 'JDK 21 is required' }
if (Get-NetTCPConnection -LocalPort 8989,8990 -State Listen -ErrorAction SilentlyContinue) { throw 'Routing ports are occupied; inspect their owner instead of replacing it' }
$taskCache = Join-Path $taskRouting $taskManifest.graphVersion
$taskArguments = @('-Xmx1024m','-XX:ActiveProcessorCount=2',"-Ddw.graphhopper.datareader.file=$taskOsm","-Ddw.graphhopper.graph.location=$taskCache",'-jar',$taskJar,'server',$taskConfig)
$taskProcess = Start-Process -FilePath $taskJava -ArgumentList ($taskArguments | ForEach-Object { '"' + $_ + '"' }) -WorkingDirectory $taskRouting -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $taskRouting 'router.log') -RedirectStandardError (Join-Path $taskRouting 'router-errors.log')
@{pid=$taskProcess.Id; graphVersion=$taskManifest.graphVersion; startedAt=(Get-Date).ToUniversalTime().ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $taskRouting 'process.json') -Encoding utf8
Write-Output "GraphHopper PID $($taskProcess.Id) starting on loopback 8989. Inspect router.log and /info for readiness; process creation is not readiness."
