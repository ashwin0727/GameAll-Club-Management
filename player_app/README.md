# GameAll Play

The players' app: view registrations, start memberships, book courts (guest booking) and follow tournaments.
It lives beside the club-management app (`../mobile`) in the same repo and talks to the same Supabase project.
One Flutter code base builds the **Android app** and the **web app**.

| | Club app | Player app |
|---|---|---|
| Folder | `mobile/` | `player_app/` |
| Package | `gameall_club_mobile` | `gameall_player` |
| Android id | `gameall.venue` | `com.gameall.gameall_play` |

## Run / build

OneDrive and editor file watchers lock Flutter's `build` folder, so builds and tests run on a copy outside OneDrive. One helper
does it (from the repo root; the first argument onwards is an ordinary `flutter` command):

```
cp player_app/env.example.json player_app/env.json     # once; same values as mobile/env.json (git-ignored)
powershell -ExecutionPolicy Bypass -File player_app\tool\run-in-copy.ps1 test
powershell -ExecutionPolicy Bypass -File player_app\tool\run-in-copy.ps1 build apk --debug --dart-define-from-file=env.json
powershell -ExecutionPolicy Bypass -File player_app\tool\run-in-copy.ps1 build web --release --dart-define-from-file=env.json
```

Outputs: `C:\GameAllBuild\player-src\build\app\outputs\flutter-apk\app-debug.apk` and `C:\GameAllBuild\player-src\build\web\`
(upload that folder to any static host; there is no server code).

## Deploying to play.gameall.co

The Player web app has its own Vercel project, **gameall-player**, separate from the club site (the Next.js project
`game-all-club-management`). They share one Git repository but never one deployment: the club project ignores this folder
(`.vercelignore`), and this project serves only the static Flutter build. A Player release cannot affect the club site.

One-time setup:
1. `vercel login` (the CLI's saved sign-in has expired).
2. Do a first preview deploy, which creates the project: `powershell -ExecutionPolicy Bypass -File player_app\tool\deploy-web.ps1`
3. In Vercel -> gameall-player -> Settings -> Domains, add **play.gameall.co**. Vercel then shows the DNS record to create at
   your domain registrar (normally a CNAME `play` -> `cname.vercel-dns.com`). It goes live once DNS has updated.
4. In the club project (`game-all-club-management`) -> Settings -> Git -> **Ignored Build Step**, set the command to
   `git diff --quiet HEAD^ HEAD -- . ":(exclude)player_app"` so a Player-only change never rebuilds the club site.
5. Supabase -> Authentication -> URL configuration: add `https://play.gameall.co` to the redirect URLs, ready for sign-in.

Every release after that (from the repo root):
```
powershell -ExecutionPolicy Bypass -File player_app\tool\deploy-web.ps1          # preview: a temporary URL to check first
powershell -ExecutionPolicy Bypass -File player_app\tool\deploy-web.ps1 -Prod    # the live site, play.gameall.co
```
It builds on a copy outside OneDrive, stages the site in `C:\GameAllBuild\player-deploy`, and uses `player_app/vercel.json`
(no-cache on the app shell, a day of caching on assets).

## Database

The Home page reads everything about the player in one call, `get_my_player_home()` (migration `0167_player_home.sql`): name,
unread notifications, active membership, active coaching, booking history and the next confirmed bookings, for the signed-in
caller only. Until that migration is applied the page still opens, without the personal parts.

## Layout

- `lib/core/theme/` — the design system: `app_colors.dart` (the palette tokens and the dark/light `AppPalette`),
  `app_text_styles.dart` (the Manrope scale), `app_dimensions.dart`, `app_theme.dart`. Widgets read `context.palette`; never
  hard-code a colour, so Dark and Light stay one set of widgets.
- `assets/fonts/Manrope-Variable.ttf` — Manrope (SIL Open Font Licence), bundled, so it renders the same offline and on the web.
- `lib/core/widgets/` — `GameAllButton` (gradient / solid / secondary / disabled) and `Pressable` (the 150ms press animation).
- `lib/features/player_home/` — the Home page: `domain` (models and the "next game" rule), `data` (the Supabase repository),
  `application` (Riverpod providers: data, selected sport, city, theme), `presentation` (page, desktop body, and one widget per
  section: header, search bar, sports selector, promo carousel, shortcut cards, next game, bottom navigation).
- `lib/features/shell/` — the signed-in frame: five tabs, bottom bar on a phone, top bar on a wide window; plus the
  "coming soon" page every not-yet-built destination opens.
- `lib/features/welcome/` — the first page.
- `assets/images/hero_*.webp` — the three promo images (blue-toned from the club app's photography; swap in licensed photos
  of the same size, 960x616, to change them).

## What is not built yet

Sign in / registration, and the pages behind the Home shortcuts (guest booking, memberships, coaching, bookings, explore,
profile, notifications, search). They open a clear "Coming soon" page; the Home page is ready to link to each as it lands.
The Profile tab already has the Dark/Light switch.
