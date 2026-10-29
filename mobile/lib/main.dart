import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/config/app_config.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode_controller.dart';
import 'features/authentication/session_controller.dart';
import 'features/authentication/splash_screen.dart' show warmSplashVideo;
import 'features/notifications/notification_providers.dart';
import 'features/notifications/push_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Start decoding the splash clip now so it plays instantly, in parallel
  // with Supabase init and the first session resolution.
  warmSplashVideo();

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

  await _startCrashReporting();

  runApp(const ProviderScope(child: GameAllClubApp()));
}

/// Sends crashes to Firebase Crashlytics in release builds (not while developing). Best effort: a phone without Google
/// services, or a build without Firebase set up, simply has no crash reports.
Future<void> _startCrashReporting() async {
  if (kDebugMode) return;
  try {
    await Firebase.initializeApp();
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  } catch (e) {
    debugPrint('Crash reporting unavailable: $e');
  }
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
    // Phone push notifications: tapping one opens the screen it is about; a message arriving refreshes the bell.
    PushService.instance.init(
      open: (route) => ref.read(appRouterProvider).push(route),
      onIncoming: () {
        ref.invalidate(unreadNotificationsProvider);
        ref.invalidate(notificationsProvider);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    // Register this phone for push when someone signs in, and release it when they sign out.
    ref.listen<String?>(sessionControllerProvider.select((s) => s.user?.id), (previous, next) {
      if (next != null) {
        PushService.instance.onSignedIn(ref.read(notificationRepositoryProvider));
      } else if (previous != null) {
        PushService.instance.onSignedOut();
      }
    });
    final themeMode = ref.watch(themeModeControllerProvider);
    return MaterialApp.router(
      title: 'GameAll Venue',
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
      builder: (context, child) {
        // Screens without an AppBar (e.g. the dashboard) don't pick up
        // AppBarTheme.systemOverlayStyle — assert it here from the theme
        // that actually resolved so the status bar always contrasts.
        final theme = Theme.of(context);
        SystemChrome.setSystemUIOverlayStyle(
          systemOverlayFor(
            theme.extension<AppColorTokens>() ?? AppColorTokens.dark,
            theme.brightness,
          ),
        );
        return child ?? const SizedBox.shrink();
      },
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