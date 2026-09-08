import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../core/routing/app_router.dart';

/// The branded splash clip, created once and warmed from `main()` so it's
/// ready to play the instant the splash appears.
final VideoPlayerController splashVideo =
    VideoPlayerController.asset('assets/splash.mp4');
Future<void>? _warm;
Future<void> warmSplashVideo() =>
    _warm ??= splashVideo.initialize().catchError((_) {});

/// Cold-start splash. Fades the branded clip in, plays it through full-frame
/// on black, then lifts [splashGate] so the router (app_router.dart) moves on.
/// A safety timeout covers a stuck clip.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  Timer? _timeout;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _timeout = Timer(const Duration(seconds: 6), _finish);
    _start();
  }

  Future<void> _start() async {
    await warmSplashVideo();
    if (_done || !mounted) return;
    final c = splashVideo;
    if (!c.value.isInitialized) {
      _finish();
      return;
    }
    try {
      c
        ..setVolume(0)
        ..addListener(_onTick);
      await c.play();
      if (mounted) setState(() {});
    } catch (_) {
      _finish();
    }
  }

  void _onTick() {
    final c = splashVideo;
    if (!c.value.isInitialized) return;
    final ended = c.value.duration > Duration.zero &&
        c.value.position >= c.value.duration;
    if (ended || c.value.hasError) _finish();
  }

  void _finish() {
    if (_done) return;
    _done = true;
    _timeout?.cancel();
    splashGate.value = true;
  }

  @override
  void dispose() {
    splashVideo.removeListener(_onTick);
    splashVideo.dispose();
    _timeout?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = splashVideo;
    final ready = c.value.isInitialized;
    return Scaffold(
      backgroundColor: Colors.black,
      body: AnimatedOpacity(
        opacity: ready ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOut,
        child: ready
            ? Center(
                // Medium size, and the bottom ~18% clipped so the corner
                // watermark is never shown — biased up a touch so the mark
                // stays centred in what's left.
                child: SizedBox(
                  width: MediaQuery.of(context).size.shortestSide * 0.62,
                  child: AspectRatio(
                    aspectRatio: c.value.aspectRatio / 0.82,
                    child: ClipRect(
                      child: Align(
                        alignment: const Alignment(0, -0.35),
                        heightFactor: 0.82,
                        child: AspectRatio(
                          aspectRatio: c.value.aspectRatio,
                          child: VideoPlayer(c),
                        ),
                      ),
                    ),
                  ),
                ),
              )
            : const SizedBox.expand(),
      ),
    );
  }
}
