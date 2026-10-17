param(
  [string]$Flutter = (Join-Path $env:USERPROFILE '.codex\toolchains\flutter\bin\flutter.bat'),
  [string]$Jdk = (Join-Path $env:USERPROFILE '.codex\toolchains\jdk-21.0.12.1\jdk-21.0.12.1+1'),
  [switch]$Integration,
  [string]$IntegrationTarget = 'integration_test/android_loop_test.dart',
  [ValidateSet('debug', 'profile')][string]$Mode = 'debug',
  [switch]$UseMirrors,
  [switch]$StopBuildDaemon
)
$ErrorActionPreference = 'Stop'
if ($Integration -and $Mode -ne 'debug') { throw 'Integration fixtures require debug mode' }
if ($Integration -and $IntegrationTarget -notmatch '^integration_test/[a-z0-9_]+\.dart$') { throw 'Supply an integration_test Dart entry point' }
$workspaceRoot = Split-Path $PSScriptRoot -Parent
$mobileRoot = Join-Path $workspaceRoot 'apps\mobile'
if (-not (Test-Path -LiteralPath $Flutter)) { throw 'Supply the Flutter executable path' }
if (-not (Test-Path -LiteralPath (Join-Path $Jdk 'bin\java.exe'))) { throw 'Supply a JDK 21 directory' }
$previousJava = $env:JAVA_HOME
$previousOptions = $env:JAVA_TOOL_OPTIONS
$previousMirror = $env:AWAAZ_USE_GOOGLE_MAVEN_MIRROR
$previousMapsDisable = $env:AWAAZ_DISABLE_GOOGLE_MAPS
Push-Location $mobileRoot
try {
  $env:JAVA_HOME = $Jdk
  $env:JAVA_TOOL_OPTIONS = '-Djava.net.preferIPv4Stack=true -Dorg.gradle.internal.http.connectionTimeout=10000 -Dorg.gradle.internal.http.socketTimeout=20000'
  $env:AWAAZ_USE_GOOGLE_MAVEN_MIRROR = if ($UseMirrors) { 'true' } else { 'false' }
  # Integration fixtures never instantiate the live provider or embed its key.
  if ($Integration) { $env:AWAAZ_DISABLE_GOOGLE_MAPS = 'true' }
  $mapsConfigFile = Join-Path $workspaceRoot '.local\maps.android.properties'
  $mapsConfigured = -not [string]::IsNullOrWhiteSpace($env:AWAAZ_GOOGLE_MAPS_ANDROID_API_KEY)
  if (-not $mapsConfigured -and (Test-Path -LiteralPath $mapsConfigFile)) {
    # Inspect presence only. The credential never becomes a Dart define or log.
    $mapsConfigured = [bool](Get-Content -LiteralPath $mapsConfigFile | Where-Object {
      $_ -match '^\s*GOOGLE_MAPS_ANDROID_API_KEY\s*=\s*\S'
    })
  }
  if ($env:AWAAZ_DISABLE_GOOGLE_MAPS -eq 'true') { $mapsConfigured = $false }
  $mapsFlag = if ($mapsConfigured) { 'true' } else { 'false' }
  $target = if ($Integration) { $IntegrationTarget } else { 'lib/main.dart' }
  if (-not (Test-Path -LiteralPath $target)) { throw 'Android entry point not found' }
  $routingUrl = ''
  $routingConfigFile = Join-Path $workspaceRoot '.local\routing.mobile.properties'
  if (-not $Integration -and (Test-Path -LiteralPath $routingConfigFile)) {
    $routingLine = Get-Content -LiteralPath $routingConfigFile | Where-Object { $_ -match '^AWAAZ_ROUTING_API_URL=' } | Select-Object -First 1
    if ($routingLine) { $routingUrl = ($routingLine -split '=',2)[1].Trim() }
  }
  & $Flutter build apk "--$Mode" --target-platform android-x64 --target $target "--dart-define=AWAAZ_GOOGLE_MAPS=$mapsFlag" "--dart-define=AWAAZ_ROUTING_API_URL=$routingUrl"
  if ($LASTEXITCODE -ne 0) { throw 'Android build failed' }
  $outputRoot = Join-Path $workspaceRoot '.local'
  New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
  $outputName = if ($Integration -and $IntegrationTarget -ne 'integration_test/android_loop_test.dart') {
    'awaaz-' + ([IO.Path]::GetFileNameWithoutExtension($IntegrationTarget) -replace '_', '-') + '.apk'
  } elseif ($Integration) { 'awaaz-android-test.apk' } elseif ($Mode -eq 'profile') { 'awaaz-android-profile.apk' } else { 'awaaz-android-preview.apk' }
  Copy-Item -LiteralPath (Join-Path $mobileRoot "build\app\outputs\flutter-apk\app-$Mode.apk") -Destination (Join-Path $outputRoot $outputName)
  if ($StopBuildDaemon) {
    Push-Location (Join-Path $mobileRoot 'android')
    try { & .\gradlew.bat --stop } finally { Pop-Location }
    if ($LASTEXITCODE -ne 0) { throw 'Gradle daemon did not stop' }
  }
  Write-Output "Built $outputName ($Mode). Local debug/profile/test builds must not be distributed."
} finally {
  $env:JAVA_HOME = $previousJava
  $env:JAVA_TOOL_OPTIONS = $previousOptions
  $env:AWAAZ_USE_GOOGLE_MAVEN_MIRROR = $previousMirror
  $env:AWAAZ_DISABLE_GOOGLE_MAPS = $previousMapsDisable
  Pop-Location
}
