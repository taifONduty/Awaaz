$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path $PSScriptRoot -Parent
$taskRouting = Join-Path $taskRoot '.local\routing'
$taskManifestPath = Join-Path $taskRouting 'manifest.json'
$taskManifest = Get-Content -LiteralPath $taskManifestPath -Raw | ConvertFrom-Json -DateKind String
if ($taskManifest.graphVersion -notmatch '^dhaka-gh11\.1-[0-9a-f]{20}-[0-9a-f]{12}$' -or -not $taskManifest.importDate) { throw 'Confirm the pinned routing graph first' }
$taskJar = Join-Path $taskRouting 'graphhopper-web-11.1.jar'
if ((Get-FileHash -LiteralPath $taskJar -Algorithm SHA256).Hash.ToLowerInvariant() -ne $taskManifest.engineSha256) { throw 'Engine digest mismatch' }
$taskJavaHome = 'C:\Users\User\.codex\toolchains\jdk-21.0.12.1\jdk-21.0.12.1+1'
$taskGraph = Join-Path $taskRouting $taskManifest.graphVersion
$taskExport = Join-Path $taskRouting ($taskManifest.graphVersion + '.edges.jsonl')
$taskPartial = $taskExport + '.' + [guid]::NewGuid().ToString('N') + '.partial'
# Record graph content digests to prove that the export did not modify its input.
$taskBefore = @(Get-ChildItem -LiteralPath $taskGraph -File | Sort-Object Name | ForEach-Object { [pscustomobject]@{ name=$_.Name; sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() } })
& (Join-Path $taskJavaHome 'bin\java.exe') -Xmx256m '-XX:ActiveProcessorCount=2' --class-path $taskJar (Join-Path $taskRoot 'backend\routing\ExportEdges.java') $taskGraph $taskManifest.importDate $taskPartial
if ($LASTEXITCODE -ne 0) { throw 'Read-only edge export failed; partial output retained for inspection' }
$taskAfter = @(Get-ChildItem -LiteralPath $taskGraph -File | Sort-Object Name | ForEach-Object { [pscustomobject]@{ name=$_.Name; sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() } })
if (($taskBefore | ConvertTo-Json -Compress) -ne ($taskAfter | ConvertTo-Json -Compress)) { throw 'Input graph changed during export' }
$taskCount = 0
foreach ($taskLine in [System.IO.File]::ReadLines($taskPartial)) { $taskCount++ }
if ($taskCount -lt 1000 -or $taskCount -gt 1000000) { throw 'Unexpected edge count' }
# A repeat may replace only the export artifact, never any graph input file.
Move-Item -LiteralPath $taskPartial -Destination $taskExport -Force
$taskExportManifest = [ordered]@{ graphVersion=$taskManifest.graphVersion; importDate=$taskManifest.importDate; sourceTimestamp=$taskManifest.osmBase; engineSha256=$taskManifest.engineSha256; configSha256=$taskManifest.configSha256; extractSha256=$taskManifest.extractSha256; edgesSha256=(Get-FileHash -LiteralPath $taskExport -Algorithm SHA256).Hash.ToLowerInvariant(); edgeCount=$taskCount; format='awaaz-gh-edges-v1'; sourceGraphFiles=$taskAfter }
$taskExportManifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath ($taskExport + '.manifest.json') -Encoding utf8
Write-Output "Read-only export ready: $taskCount edges; graph input checksums unchanged."
