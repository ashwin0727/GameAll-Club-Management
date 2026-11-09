import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/app_config.dart';
import 'core/routing/app_routes.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/theme_crossfade.dart';
import 'features/auth/presentation/login_flow.dart';
import 'features/notifications/application/notification_providers.dart';
import 'features/notifications/presentation/notifications_ui.dart';
import 'features/notifications/push_service.dart';
import 'features/auth/application/auth_providers.dart';
import 'features/player_home/application/player_home_controller.dart';
import 'features/shell/player_pages.dart';
import 'features/shell/player_shell.dart';
import 'features/welcome/welcome_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Portrait only on a phone; the web build and tablets rotate freely.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // The first page needs no backend, so a build without env.json still opens; every page that talks to Supabase
  // checks `AppConfig.isConfigured` first. Build with: flutter build apk --debug --dart-define-from-file=env.json
  if (AppConfig.isConfigured) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseAnonKey,
    );
  }

  // the theme the player chose last time
  var theme = ThemeMode.dark;
  try {
    final saved = (await SharedPreferences.getInstance()).getString(
      ThemeModeController.prefsKey,
    );
    if (saved == 'light') theme = ThemeMode.light;
  } catch (_) {}

  // Phone push (not on the web); best effort, never blocks the app opening
  if (!kIsWeb) unawaited(PushService.instance.init());

  runApp(
    ProviderScope(
      overrides: [initialThemeModeProvider.overrideWithValue(theme)],
      child: const GameAllPlayerApp(),
    ),
  );
}

class GameAllPlayerApp extends ConsumerWidget {
  const GameAllPlayerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    // a push message arriving while the app is open refreshes the bell
    PushService.instance.onIncoming = () => ref.invalidate(notificationsControllerProvider);
    // register this phone for push when a player is signed in, release it when they sign out
    ref.listen(currentPlayerProvider, (previous, next) {
      if (next != null) {
        PushService.instance.onSignedIn(ref.read(notificationRepositoryProvider));
      } else if (previous != null) {
        PushService.instance.onSignedOut();
      }
    });
    return MaterialApp(
      title: 'GameAll Play',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      // Dark first, like the design; switchable from Profile. Switching only restyles: no screen state is lost.
      themeMode: mode,
      // No per-frame theme animation (it made pages shrink and shake): the new theme is applied at once and the old look fades away.
      themeAnimationDuration: Duration.zero,
      builder: (context, child) => NotificationPoller(
        child: ThemeCrossfade(mode: mode, child: child ?? const SizedBox.shrink()),
      ),
      // The welcome page is for the phone app only. On the web the app opens on the address in the browser (so a refresh stays
      // on the same page) and on Home when there is none.
      initialRoute: kIsWeb ? null : '/welcome',
      // One route for the address, not the stack "/", "/venue", "/venue/<id>" that Flutter builds by default.
      onGenerateInitialRoutes: (name) => [_routeFor(RouteSettings(name: name))],
      onGenerateRoute: _routeFor,
    );
  }
}

Route<dynamic> _routeFor(RouteSettings settings) {
  // an address can carry a query ("/explore?x=1"): only the path picks the page
  final raw = settings.name;
  final parsed = raw == null ? null : Uri.tryParse(raw);
  final name = parsed == null
      ? raw
      : (parsed.path.isEmpty ? AppRoutes.home : parsed.path);
  // A page the shell shows itself (a tab, a venue, a booking ...): the shell opens on it, so a refresh does not land on Home.
  if (kIsWeb && name != null && AppRoutes.isShellRoute(name)) {
    return MaterialPageRoute<void>(
      settings: RouteSettings(name: name),
      builder: (_) => PlayerShell(initialRoute: name),
    );
  }
  if (name == '/welcome' && kIsWeb) {
    // An old /welcome link or bookmark on the web lands on Home as well.
    return MaterialPageRoute<void>(
      settings: const RouteSettings(name: AppRoutes.home),
      builder: (_) => const PlayerShell(),
    );
  }
  if (name == '/welcome') {
    return MaterialPageRoute<void>(
      settings: settings,
      // The welcome page is a portrait phone design: on a wide window it stays a centred phone-width column.
      builder: (context) => ColoredBox(
        color: AppColors.darkBackground,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: WelcomeScreen(
              onGetStarted: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute<void>(builder: (_) => const PlayerShell()),
              ),
            ),
          ),
        ),
      ),
    );
  }
  if (name == AppRoutes.login) {
    return MaterialPageRoute<void>(
      settings: settings,
      fullscreenDialog: true,
      builder: (_) => const LoginPage(),
    );
  }
  if (name == AppRoutes.home) {
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => const PlayerShell(),
    );
  }
  return MaterialPageRoute<void>(
    settings: settings,
    builder: (_) => playerPageForRoute(name ?? ''),
  );
}
