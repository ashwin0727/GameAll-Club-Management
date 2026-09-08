import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/config/app_config.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait — the app's layouts are designed portrait-only and the
  // rotation on device tilt was more disorienting than useful.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  if (!AppConfig.isConfigured) {
    runApp(const _MissingConfigApp());
    return;
  }

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    // Same anon/publishable key the web app uses — public, RLS-protected.
    publishableKey: AppConfig.supabaseAnonKey,
  );

  runApp(const ProviderScope(child: GameAllClubApp()));
}

class GameAllClubApp extends ConsumerStatefulWidget {
  const GameAllClubApp({super.key});

  @override
  ConsumerState<GameAllClubApp> createState() => _GameAllClubAppState();
}

class _GameAllClubAppState extends ConsumerState<GameAllClubApp> {
  @override
  void initState() {
    super.initState();
    // Re-assert the portrait lock once the engine + activity are attached —
    // the call in main() can race engine init and be dropped, which lets
    // Flutter fall back to SCREEN_ORIENTATION_UNSPECIFIED and override the
    // manifest. Doing it here (post-attach) makes it stick.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeControllerProvider);
    return MaterialApp.router(
      title: 'GameAll Club',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      // Dark is the primary visual direction (spec) — System/Light/Dark is
      // the user's own Appearance choice (see ThemeModeController), never
      // hard-coded to one theme.
      themeMode: themeMode,
      themeAnimationDuration: const Duration(milliseconds: 240),
      routerConfig: router,
      // Never suppress the platform's accessibility text scaling — a large
      // system font size must still produce a usable app (item 9/80).
      builder: (context, child) => child ?? const SizedBox.shrink(),
    );
  }
}

/// Shown only if the app was built without `--dart-define-from-file` — a
/// clear configuration error, not a silent crash or a fallback to
/// hard-coded credentials.
class _MissingConfigApp extends StatelessWidget {
  const _MissingConfigApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Missing Supabase configuration.\n\n'
              'Run with:\n'
              'flutter run --dart-define-from-file=env.json',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

extension AppRouterExtension on WidgetRef {
  GoRouter get router => read(appRouterProvider);
}