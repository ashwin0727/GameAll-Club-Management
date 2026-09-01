import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';

/// Restores the real session/facility state before deciding anything — no
/// arbitrary delay (item 19). go_router's own redirect (see app_router.dart)
/// does the actual navigation once [SessionController] resolves; this
/// screen only needs to render while that's in flight.
///
/// Premium-minimal per spec §"Splash Screen": centered mark, one subtle
/// entrance animation, no loading copy. The animation plays once on mount
/// and settles — it never blocks or delays the redirect above, which can
/// (and often does) fire before the animation even finishes.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: AppMotion.slow)..forward();
  late final Animation<double> _scale = CurvedAnimation(parent: _controller, curve: AppMotion.emphasized);
  late final Animation<double> _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: FadeTransition(
          opacity: _fade,
          child: ScaleTransition(
            scale: _scale,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/images/logo-icon.png', width: 88, height: 88),
                const SizedBox(height: 20),
                const Text(
                  'GameAll',
                  style: TextStyle(color: AppColors.foreground, fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.5),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Club Management',
                  style: TextStyle(color: AppColors.muted, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}