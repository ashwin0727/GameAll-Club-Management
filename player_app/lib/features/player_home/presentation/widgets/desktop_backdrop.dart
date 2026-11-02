import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// The background of the wide (web) layout: a deep navy that turns blue towards the bottom-right, a violet glow low in the middle,
/// a blue glow top-right, and thin glowing arcs and streaks (a blue wave bottom-left, a violet-blue wave bottom-right, a streak
/// across the top-right). In Light mode the same shapes are drawn very softly on the light background.
///
/// Purely decorative: it ignores touches and is hidden from screen readers.
///
/// When the page opens, the glowing lines draw themselves in from their outer ends (about a second and a half, easing out) while their
/// glow fades up. It plays once; with "reduce motion" on they are simply there.
class DesktopBackdrop extends StatefulWidget {
  const DesktopBackdrop({super.key});

  @override
  State<DesktopBackdrop> createState() => _DesktopBackdropState();
}

class _DesktopBackdropState extends State<DesktopBackdrop> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1900))..forward();
  // The first 0.4s is a pause, so the lines start drawing just as the page content is landing.
  late final Animation<double> _draw = CurvedAnimation(parent: _controller, curve: const Interval(0.2, 1, curve: Curves.easeInOutCubic));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = context.palette.isDark;
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return IgnorePointer(
      child: ExcludeSemantics(
        child: SizedBox.expand(
          child: CustomPaint(painter: _BackdropPainter(dark: dark, progress: still ? const AlwaysStoppedAnimation(1.0) : _draw)),
        ),
      ),
    );
  }
}

class _BackdropPainter extends CustomPainter {
  _BackdropPainter({required this.dark, required this.progress}) : super(repaint: progress);
  final bool dark;

  /// 0 = no lines yet, 1 = fully drawn.
  final Animation<double> progress;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rect = Offset.zero & size;

    // 1. The base: navy at the top-left, deepening to blue at the bottom-right.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(w, h),
          dark
              ? const [Color(0xFF040D1C), Color(0xFF06142B), Color(0xFF0A1D52)]
              : const [Color(0xFFF7F9FD), Color(0xFFF1F5FC), Color(0xFFE8EFFB)],
          const [0.0, 0.55, 1.0],
        ),
    );

    // 2. Soft light: violet low in the middle, blue at the top-right, a hint of violet at the top-left.
    void glow(Offset c, double r, Color color) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = ui.Gradient.radial(c, r, [
            color,
            color.withValues(alpha: 0),
          ]),
      );
    }

    glow(
      Offset(w * 0.55, h * 0.95),
      w * 0.45,
      AppColors.violet.withValues(alpha: dark ? 0.22 : 0.08),
    );
    glow(
      Offset(w * 0.9, h * 0.1),
      w * 0.4,
      AppColors.blue.withValues(alpha: dark ? 0.20 : 0.07),
    );
    glow(
      Offset(w * 0.05, h * 0.05),
      w * 0.3,
      AppColors.violet.withValues(alpha: dark ? 0.10 : 0.04),
    );

    // 3. The glowing lines. Each is drawn twice: a wide faint stroke (the glow) and a thin bright one.
    void line(
      Path path,
      List<Color> colors,
      Offset from,
      Offset to,
      double width,
    ) {
      final t = progress.value;
      if (t <= 0) return;
      // The line grows along its length; the glow comes up a little faster than the line is drawn.
      final drawn = Path();
      for (final m in path.computeMetrics()) {
        drawn.addPath(m.extractPath(0, m.length * t), Offset.zero);
      }
      final glowAlpha = (t * 1.5).clamp(0.0, 1.0);
      path = drawn;
      // three colours need explicit, evenly spaced stops
      final shader = ui.Gradient.linear(from, to, colors, [
        for (var i = 0; i < colors.length; i++) i / (colors.length - 1),
      ]);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width * 5
          ..shader = shader
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10)
          ..colorFilter = ColorFilter.mode(Colors.white.withValues(alpha: glowAlpha), BlendMode.modulate),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round
          ..shader = shader,
      );
    }

    final a = dark ? 1.0 : 0.55;
    // bottom-left: a blue wave rising from the corner
    final left = Path()
      ..moveTo(-20, h * 0.955)
      ..cubicTo(w * 0.05, h * 0.93, w * 0.12, h * 0.98, w * 0.22, h + 10);
    line(
      left,
      [
        AppColors.blue.withValues(alpha: 0.0),
        AppColors.blue.withValues(alpha: 0.75 * a),
        AppColors.cyan.withValues(alpha: 0.0),
      ],
      Offset(0, h),
      Offset(w * 0.22, h),
      1.4,
    );

    // bottom-right: a violet-to-blue wave
    final right = Path()
      ..moveTo(w * 0.80, h + 10)
      ..cubicTo(w * 0.88, h * 0.98, w * 0.95, h * 0.94, w + 20, h * 0.955);
    line(
      right,
      [
        AppColors.violet.withValues(alpha: 0.0),
        AppColors.violet.withValues(alpha: 0.8 * a),
        AppColors.blue.withValues(alpha: 0.7 * a),
      ],
      Offset(w * 0.80, h),
      Offset(w, h * 0.955),
      1.4,
    );
  }

  @override
  bool shouldRepaint(_BackdropPainter old) => old.dark != dark || old.progress != progress;
}
