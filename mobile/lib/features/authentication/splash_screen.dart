import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/routing/app_router.dart';

/// How long the splash stays up in total, counted from the moment the app process started drawing it. The light show itself
/// ([_showLength]) finishes a little before this, so the finished logo is held for a beat before the app opens.
const splashHold = Duration(milliseconds: 3300);
const _showLength = Duration(milliseconds: 3000);

final Stopwatch _sinceLaunch = Stopwatch();
bool _introPlayed = false;

/// Called first thing in `main()`, so the hold time counts from launch and not from when the router first shows the splash.
void markSplashStart() {
  if (!_sinceLaunch.isRunning) _sinceLaunch.start();
}

/// The splash picture: a dark court that comes alive. A stadium lamp flickers on at the top and throws a spotlight cone down, the
/// court floods with light, and the white GameAll wordmark switches on with a sweep of light, followed by the two taglines.
/// It has no dependencies on Supabase or the router, so `main()` can show it in the very first frame while the backend starts up
/// behind it. The show plays once per launch: when the router later shows the same picture, it is already complete. With
/// "remove animations" turned on, it shows the finished picture straight away.
class SplashView extends StatefulWidget {
  const SplashView({super.key});

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView> with SingleTickerProviderStateMixin {
  late final AnimationController _show;

  @override
  void initState() {
    super.initState();
    // Decide before anything flips the flag: the first splash of the launch plays the show, any later one is already complete.
    final alreadyPlayed = _introPlayed;
    _introPlayed = true;
    _show = AnimationController(vsync: this, duration: _showLength, value: alreadyPlayed ? 1 : 0);
    if (!alreadyPlayed) _show.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) _show.value = 1;
  }

  @override
  void dispose() {
    _show.dispose();
    super.dispose();
  }

  /// 0 to 1 over the slice [from]..[to] of the show, eased.
  static double _seg(double t, double from, double to, [Curve curve = Curves.easeOutCubic]) =>
      curve.transform(((t - from) / (to - from)).clamp(0.0, 1.0));

