import 'package:flutter/material.dart';

/// Which picture an intro page shows.
enum IntroArtKind { bookings, growth, otpPhone, otpEmail }

const _violet = Color(0xFF6D3FE0);
const _purple = Color(0xFF4817C2);
const _lavender = Color(0xFFEFE7FF);
const _cell = Color(0xFFE4DAFB);
const _amber = Color(0xFFF5A33A);

/// The two intro illustrations, drawn in code so they stay sharp on any screen and use the brand purple: a calendar with a clock
/// (bookings) and rising bars with an arrow (growth). Both are drawn on a 240 x 200 canvas.
class IntroArt extends StatelessWidget {
  const IntroArt({super.key, required this.kind, this.width = 270});

  final IntroArtKind kind;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: switch (kind) {
        IntroArtKind.bookings => 'A calendar with a clock',
        IntroArtKind.growth => 'Rising bars with an upward arrow',
        IntroArtKind.otpPhone => 'A phone receiving a message',
        IntroArtKind.otpEmail => 'An email with a tick',
      },
      child: SizedBox(
        width: width,
        height: width * 200 / 240,
        child: CustomPaint(painter: _ArtPainter(kind)),
      ),
    );
  }
}

class _ArtPainter extends CustomPainter {
  const _ArtPainter(this.kind);

  final IntroArtKind kind;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 240;
    canvas.save();
    canvas.scale(k);

    // The soft lavender backdrop.
    canvas.drawOval(const Rect.fromLTWH(26, 22, 188, 168), Paint()..color = _lavender);
    canvas.drawOval(const Rect.fromLTWH(118, 110, 100, 78), Paint()..color = const Color(0xFFE6DAFF).withValues(alpha: 0.7));

