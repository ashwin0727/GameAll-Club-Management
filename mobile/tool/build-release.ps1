# Builds the signed Play Store bundle (.aab) for GameAll Venue.
#
# Why a copy? The project lives in OneDrive, and OneDrive (and editor file watchers) lock Gradle's build folder, which makes
# release builds fail with "Unable to delete directory". This script copies the app to C:\GameAllBuild\venue-src, builds there,
# checks the bundle is signed with YOUR upload key (not the debug key), and copies the result next to the key.
#
# Needs: android\key.properties (see key.properties.example) and env.json in the mobile folder.
#
# Run:   powershell -ExecutionPolicy Bypass -File mobile\tool\build-release.ps1

$ErrorActionPreference = "Stop"
$src = Resolve-Path (Join-Path $PSScriptRoot "..")
$dst = "C:\GameAllBuild\venue-src"
$keytool = "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe"

foreach ($f in @("android\key.properties", "env.json", "android\app\google-services.json")) {
  if (-not (Test-Path (Join-Path $src $f))) { throw "Missing $f in the mobile folder. See docs/play-store-release.md." }
}

Write-Host "Copying the app to $dst ..."
New-Item -ItemType Directory -Force $dst | Out-Null
robocopy $src $dst /MIR /XD build .dart_tool .gradle .idea .cxx /XF flutter_01.log /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "Copy failed (robocopy exit $LASTEXITCODE)." }

Push-Location $dst
try {
  & flutter pub get
  if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed." }
  & flutter build appbundle --release --dart-define-from-file=env.json
  if ($LASTEXITCODE -ne 0) { throw "Build failed." }

  $aab = Join-Path $dst "build\app\outputs\bundle\release\app-release.aab"
  Write-Host "`nSigner of the bundle:"
  & $keytool -printcert -jarfile $aab | Select-String "Owner|Valid from"
  $owner = (& $keytool -printcert -jarfile $aab | Select-String "Owner").ToString()
  if ($owner -match "Android Debug") { throw "The bundle is signed with the DEBUG key. Check android\key.properties." }

  $version = (Select-String -Path (Join-Path $src "pubspec.yaml") -Pattern "^version:\s*(\S+)").Matches[0].Groups[1].Value
  $out = "C:\GameAllBuild\GameAll-Venue-$version.aab"
  Copy-Item $aab $out -Force
  Write-Host "`nDone. Upload this file to Play Console:`n  $out"
}
finally {
  Pop-Location
}
