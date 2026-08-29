import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/config/app_config.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

class GameAllClubApp extends ConsumerWidget {
  const GameAllClubApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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