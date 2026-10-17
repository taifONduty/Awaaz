param(
  [string]$Jdk = (Join-Path $env:USERPROFILE '.codex\toolchains\jdk-21.0.12.1\jdk-21.0.12.1+1'),
  [switch]$UseMirrors
)
$ErrorActionPreference = 'Stop'
$awaazRoot = Split-Path $PSScriptRoot -Parent
$previousJava = $env:JAVA_HOME
$previousOptions = $env:JAVA_TOOL_OPTIONS
$previousMirror = $env:AWAAZ_USE_GOOGLE_MAVEN_MIRROR
Push-Location (Join-Path $awaazRoot 'apps\mobile\android')
try {
  $env:JAVA_HOME = $Jdk
  $env:JAVA_TOOL_OPTIONS = '-Djava.net.preferIPv4Stack=true -Dorg.gradle.internal.http.connectionTimeout=10000 -Dorg.gradle.internal.http.socketTimeout=20000'
  $env:AWAAZ_USE_GOOGLE_MAVEN_MIRROR = if ($UseMirrors) { 'true' } else { 'false' }
  # Match the installed emulator ABI; unit tests do not need every Flutter engine ABI.
  & .\gradlew.bat :app:testDebugUnitTest -Ptarget-platform=android-x64 --console=plain
  $testExit = $LASTEXITCODE
  & .\gradlew.bat --stop
  if ($testExit -ne 0) { throw 'Native trip unit tests failed' }
  if ($LASTEXITCODE -ne 0) { throw 'Could not stop the build daemon' }
} finally {
  $env:JAVA_HOME = $previousJava
  $env:JAVA_TOOL_OPTIONS = $previousOptions
  $env:AWAAZ_USE_GOOGLE_MAVEN_MIRROR = $previousMirror
  Pop-Location
}
