# Runs a flutter command on a copy of the Player app outside OneDrive.
#
# OneDrive and editor file watchers lock the build folder ("Flutter failed to delete a directory"), so builds and tests run on a copy
# at C:\GameAllBuild\player-src. Examples (from the repo root):
#   powershell -ExecutionPolicy Bypass -File player_app\tool\run-in-copy.ps1 test
#   powershell -ExecutionPolicy Bypass -File player_app\tool\run-in-copy.ps1 build apk --debug --dart-define-from-file=env.json
#   powershell -ExecutionPolicy Bypass -File player_app\tool\run-in-copy.ps1 build web --release --dart-define-from-file=env.json
# (No param() block on purpose: PowerShell would swallow flags such as --debug as its own common parameters.)
$FlutterArgs = $args
$ErrorActionPreference = "Stop"
$src = Resolve-Path (Join-Path $PSScriptRoot "..")
$dst = "C:\GameAllBuild\player-src"
New-Item -ItemType Directory -Force $dst | Out-Null
robocopy $src $dst /MIR /XD build .dart_tool .gradle .idea .cxx /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "Copy failed (robocopy exit $LASTEXITCODE)." }
Push-Location $dst
try {
  & flutter pub get
  & flutter @FlutterArgs
  exit $LASTEXITCODE
}
finally { Pop-Location }
