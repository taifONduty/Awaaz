param(
  [string]$Flutter = (Join-Path $env:USERPROFILE '.codex\toolchains\flutter\bin\flutter.bat'),
  [string]$Jdk = (Join-Path $env:USERPROFILE '.codex\toolchains\jdk-21.0.12.1\jdk-21.0.12.1+1'),
  [string]$Sdk = (Join-Path $env:LOCALAPPDATA 'Android\Sdk')
)
$ErrorActionPreference = 'Stop'
$awaazRoot = Split-Path $PSScriptRoot -Parent
$adbPath = Join-Path $Sdk 'platform-tools\adb.exe'
$apkPath = Join-Path $awaazRoot '.local\awaaz-android-test.apk'
if (-not (Test-Path -LiteralPath $apkPath)) { throw 'Build the integration APK first' }
$deviceName = (& $adbPath -s emulator-5554 emu avd name) | ForEach-Object { $_.Trim() }
if ($deviceName -notcontains 'awaaz_dhaka_api36') { throw 'Expected the isolated Awaaz test AVD' }
$deviceWindows = & $adbPath -s emulator-5554 shell dumpsys window
if ($deviceWindows -match 'mCurrentFocus=.*Application Not Responding') {
  throw 'An emulator ANR dialog covers the application. Inspect and resolve it before running the Android cycle.'
}
$fixtures = Invoke-RestMethod http://127.0.0.1:3031/__fixtures
if (-not $fixtures.synthetic -or $fixtures.restartRequestId) { throw 'Restart the disposable fixture API before phase one' }
$fixtureOwner = $fixtures.alice.id
$previousJava = $env:JAVA_HOME
Push-Location (Join-Path $awaazRoot 'apps\mobile')
try {
  $env:JAVA_HOME = $Jdk
  # End any service left by a failed prior fixture run; retain installation/data.
  & $adbPath -s emulator-5554 shell am force-stop app.awaaz.awaaz
  if ($LASTEXITCODE -ne 0) { throw 'Could not stop the previous test application' }
  $arguments = @('drive', '--no-pub', '--keep-app-running',
    '--driver=test_driver/integration_test.dart', '--target=integration_test/android_loop_test.dart',
    "--use-application-binary=$apkPath", '-d', 'emulator-5554')
  & $Flutter @arguments *> (Join-Path $awaazRoot '.local\android-storage-phase1-kept.log')
  if ($LASTEXITCODE -ne 0) { throw 'Android phase one failed; inspect its log' }
  $restart = Invoke-RestMethod http://127.0.0.1:3031/__fixtures
  if (-not $restart.restartRequestId -or $restart.alice.id -ne $fixtureOwner) { throw 'Missing restart fixture or changed database' }
  $installed = & $adbPath -s emulator-5554 shell pm path app.awaaz.awaaz
  if (-not ($installed -match '^package:')) { throw 'Driver removed the app; private data cannot be tested across restart' }
  $beforePid = & $adbPath -s emulator-5554 shell pidof app.awaaz.awaaz
  & $adbPath -s emulator-5554 shell am force-stop app.awaaz.awaaz
  if ($LASTEXITCODE -ne 0) { throw 'Could not stop the test application' }
  $afterPid = & $adbPath -s emulator-5554 shell pidof app.awaaz.awaaz
  if ($afterPid) { throw 'Application process still exists after force-stop' }
  Write-Output "Phase one passed. Stopped process $beforePid; app installation and fixture database retained."
  & $Flutter @arguments *> (Join-Path $awaazRoot '.local\android-storage-phase2-kept.log')
  if ($LASTEXITCODE -ne 0) { throw 'Android process-restart recovery failed; inspect phase two log' }
  Write-Output 'Both Android phases passed. Restore the regular preview APK after testing.'
} finally {
  $env:JAVA_HOME = $previousJava
  Pop-Location
}
