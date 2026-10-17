param()
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path $PSScriptRoot -Parent
$taskRouting = Join-Path $taskRoot '.local\routing'
New-Item -ItemType Directory -Path $taskRouting -Force | Out-Null
$taskJar = Join-Path $taskRouting 'graphhopper-web-11.1.jar'
$taskExpectedJar = '8462f758d9ea49edaded557cec5c687a0a24f004ec371cd4daaeb0534824ea33'
if (-not (Test-Path -LiteralPath $taskJar)) {
  Invoke-WebRequest -Uri 'https://repo.maven.apache.org/maven2/com/graphhopper/graphhopper-web/11.1/graphhopper-web-11.1.jar' -OutFile "$taskJar.partial" -TimeoutSec 180
  if ((Get-FileHash -LiteralPath "$taskJar.partial" -Algorithm SHA256).Hash.ToLowerInvariant() -ne $taskExpectedJar) { throw 'GraphHopper publisher checksum mismatch' }
  Move-Item -LiteralPath "$taskJar.partial" -Destination $taskJar
}
if ((Get-FileHash -LiteralPath $taskJar -Algorithm SHA256).Hash.ToLowerInvariant() -ne $taskExpectedJar) { throw 'GraphHopper publisher checksum mismatch' }
$taskOsm = Join-Path $taskRouting 'dhaka.osm'
$taskQuery = Join-Path $taskRoot 'backend\routing\dhaka.overpass.ql'
if (-not (Test-Path -LiteralPath $taskOsm)) {
  # One bulk extraction, retained locally. Never query Overpass per app user.
  Invoke-WebRequest -Uri 'https://overpass-api.de/api/interpreter' -Method Post -Body @{data=(Get-Content -LiteralPath $taskQuery -Raw)} -UserAgent 'Awaaz-local-routing-development/0.2' -OutFile "$taskOsm.partial" -TimeoutSec 180
  $taskInput = Get-Item -LiteralPath "$taskOsm.partial"
  if ($taskInput.Length -lt 10000 -or $taskInput.Length -gt 268435456) { throw 'Unexpected OSM extract size' }
  # Parse with external entity resolution disabled. Detect error/partial extracts
  # before promoting them to the importer; retain a valid cached extract on rerun.
  $taskSettings = [System.Xml.XmlReaderSettings]::new()
  $taskSettings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
  $taskSettings.XmlResolver = $null
  $taskReader = [System.Xml.XmlReader]::Create("$taskOsm.partial", $taskSettings)
  $taskNodes = 0; $taskWays = 0; $taskRelations = 0; $taskOsmBase = $null
  try {
    while ($taskReader.Read()) {
      if ($taskReader.NodeType -ne [System.Xml.XmlNodeType]::Element) { continue }
      switch ($taskReader.Name) {
        'remark' { throw 'Overpass returned an incomplete/error extract' }
        'meta' { $taskOsmBase = $taskReader.GetAttribute('osm_base') }
        'node' { $taskNodes++ }
        'way' { $taskWays++ }
        'relation' { $taskRelations++ }
      }
    }
  } finally { $taskReader.Dispose() }
  if ($taskNodes -lt 100 -or $taskWays -lt 100 -or -not $taskOsmBase) { throw 'OSM extract metadata or road data missing' }
  Move-Item -LiteralPath "$taskOsm.partial" -Destination $taskOsm
  @{osmBase=$taskOsmBase; nodes=$taskNodes; ways=$taskWays; relations=$taskRelations; querySha256=(Get-FileHash -LiteralPath $taskQuery -Algorithm SHA256).Hash.ToLowerInvariant()} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $taskRouting 'extract.json') -Encoding utf8
}
$taskMeta = Get-Content -LiteralPath (Join-Path $taskRouting 'extract.json') -Raw | ConvertFrom-Json
$taskOsmHash = (Get-FileHash -LiteralPath $taskOsm -Algorithm SHA256).Hash.ToLowerInvariant()
$taskConfigHash = (Get-FileHash -LiteralPath (Join-Path $taskRoot 'backend\routing\graphhopper.yml') -Algorithm SHA256).Hash.ToLowerInvariant()
$taskVersion = "dhaka-gh11.1-$($taskOsmHash.Substring(0,20))-$($taskConfigHash.Substring(0,12))"
@{graphVersion=$taskVersion; engineVersion='11.1'; engineSha256=$taskExpectedJar; extractSha256=$taskOsmHash; configSha256=$taskConfigHash; osmBase=$taskMeta.osmBase; importBounds=@(23.60,90.15,24.05,90.63); pilotBounds=@(23.62,90.20,24.02,90.58); attribution='© OpenStreetMap contributors'; license='ODbL-1.0'; source='https://overpass-api.de/api/interpreter'} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $taskRouting 'manifest.json') -Encoding utf8
Write-Output "Prepared $taskVersion ($($taskMeta.nodes) nodes, $($taskMeta.ways) ways, $($taskMeta.relations) relations). Public OSM data; no road safety labels."
