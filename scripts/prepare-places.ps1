param()
$ErrorActionPreference='Stop'
$taskRoot=Split-Path $PSScriptRoot -Parent
$placeRoot=Join-Path $taskRoot '.local/places'
New-Item -ItemType Directory -Path $placeRoot -Force | Out-Null
$target=Join-Path $placeRoot 'dhaka-poi.osm'
if (-not (Test-Path -LiteralPath $target)) {
  $query=Get-Content -LiteralPath (Join-Path $taskRoot 'backend/routing/dhaka-places.overpass.ql') -Raw
  Invoke-WebRequest -Uri 'https://overpass-api.de/api/interpreter' -Method Post -Body @{data=$query} -UserAgent 'Awaaz-local-place-import/0.2' -OutFile "$target.partial" -TimeoutSec 180
  $bytes=(Get-Item -LiteralPath "$target.partial").Length
  if($bytes -lt 1000 -or $bytes -gt 134217728){throw 'Unexpected POI extract size'}
  $settings=[System.Xml.XmlReaderSettings]::new()
  $settings.DtdProcessing=[System.Xml.DtdProcessing]::Prohibit
  $settings.XmlResolver=$null
  $reader=[System.Xml.XmlReader]::Create("$target.partial",$settings)
  $sourceTime=$null; $nodes=0
  try {while($reader.Read()) {if($reader.NodeType -ne [System.Xml.XmlNodeType]::Element){continue};switch($reader.Name){'remark'{throw 'Incomplete POI extract'} 'meta'{$sourceTime=$reader.GetAttribute('osm_base')} 'node'{$nodes++}}}}
  finally{$reader.Dispose()}
  if(-not $sourceTime -or $nodes -lt 10){throw 'POI extract is incomplete'}
  Move-Item -LiteralPath "$target.partial" -Destination $target
}
Write-Output 'Cached Dhaka POI extract ready. Run the offline catalogue exporter; this is not a live search service.'
