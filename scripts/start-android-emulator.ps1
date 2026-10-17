param(
  [string]$Sdk = (Join-Path $env:LOCALAPPDATA 'Android\Sdk'),
  [switch]$LeanFixtures
)
$ErrorActionPreference = 'Stop'
$awaazRoot = Split-Path $PSScriptRoot -Parent
$adb = Join-Path $Sdk 'platform-tools\adb.exe'
$emulator = Join-Path $Sdk 'emulator\emulator.exe'
$serial = 'emulator-5554'
$avd = 'awaaz_dhaka_api36'
if (-not (Test-Path -LiteralPath $adb) -or -not (Test-Path -LiteralPath $emulator)) {
  throw 'Supply the installed Android SDK path'
}
$state = & $adb -s $serial get-state 2>$null
if ($state -ne 'device') {
  $outputRoot = Join-Path $awaazRoot '.local'
  New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
  # A visible emulator was explicitly requested. No unrelated device is changed.
  Start-Process -FilePath $emulator -ArgumentList @(
    '-avd', $avd, '-port', '5554', '-memory', '2048', '-cores', '4',
    '-gpu', 'auto', '-no-boot-anim', '-no-snapshot', '-noaudio',
    '-crash-report-mode', 'disabled'
  ) -RedirectStandardOutput (Join-Path $outputRoot 'emulator-start.log') `
    -RedirectStandardError (Join-Path $outputRoot 'emulator-start-errors.log') | Out-Null
}
$deadline = (Get-Date).AddMinutes(3)
do {
  $booted = & $adb -s $serial shell getprop sys.boot_completed 2>$null
  if ($booted -eq '1') { break }
  Start-Sleep -Seconds 2
} while ((Get-Date) -lt $deadline)
if ($booted -ne '1') { throw 'Awaaz emulator did not finish booting' }
$identity = (& $adb -s $serial emu avd name) | ForEach-Object { $_.Trim() }
if ($identity -notcontains $avd) { throw 'Port 5554 belongs to another device; refusing to modify it' }
foreach ($scale in @('window_animation_scale', 'transition_animation_scale', 'animator_duration_scale')) {
  & $adb -s $serial shell settings put global $scale 0 | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "Could not set $scale" }
}
& $adb -s $serial shell settings put secure show_ime_with_hard_keyboard 1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not enable the emulator software keyboard' }
if ($LeanFixtures) {
  # Only disposable local-fixture tests. These packages are unrelated to the
  # tested flows. Keep Play Services, location, keyboard and accessibility enabled.
  $packages = @(
    'com.google.android.googlequicksearchbox', 'com.google.android.apps.wellbeing',
    'com.google.android.apps.safetyhub', 'com.google.android.apps.photos',
    'com.google.android.apps.messaging', 'com.google.android.as',
    'com.google.android.as.oss', 'com.google.android.projection.gearhead',
    'com.android.chrome'
  )
  $installed = (& $adb -s $serial shell pm list packages) | ForEach-Object { $_.Trim() }
  foreach ($package in $packages) {
    if ($installed -contains "package:$package") {
      & $adb -s $serial shell pm disable-user --user 0 $package | Out-Null
      if ($LASTEXITCODE -ne 0) { throw "Could not disable fixture-only package $package" }
    }
  }
}
Write-Output "Ready: $avd ($serial). Compile before boot on this low-memory host."
Write-Output 'Lean package changes are reversible with adb shell pm enable <package> or by recreating this test AVD.'