    switch (kind) {
      case IntroArtKind.bookings:
        _bookings(canvas);
        _sparkle(canvas, const Offset(206, 50), 9, _amber);
        _sparkle(canvas, const Offset(220, 76), 5, _amber);
      case IntroArtKind.growth:
        _growth(canvas);
      case IntroArtKind.otpPhone:
        _otpPhone(canvas);
        _sparkle(canvas, const Offset(58, 72), 9, _violet);
        _sparkle(canvas, const Offset(46, 96), 4.5, const Color(0xFFB79CFF));
      case IntroArtKind.otpEmail:
        _otpEmail(canvas);
        _sparkle(canvas, const Offset(52, 70), 9, _violet);
        _sparkle(canvas, const Offset(42, 94), 4.5, const Color(0xFFB79CFF));
    }
    canvas.restore();
  }

  void _shadow(Canvas canvas, RRect r) {
    canvas.drawRRect(
      r.shift(const Offset(0, 6)),
      Paint()
        ..color = _purple.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
  }

  void _bookings(Canvas canvas) {
    // The calendar page.
    final page = RRect.fromRectAndRadius(const Rect.fromLTWH(40, 52, 144, 118), const Radius.circular(16));
    _shadow(canvas, page);
    canvas.drawRRect(page, Paint()..color = Colors.white);
    canvas.drawRRect(page, Paint()..color = const Color(0xFFE5E1EF)..style = PaintingStyle.stroke..strokeWidth = 1.5);

    // The purple header, rounded on top only.
    final header = RRect.fromRectAndCorners(
      const Rect.fromLTWH(40, 52, 144, 34),
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
    );
    canvas.drawRRect(
      header,
      Paint()..shader = const LinearGradient(colors: [_violet, _purple]).createShader(const Rect.fromLTWH(40, 52, 144, 34)),
    );

    // The binder rings.
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(70, 40, 9, 24), const Radius.circular(4.5)), Paint()..color = _amber);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(104, 40, 9, 24), const Radius.circular(4.5)), Paint()..color = const Color(0xFF8C6AE8));
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(138, 40, 9, 24), const Radius.circular(4.5)), Paint()..color = const Color(0xFF8C6AE8));

    // The day grid, with one day ticked.
    for (var row = 0; row < 3; row++) {
      for (var col = 0; col < 4; col++) {
        final r = RRect.fromRectAndRadius(Rect.fromLTWH(54 + col * 31.0, 98 + row * 22.0, 24, 15), const Radius.circular(4));
        canvas.drawRRect(r, Paint()..color = _cell);
      }
    }
    final ticked = RRect.fromRectAndRadius(const Rect.fromLTWH(85, 120, 24, 15), const Radius.circular(4));
    canvas.drawRRect(ticked, Paint()..color = Colors.white);
    final tick = Path()
      ..moveTo(91, 127.5)
      ..lineTo(95.5, 132)
      ..lineTo(104, 122);
    canvas.drawPath(
      tick,
      Paint()
        ..color = _purple
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // The clock, overlapping the calendar's corner.
    const c = Offset(178, 144);
    canvas.drawCircle(c.translate(0, 5), 34, Paint()..color = _purple.withValues(alpha: 0.2)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    canvas.drawCircle(c, 34, Paint()..color = Colors.white);
    canvas.drawCircle(c, 30, Paint()..color = _purple..style = PaintingStyle.stroke..strokeWidth = 8);
    final hand = Paint()
      ..color = _purple
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(c, c.translate(0, -17), hand);
    canvas.drawLine(c, c.translate(11, 6), hand);
    canvas.drawCircle(c, 3.5, Paint()..color = _purple);
  }

  void _growth(Canvas canvas) {
    // A soft shadow on the ground under the bars.
    canvas.drawOval(
      const Rect.fromLTWH(54, 158, 132, 10),
      Paint()
        ..color = _purple.withValues(alpha: 0.16)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );

    // Four bars, each taller than the last, in fading lavender.
    const heights = [40.0, 58.0, 72.0, 92.0];
    for (var i = 0; i < heights.length; i++) {
      final left = 62 + i * 33.0;
      final rect = Rect.fromLTWH(left, 160 - heights[i], 26, heights[i]);
      final r = RRect.fromRectAndCorners(rect, topLeft: const Radius.circular(6), topRight: const Radius.circular(6));
      canvas.drawRRect(
        r,
        Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFCDBCF4), Color(0xFFE3D9FA)]).createShader(rect),
      );
    }

    // The arrow: a swoop that dips, then climbs up and to the right.
    final path = Path()
      ..moveTo(58, 98)
      ..cubicTo(98, 112, 146, 102, 182, 62);
    canvas.drawPath(
      path,
      Paint()
        ..color = _purple
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round,
    );
    // The head, pointing the way the swoop ends (up and to the right).
    const tip = Offset(190, 52);
    final head = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(tip.dx - 20, tip.dy + 2)
      ..lineTo(tip.dx - 4, tip.dy + 20)
      ..close();
    canvas.drawPath(head, Paint()..color = _purple);
    canvas.drawPath(head, Paint()..color = _purple..style = PaintingStyle.stroke..strokeWidth = 3..strokeJoin = StrokeJoin.round);
  }

  void _otpPhone(Canvas canvas) {
    // The phone.
    final body = RRect.fromRectAndRadius(const Rect.fromLTWH(78, 26, 70, 124), const Radius.circular(14));
    _shadow(canvas, body);
    canvas.drawRRect(body, Paint()..color = Colors.white);
    canvas.drawRRect(body, Paint()..color = _purple..style = PaintingStyle.stroke..strokeWidth = 6);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(86, 40, 54, 92), const Radius.circular(6)), Paint()..color = const Color(0xFFF3EEFF));
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(102, 32, 22, 4), const Radius.circular(2)), Paint()..color = _purple);
    canvas.drawCircle(const Offset(113, 142), 3.2, Paint()..color = _cell);

    // The message bubble, overlapping the phone's top-right corner.
    final bubble = RRect.fromRectAndRadius(const Rect.fromLTWH(122, 54, 70, 44), const Radius.circular(14));
    _shadow(canvas, bubble);
    final tail = Path()
      ..moveTo(134, 96)
      ..lineTo(128, 112)
      ..lineTo(150, 98)
      ..close();
    final fill = Paint()..shader = const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [_violet, _purple]).createShader(const Rect.fromLTWH(122, 54, 70, 60));
    canvas.drawPath(tail, fill);
    canvas.drawRRect(bubble, fill);
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(Offset(142 + i * 14.0, 76), 4.2, Paint()..color = Colors.white);
    }
  }

  void _otpEmail(Canvas canvas) {
    // The envelope.
    final env = RRect.fromRectAndRadius(const Rect.fromLTWH(56, 62, 128, 88), const Radius.circular(14));
    _shadow(canvas, env);
    canvas.drawRRect(env, Paint()..color = Colors.white);
    canvas.drawRRect(env, Paint()..color = _purple..style = PaintingStyle.stroke..strokeWidth = 6);
    final flap = Path()
      ..moveTo(62, 72)
      ..lineTo(120, 114)
      ..lineTo(178, 72);
    canvas.drawPath(
      flap,
      Paint()
        ..color = _purple
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // The tick badge on the top-right corner.
    const c = Offset(176, 62);
    canvas.drawCircle(c.translate(0, 3), 20, Paint()..color = _purple.withValues(alpha: 0.2)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
    canvas.drawCircle(c, 20, Paint()..shader = const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [_violet, _purple]).createShader(Rect.fromCircle(center: c, radius: 20)));
    final tick = Path()
      ..moveTo(c.dx - 8, c.dy + 1)
      ..lineTo(c.dx - 2, c.dy + 7)
      ..lineTo(c.dx + 9, c.dy - 6);
    canvas.drawPath(
      tick,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _sparkle(Canvas canvas, Offset c, double r, Color color) {
    final p = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r)
      ..close();
    canvas.drawPath(p, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_ArtPainter old) => old.kind != kind;
}
