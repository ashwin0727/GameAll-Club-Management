# Builds the Player web app and deploys it to Vercel (the "gameall-player" project, served at https://play.gameall.co).
#
# The club app (Next.js) is a different Vercel project; this one only ever serves the static Flutter build, so a Player release can
# never touch the club site and the other way round.
#
# One-time setup (see player_app/README.md, "Deploying to play.gameall.co"):
#   1. vercel login
#   2. add the domain play.gameall.co to the gameall-player project and point its DNS at Vercel
#   3. player_app\env.json must exist (SUPABASE_URL and SUPABASE_ANON_KEY; the same public values as mobile\env.json)
#
# Run from the repo root:
#   powershell -ExecutionPolicy Bypass -File player_app\tool\deploy-web.ps1            # a preview deployment (its own temporary URL)
#   powershell -ExecutionPolicy Bypass -File player_app\tool\deploy-web.ps1 -Prod      # the live site, play.gameall.co
param([switch] $Prod)
# "Continue" on purpose: the Vercel CLI and Flutter write progress to the error stream, which "Stop" would treat as a failure.
# Every step checks its exit code explicitly instead.
$ErrorActionPreference = "Continue"
$here = Split-Path -Parent $PSScriptRoot            # ...\player_app
$staging = "C:\GameAllBuild\player-deploy"          # holds the built site plus Vercel's link to the project (.vercel)

if (-not (Test-Path (Join-Path $here "env.json"))) { throw "player_app\env.json is missing. Copy env.example.json and fill in the Supabase values." }

# Is the Vercel CLI signed in?
& vercel whoami *> $null
if ($LASTEXITCODE -ne 0) { throw "Not signed in to Vercel. Run: vercel login" }

# 1. Build (on a copy outside OneDrive; see run-in-copy.ps1).
#    --pwa-strategy=none: no caching service worker. The site only works online anyway, and the worker kept stale copies of the app and
#    its icon font in the browser's Cache Storage (which "clear cache" does not reach), so a new deploy showed blank icons.
& powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "run-in-copy.ps1") build web --release --pwa-strategy=none --dart-define-from-file=env.json
if ($LASTEXITCODE -ne 0) { throw "The web build failed." }

# 2. Stage the site, keeping the project link between deployments
New-Item -ItemType Directory -Force $staging | Out-Null
robocopy "C:\GameAllBuild\player-src\build\web" $staging /MIR /XD .vercel /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "Copying the build failed (robocopy exit $LASTEXITCODE)." }
Copy-Item (Join-Path $here "vercel.json") (Join-Path $staging "vercel.json") -Force

# 3. Deploy
Push-Location $staging
try {
  if (-not (Test-Path ".vercel\project.json")) {
    # First run only: creates (or links) the project named gameall-player.
    & vercel link --yes --project gameall-player
    if ($LASTEXITCODE -ne 0) { throw "Linking the Vercel project failed." }
  }
  if ($Prod) { & vercel deploy --prod --yes } else { & vercel deploy --yes }
  if ($LASTEXITCODE -ne 0) { throw "The deployment failed." }
}
finally { Pop-Location }
