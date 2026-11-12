import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/routing/app_router.dart';

/// How long the splash stays up in total, counted from the moment the app process started drawing it.
const splashHold = Duration(milliseconds: 2400);

final Stopwatch _sinceLaunch = Stopwatch();
bool _introPlayed = false;

/// Called first thing in `main()`, so the hold time counts from launch and not from when the router first shows the splash.
void markSplashStart() {
  if (!_sinceLaunch.isRunning) _sinceLaunch.start();
}

/// The splash picture itself: the purple court, the white GameAll wordmark and "Manage · Book · Grow". It has no dependencies on
/// Supabase or the router, so `main()` can show it in the very first frame while the backend starts up behind it. The fade-in plays
/// once per launch: when the router later shows the same picture, it is already fully in.
class SplashView extends StatefulWidget {
  const SplashView({super.key});

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView> with SingleTickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
    value: _introPlayed ? 1 : 0,
  );

  @override
  void initState() {
    super.initState();
    if (!_introPlayed) {
      _introPlayed = true;
      _intro.forward();
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final fade = CurvedAnimation(parent: _intro, curve: Curves.easeOutCubic);
    return Scaffold(
      backgroundColor: const Color(0xFF2A0E6B),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // The court photo, tinted into the brand purple. Decoded at screen size, not full size, so it paints on the first frame.
          Image.asset(
            'assets/images/live_court_hero.png',
            fit: BoxFit.cover,
            alignment: Alignment.centerRight,
            cacheWidth: 1080,
            gaplessPlayback: true,
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xE62A0E6B), Color(0xB84817C2), Color(0xF21B0B4B)],
                stops: [0, 0.5, 1],
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: FadeTransition(
                opacity: fade,
                child: SlideTransition(
                  position: Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero).animate(fade),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset('assets/images/gameall_logo_white.png', width: width * 0.62, gaplessPlayback: true),
                      const SizedBox(height: 22),
                      const Text(
                        'Manage · Book · Grow',
                        style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: 0.3),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Your Sports Facility',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.82), fontSize: 14, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The router's splash route. Shows [SplashView] and lifts [splashGate] once the total hold time since launch has passed, so the
/// router (app_router.dart) can move on.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  Timer? _hold;

  @override
  void initState() {
    super.initState();
    markSplashStart();
    final left = splashHold - _sinceLaunch.elapsed;
    if (left <= Duration.zero) {
      // Startup already took longer than the hold: go as soon as the first frame is up.
      WidgetsBinding.instance.addPostFrameCallback((_) => splashGate.value = true);
    } else {
      _hold = Timer(left, () => splashGate.value = true);
    }
  }

  @override
  void dispose() {
    _hold?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SplashView();
}
