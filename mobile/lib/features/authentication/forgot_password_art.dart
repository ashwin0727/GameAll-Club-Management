import 'dart:math' as math;

import 'package:flutter/material.dart';

const _violet = Color(0xFF6D3FE0);
const _purple = Color(0xFF4817C2);
const _deep = Color(0xFF3B14A0);
const _soft = Color(0xFFEFE7FF);

/// The picture under the Forgot Password form: a tilted phone showing a padlock and a masked password, with a refresh badge, leaves and
/// a soft cloud behind it.
///
/// If the finished artwork is added to the project as `assets/images/forgot_password_art.png`, that picture is shown instead and this
/// drawing is only the fallback, so the real artwork can be dropped in without touching any code.
class ForgotPasswordArt extends StatelessWidget {
  const ForgotPasswordArt({super.key, this.width = 300});

  static const assetPath = 'assets/images/forgot_password_art.png';

  final double width;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'A phone with a padlock and a password reset badge',
      child: SizedBox(
        width: width,
        child: Image.asset(
          assetPath,
          width: width,
          fit: BoxFit.fitWidth,
          errorBuilder: (context, error, stack) => SizedBox(
            width: width,
            height: width * 270 / 320,
            child: const CustomPaint(painter: _ArtPainter()),
          ),
        ),
      ),
    );
  }
}

