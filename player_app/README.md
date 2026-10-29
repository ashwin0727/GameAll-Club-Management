# GameAll Player

The players' app: view registrations, start memberships, book courts (guest booking) and follow tournaments.
It lives beside the club-management app (`../mobile`) in the same repo and talks to the same Supabase project.

| | Club app | Player app |
|---|---|---|
| Folder | `mobile/` | `player_app/` |
| Package | `gameall_club_mobile` | `gameall_player` |
| Android id | `gameall.venue` | `com.gameall.gameall_player` |

## Run / build

```
cd player_app
cp env.example.json env.json        # once; same values as mobile/env.json (env.json is git-ignored)
flutter run --dart-define-from-file=env.json
flutter build apk --debug --dart-define-from-file=env.json
```

The APK is written to `build/app/outputs/flutter-apk/app-debug.apk`.

## Layout

- `lib/core/theme/` — the GameAll design system (colours, Manrope type scale, theme), copied from the club app so
  both apps look the same. When a third consumer appears, move it into a shared package.
- `lib/core/config/app_config.dart` — Supabase configuration from `--dart-define`.
- `lib/features/welcome/` — the first page.
- `assets/images/players.png` — the welcome background; `logo-icon.png` — the GameAll mark.
