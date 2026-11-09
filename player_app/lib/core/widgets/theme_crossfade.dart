import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Makes a light / dark switch smooth.
///
/// Animating the theme itself re-lays-out and repaints the whole page on every frame for a quarter of a second, which is what made
/// the pages seem to shrink and shake. Instead the new theme is applied at once, and a picture of the page as it was just before is
/// faded away on top: one cheap image fade, no layout work, the same on every page (it sits above the Navigator).
class ThemeCrossfade extends StatefulWidget {
  const ThemeCrossfade({
    super.key,
    required this.mode,
    required this.child,
    this.duration = const Duration(milliseconds: 380),
  });

  /// Any value that changes when the theme does.
  final Object mode;
  final Widget child;
  final Duration duration;

  @override
  State<ThemeCrossfade> createState() => _ThemeCrossfadeState();
}

class _ThemeCrossfadeState extends State<ThemeCrossfade>
    with SingleTickerProviderStateMixin {
  final _boundary = GlobalKey();
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: widget.duration,
  )..addStatusListener(_done);
  ui.Image? _old;

  @override
  void didUpdateWidget(ThemeCrossfade old) {
    super.didUpdateWidget(old);
    if (old.mode == widget.mode) return;
    // The page has not been repainted yet in this frame, so the boundary still holds the previous look.
    try {
      final box = _boundary.currentContext?.findRenderObject();
      if (box is RenderRepaintBoundary && box.hasSize) {
        final ratio = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 2.0);
        _old?.dispose();
        _old = box.toImageSync(pixelRatio: ratio);
        _fade.value = 1;
        _fade.reverse();
      }
    } catch (_) {
      _old = null; // no picture: the switch is simply instant
    }
  }

  void _done(AnimationStatus s) {
    if (s == AnimationStatus.dismissed && _old != null) {
      setState(() {
        _old?.dispose();
        _old = null;
      });
    }
  }

  @override
  void dispose() {
    _fade.dispose();
    _old?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final old = _old;
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(key: _boundary, child: widget.child),
        if (old != null)
          Positioned.fill(
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: FadeTransition(
                  opacity: CurvedAnimation(
                    parent: _fade,
                    curve: Curves.easeInOut,
                  ),
                  child: RawImage(image: old, fit: BoxFit.fill),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
