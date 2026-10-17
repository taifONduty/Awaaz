param(
  [string]$Flutter = (Join-Path $env:USERPROFILE '.codex\toolchains\flutter\bin\flutter.bat'),
  [string]$Jdk = (Join-Path $env:USERPROFILE '.codex\toolchains\jdk-21.0.12.1\jdk-21.0.12.1+1')
)
$ErrorActionPreference = 'Stop'
$workspaceRoot = Split-Path $PSScriptRoot -Parent
$adbTool = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
$apkFile = Join-Path $workspaceRoot '.local\awaaz-sharing-test.apk'
if (-not (Test-Path -LiteralPath $apkFile)) { throw 'Build with -Integration -IntegrationTarget integration_test/sharing_test.dart first' }
$identity = & $adbTool -s emulator-5554 emu avd name
if ($identity -notcontains 'awaaz_dhaka_api36') { throw 'Expected isolated Awaaz emulator' }
$fixture = Invoke-RestMethod http://127.0.0.1:3031/__fixtures
if (-not $fixture.synthetic) { throw 'Expected disposable local fixtures' }
$windows = & $adbTool -s emulator-5554 shell dumpsys window
if ($windows -match 'mCurrentFocus=.*Application Not Responding') { throw 'Resolve the visible emulator ANR before starting' }
$previousJava = $env:JAVA_HOME
Push-Location (Join-Path $workspaceRoot 'apps\mobile')
try {
  $env:JAVA_HOME = $Jdk
  & $adbTool -s emulator-5554 shell am force-stop app.awaaz.awaaz
  if ($LASTEXITCODE -ne 0) { throw 'Could not stop the prior Awaaz application' }
  & $Flutter drive --no-pub --keep-app-running --driver=test_driver/integration_test.dart --target=integration_test/sharing_test.dart "--use-application-binary=$apkFile" -d emulator-5554 *> (Join-Path $workspaceRoot '.local\sharing-android.log')
  if ($LASTEXITCODE -ne 0) { throw 'Sharing Android cycle failed; inspect .local/sharing-android.log' }
  Write-Output 'Sharing Android cycle passed. Restore the regular preview APK.'
} finally {
  $env:JAVA_HOME = $previousJava
  Pop-Location
}
