import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/app_config.dart';
import 'core/theme/app_theme.dart';
import 'features/welcome/welcome_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Portrait only, like the club app.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // The first page needs no backend, so a build without env.json still opens; every page that talks to Supabase
  // will check `AppConfig.isConfigured` first. Build with: flutter build apk --debug --dart-define-from-file=env.json
  if (AppConfig.isConfigured) {
    await Supabase.initialize(url: AppConfig.supabaseUrl, publishableKey: AppConfig.supabaseAnonKey);
  }

  runApp(const ProviderScope(child: GameAllPlayerApp()));
}

class GameAllPlayerApp extends StatelessWidget {
  const GameAllPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GameAll Player',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      // The player experience is dark-first, like the design.
      themeMode: ThemeMode.dark,
      home: Builder(
        builder: (context) => WelcomeScreen(
          onGetStarted: () => ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(const SnackBar(content: Text('Sign in and registration are coming next.'))),
        ),
      ),
    );
  }
}