  /// The lamp coming on: a few quick flickers in the first half second, then steady.
  static final TweenSequence<double> _flicker = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.9), weight: 10),
    TweenSequenceItem(tween: Tween(begin: 0.9, end: 0.15), weight: 8),
    TweenSequenceItem(tween: Tween(begin: 0.15, end: 1.0), weight: 9),
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.45), weight: 6),
    TweenSequenceItem(tween: Tween(begin: 0.45, end: 1.0), weight: 12),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 55),
  ]);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: const Color(0xFF12062E),
      body: AnimatedBuilder(
        animation: _show,
        builder: (context, _) {
          final t = _show.value;
          final lamp = _flicker.transform(_seg(t, 0.0, 0.2, Curves.linear));
          final flood = _seg(t, 0.12, 0.45, Curves.easeInOutCubic);
          final logoIn = _seg(t, 0.33, 0.62);
          final sweep = _seg(t, 0.4, 0.78, Curves.easeInOutCubic);
          final tag1 = _seg(t, 0.58, 0.76);
          final tag2 = _seg(t, 0.66, 0.84);
          final glowPulse = _seg(t, 0.5, 0.72) * (1 - _seg(t, 0.78, 1.0));
          return Stack(
            fit: StackFit.expand,
            children: [
              // The court, slowly settling in from a slight zoom, brightening as the lights flood it.
              Opacity(
                opacity: flood,
                child: Transform.scale(
                  scale: 1.1 - 0.1 * Curves.easeOutCubic.transform(t),
                  child: Image.asset(
                    'assets/images/live_court_hero.png',
                    fit: BoxFit.cover,
                    alignment: Alignment.centerRight,
                    cacheWidth: 1080,
                    gaplessPlayback: true,
                  ),
                ),
              ),
              // The purple wash: nearly black at the start, lifting as the court lights up.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color.lerp(const Color(0xFF12062E), const Color(0xE62A0E6B), flood)!,
                      Color.lerp(const Color(0xF212062E), const Color(0xB84817C2), flood)!,
                      Color.lerp(const Color(0xFF12062E), const Color(0xF21B0B4B), flood)!,
                    ],
                    stops: const [0, 0.5, 1],
                  ),
                ),
              ),
              // The lamp, its spotlight cone and the drifting dust in the beam.
              CustomPaint(painter: _SpotlightPainter(intensity: lamp * (0.7 + 0.3 * flood), t: t)),
              // A soft halo behind the wordmark that swells while the logo lights up.
              Center(
                child: Opacity(
                  opacity: (glowPulse * 0.9).clamp(0.0, 1.0),
                  child: Container(
                    width: size.width * 0.95,
                    height: size.width * 0.5,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(colors: [Color(0x66B79CFF), Color(0x00B79CFF)]),
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // The wordmark comes into focus and its letters switch on, left to right, as a band of light sweeps over them.
                      Opacity(
                        opacity: logoIn,
                        child: Transform.scale(
                          scale: 0.9 + 0.1 * logoIn,
                          child: ImageFiltered(
                            imageFilter: ImageFilter.blur(sigmaX: 14 * (1 - logoIn), sigmaY: 14 * (1 - logoIn), tileMode: TileMode.decal),
                            child: ShaderMask(
                              blendMode: BlendMode.srcATop,
                              shaderCallback: (rect) => LinearGradient(
                                colors: const [Colors.white, Colors.white, Color(0xFF9F86E6)],
                                stops: [0, sweep, (sweep + 0.3).clamp(0.0, 1.0)],
                              ).createShader(rect),
                              child: Image.asset('assets/images/gameall_logo_white.png', width: size.width * 0.62, gaplessPlayback: true),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Opacity(
                        opacity: tag1,
                        child: Transform.translate(
                          offset: Offset(0, 14 * (1 - tag1)),
                          child: Text(
                            'Manage · Book · Grow',
                            style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: 0.3 + 4 * (1 - tag1)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Opacity(
                        opacity: tag2,
                        child: Transform.translate(
                          offset: Offset(0, 14 * (1 - tag2)),
                          child: Text(
                            'Your Sports Facility',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.82), fontSize: 14, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The stadium lamp at the top of the screen, the spotlight cone it throws down onto the court, a pool of light on the floor, and a
/// few specks of dust drifting in the beam. [intensity] is 0 (off) to 1 (full); [t] is the show's progress, which moves the dust.
class _SpotlightPainter extends CustomPainter {
  const _SpotlightPainter({required this.intensity, required this.t});

  final double intensity;
  final double t;

  static const _motes = <(double, double, double, double)>[
    // (x across the beam 0..1, start y 0..1, drift speed, size)
    (0.46, 0.18, 0.10, 1.6),
    (0.52, 0.30, 0.14, 1.2),
    (0.40, 0.42, 0.08, 1.8),
    (0.58, 0.50, 0.12, 1.4),
    (0.48, 0.62, 0.09, 1.1),
    (0.55, 0.12, 0.16, 1.0),
    (0.36, 0.55, 0.11, 1.5),
    (0.62, 0.36, 0.07, 1.3),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (intensity <= 0.001) return;
    final cx = size.width / 2;
    final reach = size.height * 0.78;

    // The cone: narrow at the lamp, wide on the floor, brightest at the top.
    final cone = Path()
      ..moveTo(cx - size.width * 0.05, 0)
      ..lineTo(cx + size.width * 0.05, 0)
      ..lineTo(cx + size.width * 0.62, reach)
      ..lineTo(cx - size.width * 0.62, reach)
      ..close();
    canvas.drawPath(
      cone,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white.withValues(alpha: 0.42 * intensity), const Color(0xFFD9C8FF).withValues(alpha: 0.10 * intensity), Colors.transparent],
          stops: const [0, 0.55, 1],
        ).createShader(Rect.fromLTWH(0, 0, size.width, reach))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22),
    );

    // The lamp's glow.
    canvas.drawCircle(
      Offset(cx, 0),
      size.width * 0.5,
      Paint()
        ..shader = RadialGradient(colors: [Colors.white.withValues(alpha: 0.65 * intensity), Colors.transparent])
            .createShader(Rect.fromCircle(center: Offset(cx, 0), radius: size.width * 0.5)),
    );

    // The pool of light on the floor.
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, reach), width: size.width * 1.2, height: size.height * 0.12),
      Paint()
        ..color = const Color(0xFFD9C8FF).withValues(alpha: 0.22 * intensity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 26),
    );

    // Dust in the beam, drifting slowly down and sideways.
    for (final (x, y0, speed, r) in _motes) {
      final y = ((y0 + t * speed * 2.2) % 1.0) * reach;
      final spread = (y / reach) * size.width * 0.5;
      final dx = cx + (x - 0.5) * 2 * spread + 6 * ((t * 3 + y0 * 7) % 1);
      canvas.drawCircle(Offset(dx, y), r, Paint()..color = Colors.white.withValues(alpha: 0.55 * intensity * (1 - y / reach)));
    }
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) => old.intensity != intensity || old.t != t;
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