class _ArtPainter extends CustomPainter {
  const _ArtPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 320);

    // The cloud behind everything.
    final cloud = Paint()..color = _soft;
    canvas.drawOval(const Rect.fromLTWH(46, 52, 228, 168), cloud);
    canvas.drawOval(const Rect.fromLTWH(34, 96, 120, 100), cloud);
    canvas.drawOval(const Rect.fromLTWH(180, 74, 100, 122), Paint()..color = const Color(0xFFE9DFFF));

    // The shadow on the ground.
    canvas.drawOval(
      const Rect.fromLTWH(60, 226, 210, 24),
      Paint()
        ..color = _purple.withValues(alpha: 0.16)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );

    _leaf(canvas, const Offset(78, 196), 62, -0.5, const [Color(0xFFB79CFF), Color(0xFF8E63E8)]);
    _leaf(canvas, const Offset(96, 206), 54, -0.1, const [Color(0xFFC9B5FF), Color(0xFF9F7BEA)]);
    _leaf(canvas, const Offset(246, 204), 56, 0.55, const [Color(0xFFD5C6FF), Color(0xFFB79CFF)]);
    _leaf(canvas, const Offset(232, 212), 46, 0.2, const [Color(0xFFDCCFFF), Color(0xFFB79CFF)]);

    // The phone, tilted: a darker slab behind gives it thickness.
    canvas.save();
    canvas.translate(160, 130);
    canvas.rotate(0.2);
    final frame = RRect.fromRectAndRadius(const Rect.fromLTWH(-56, -104, 112, 204), const Radius.circular(24));
    canvas.drawRRect(frame.shift(const Offset(10, 4)), Paint()..color = _deep);
    canvas.drawRRect(frame, Paint()..color = _purple);
    final screen = RRect.fromRectAndRadius(const Rect.fromLTWH(-49, -97, 98, 190), const Radius.circular(19));
    canvas.drawRRect(
      screen,
      Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFF3EEFF), Color(0xFFD9CBF8)]).createShader(const Rect.fromLTWH(-49, -97, 98, 190)),
    );
    // the notch
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-20, -97, 40, 11), const Radius.circular(6)), Paint()..color = _purple);

    // the padlock
    final shackle = Path()
      ..moveTo(-12, -22)
      ..lineTo(-12, -34)
      ..arcToPoint(const Offset(12, -34), radius: const Radius.circular(12), clockwise: true)
      ..lineTo(12, -22);
    canvas.drawPath(
      shackle,
      Paint()
        ..color = _violet
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round,
    );
    final lock = RRect.fromRectAndRadius(const Rect.fromLTWH(-24, -24, 48, 42), const Radius.circular(9));
    canvas.drawRRect(lock, Paint()..shader = const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF8A5CF0), _purple]).createShader(const Rect.fromLTWH(-24, -24, 48, 42)));
    canvas.drawCircle(const Offset(0, -6), 5.5, Paint()..color = Colors.white);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-2.2, -4, 4.4, 14), const Radius.circular(2.2)), Paint()..color = Colors.white);

    // the masked password
    final pill = RRect.fromRectAndRadius(const Rect.fromLTWH(-44, 36, 94, 26), const Radius.circular(13));
    canvas.drawRRect(
      pill.shift(const Offset(0, 3)),
      Paint()
        ..color = _purple.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawRRect(pill, Paint()..color = Colors.white);
    final star = Paint()
      ..color = _purple
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 5; i++) {
      final c = Offset(-28 + i * 15.0, 52);
      for (var k = 0; k < 3; k++) {
        final ang = k * math.pi / 3;
        final d = Offset(math.cos(ang), math.sin(ang)) * 4.6;
        canvas.drawLine(c - d, c + d, star);
      }
    }
    canvas.restore();

    // the refresh badge, overlapping the phone's bottom-right corner
    const badge = Offset(214, 186);
    canvas.drawCircle(badge.translate(0, 4), 34, Paint()..color = _purple.withValues(alpha: 0.2)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7));
    canvas.drawCircle(badge, 34, Paint()..color = Colors.white);
    canvas.drawCircle(badge, 29, Paint()..shader = const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF8A5CF0), _purple]).createShader(Rect.fromCircle(center: badge, radius: 29)));
    final arrows = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: badge, radius: 14), math.pi * 0.15, math.pi * 0.72, false, arrows);
    canvas.drawArc(Rect.fromCircle(center: badge, radius: 14), math.pi * 1.15, math.pi * 0.72, false, arrows);
    _arrowHead(canvas, badge, 14, math.pi * 0.87, true);
    _arrowHead(canvas, badge, 14, math.pi * 1.87, true);

    // the little "ping" strokes at the top right
    final ping = Paint()
      ..color = _violet
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(214, 26), const Offset(210, 14), ping);
    canvas.drawLine(const Offset(226, 36), const Offset(236, 28), ping);
    canvas.drawLine(const Offset(228, 52), const Offset(240, 52), ping);

    canvas.restore();
  }

  /// A leaf: a pointed oval rising from [base], [length] tall, leaning by [lean] radians.
  void _leaf(Canvas canvas, Offset base, double length, double lean, List<Color> colors) {
    canvas.save();
    canvas.translate(base.dx, base.dy);
    canvas.rotate(lean);
    final path = Path()
      ..moveTo(0, 0)
      ..cubicTo(-length * 0.34, -length * 0.3, -length * 0.3, -length * 0.8, 0, -length)
      ..cubicTo(length * 0.3, -length * 0.8, length * 0.34, -length * 0.3, 0, 0)
      ..close();
    canvas.drawPath(path, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: colors).createShader(Rect.fromLTWH(-length * 0.4, -length, length * 0.8, length)));
    canvas.drawLine(Offset.zero, Offset(0, -length * 0.85), Paint()..color = Colors.white.withValues(alpha: 0.35)..strokeWidth = 1.4);
    canvas.restore();
  }

  void _arrowHead(Canvas canvas, Offset center, double r, double angle, bool _) {
    final tip = center + Offset(math.cos(angle) * r, math.sin(angle) * r);
    final tangent = angle + math.pi / 2;
    final a = tip + Offset(math.cos(tangent - 0.5) * 8, math.sin(tangent - 0.5) * 8);
    final b = tip + Offset(math.cos(tangent + 2.2) * 8, math.sin(tangent + 2.2) * 8);
    canvas.drawPath(Path()..moveTo(tip.dx, tip.dy)..lineTo(a.dx, a.dy)..lineTo(b.dx, b.dy)..close(), Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
