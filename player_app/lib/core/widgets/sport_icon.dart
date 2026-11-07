import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The kinds of sport the app draws its own icon for.
enum SportKind { football, cricket, badminton, tennis, basketball, pickleball, padel, volleyball, tableTennis, squash, other }

/// The icon kind for a sport name as the database spells it ("Badminton", "Football (5v5)", "Box Cricket"...).
SportKind sportKindOf(String? sport) {
  final s = (sport ?? '').toLowerCase();
  if (s.contains('badminton') || s.contains('shuttle')) return SportKind.badminton;
  if (s.contains('foot') || s.contains('soccer') || s.contains('futsal')) return SportKind.football;
  if (s.contains('cricket')) return SportKind.cricket;
  if (s.contains('table tennis') || s.contains('ping')) return SportKind.tableTennis;
  if (s.contains('pickle')) return SportKind.pickleball;
  if (s.contains('padel')) return SportKind.padel;
  if (s.contains('squash')) return SportKind.squash;
  if (s.contains('tennis')) return SportKind.tennis;
  if (s.contains('basket')) return SportKind.basketball;
  if (s.contains('volley')) return SportKind.volleyball;
  return SportKind.other;
}

/// A hand-drawn sport icon: a duotone line drawing (the outline in [color], the main shape softly filled), crisp at any size and
/// in Dark and Light. Replaces the generic Material sport icons, which show a tennis racquet for badminton and a score sheet for
/// anything unknown.
class SportIcon extends StatelessWidget {
  const SportIcon(this.sport, {super.key, this.size = 20, required this.color});

  /// The sport name, e.g. "Badminton".
  final String? sport;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final kind = sportKindOf(sport);
    // badminton (the shuttlecock) and padel (the padel racket) are pictures from assets/images, tinted like the other icons
    if (kind == SportKind.badminton) return CorkIcon(size: size, color: color);
    if (kind == SportKind.padel) return PadelIcon(size: size, color: color);
    return ExcludeSemantics(
      child: CustomPaint(size: Size.square(size), painter: SportIconPainter(kind, color)),
    );
  }
}

/// An icon that is a picture (a white drawing on a clear background), coloured with [color] so it follows the Dark / Light theme and the
/// selected state like every other icon.
class SportPictureIcon extends StatelessWidget {
  const SportPictureIcon(this.asset, {super.key, this.size = 20, required this.color});

  final String asset;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Image.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      color: color,
      colorBlendMode: BlendMode.srcIn,
      filterQuality: FilterQuality.high,
    ),
  );
}

/// The badminton icon: the shuttlecock (assets/images/cork.png).
class CorkIcon extends StatelessWidget {
  const CorkIcon({super.key, this.size = 20, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      SportPictureIcon('assets/images/cork.png', size: size, color: color);
}

/// The padel icon: the same shuttlecock picture as badminton (assets/images/cork.png).
class PadelIcon extends StatelessWidget {
  const PadelIcon({super.key, this.size = 20, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      SportPictureIcon('assets/images/cork.png', size: size, color: color);
}

class SportIconPainter extends CustomPainter {
  const SportIconPainter(this.kind, this.color);

  final SportKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    final soft = Paint()
      ..style = PaintingStyle.fill
      ..color = color.withValues(alpha: 0.28);
    final solid = Paint()
      ..style = PaintingStyle.fill
      ..color = color;
    switch (kind) {
      case SportKind.football:
        _football(canvas, line, soft);
      case SportKind.cricket:
        _cricket(canvas, line, soft, solid);
      case SportKind.badminton:
        _badminton(canvas, line, soft, solid);
      case SportKind.tennis:
        _tennis(canvas, line, soft);
      case SportKind.basketball:
        _basketball(canvas, line, soft);
      case SportKind.pickleball:
        _pickleball(canvas, line, soft, solid);
      case SportKind.padel:
        _padel(canvas, line, soft, solid);
      case SportKind.volleyball:
        _volleyball(canvas, line, soft);
      case SportKind.tableTennis:
        _tableTennis(canvas, line, soft, solid);
      case SportKind.squash:
        _squash(canvas, line, soft, solid);
      case SportKind.other:
        _other(canvas, line, soft, solid);
    }
    canvas.restore();
  }

  // ── helpers ───────────────────────────────────────────────────────────

  static Offset _polar(Offset c, double r, double degrees) => Offset(c.dx + r * math.cos(degrees * math.pi / 180), c.dy + r * math.sin(degrees * math.pi / 180));

  void _rotated(Canvas canvas, Offset pivot, double degrees, void Function() draw) {
    canvas.save();
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(degrees * math.pi / 180);
    canvas.translate(-pivot.dx, -pivot.dy);
    draw();
    canvas.restore();
  }

  void _ball(Canvas canvas, Offset c, double r, Paint line, Paint soft) {
    canvas.drawCircle(c, r, soft);
    canvas.drawCircle(c, r, line);
  }

  // ── the sports ────────────────────────────────────────────────────────

  /// A football: black-and-white ball, drawn as a circle with a pentagon in the middle and seams to the edge.
  void _football(Canvas canvas, Paint line, Paint soft) {
    const c = Offset(12, 12);
    canvas.drawCircle(c, 9.4, line);
    final pent = Path();
    for (var i = 0; i < 5; i++) {
      final p = _polar(c, 3.4, -90 + i * 72);
      i == 0 ? pent.moveTo(p.dx, p.dy) : pent.lineTo(p.dx, p.dy);
    }
    pent.close();
    canvas.drawPath(pent, soft);
    canvas.drawPath(pent, line);
    for (var i = 0; i < 5; i++) {
      final a = -90 + i * 72;
      canvas.drawLine(_polar(c, 3.4, a.toDouble()), _polar(c, 6.2, a.toDouble()), line);
      // a short edge piece either side of the seam, so the outer panels read
      final tip = _polar(c, 6.2, a.toDouble());
      canvas.drawLine(tip, _polar(c, 9.4, a + 30.0), line);
      canvas.drawLine(tip, _polar(c, 9.4, a - 30.0), line);
    }
  }

  /// Cricket: a bat leaning across, with the ball at its foot.
  void _cricket(Canvas canvas, Paint line, Paint soft, Paint solid) {
    _rotated(canvas, const Offset(10, 12), 38, () {
      // handle
      canvas.drawLine(const Offset(10, 1.6), const Offset(10, 7), line);
      // blade
      final blade = RRect.fromRectAndRadius(const Rect.fromLTWH(6.9, 7, 6.2, 14.6), const Radius.circular(1.8));
      canvas.drawRRect(blade, soft);
      canvas.drawRRect(blade, line);
      canvas.drawLine(const Offset(10, 9.5), const Offset(10, 18.5), line..strokeWidth = 1.1);
      line.strokeWidth = 1.7;
    });
    canvas.drawCircle(const Offset(18.2, 17.8), 3.2, solid);
    canvas.drawArc(Rect.fromCircle(center: const Offset(18.2, 17.8), radius: 1.9), 0.9, 2.2, false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.75));
  }

  /// Badminton: a racket (oval head with strings, and a handle) at the lower left and a shuttlecock flying off to the upper right.
  void _badminton(Canvas canvas, Paint line, Paint soft, Paint solid) {
    // the racket, drawn upright then tilted, and moved down and to the left to make room for the shuttlecock
    canvas.save();
    canvas.translate(-2.4, 2.6);
    _rotated(canvas, const Offset(9, 12), 42, () {
      final head = Rect.fromCenter(center: const Offset(9, 8.2), width: 7.4, height: 10.2);
      canvas.drawOval(head, soft);
      canvas.drawOval(head, line);
      final strings = line..strokeWidth = 0.8;
      canvas.save();
      canvas.clipPath(Path()..addOval(head));
      for (final x in const [7.2, 9.0, 10.8]) {
        canvas.drawLine(Offset(x, 3.0), Offset(x, 13.4), strings);
      }
      for (final y in const [5.4, 7.8, 10.2]) {
        canvas.drawLine(Offset(5.2, y), Offset(12.8, y), strings);
      }
      canvas.restore();
      line.strokeWidth = 1.7;
      // throat and handle
      canvas.drawLine(const Offset(9, 13.3), const Offset(9, 21.2), line..strokeWidth = 1.9);
      line.strokeWidth = 1.7;
    });
    canvas.restore();
    // the shuttlecock: cork nearest the racket, feathers fanning away
    canvas.save();
    canvas.translate(2.4, -1.6);
    _rotated(canvas, const Offset(16.2, 8.6), 42, () {
      final skirt = Path()
        ..moveTo(15.2, 8.0)
        ..lineTo(13.6, 1.8)
        ..quadraticBezierTo(16.2, 0.6, 18.8, 1.8)
        ..lineTo(17.2, 8.0)
        ..close();
      canvas.drawPath(skirt, soft);
      canvas.drawPath(skirt, line..strokeWidth = 1.3);
      final feather = line..strokeWidth = 0.9;
      canvas.drawLine(const Offset(16.2, 8.0), const Offset(16.2, 1.4), feather);
      canvas.drawLine(const Offset(15.7, 8.0), const Offset(14.9, 1.6), feather);
      canvas.drawLine(const Offset(16.7, 8.0), const Offset(17.5, 1.6), feather);
      line.strokeWidth = 1.7;
      canvas.drawCircle(const Offset(16.2, 9.6), 1.7, solid);
    });
    canvas.restore();
  }

  /// Tennis: a ball with its two curved seams.
  void _tennis(Canvas canvas, Paint line, Paint soft) {
    _ball(canvas, const Offset(12, 12), 9.4, line, soft);
    final left = Path()
      ..moveTo(4.9, 5.2)
      ..cubicTo(10.6, 8.2, 10.6, 15.8, 4.9, 18.8);
    final right = Path()
      ..moveTo(19.1, 5.2)
      ..cubicTo(13.4, 8.2, 13.4, 15.8, 19.1, 18.8);
    canvas.drawPath(left, line);
    canvas.drawPath(right, line);
  }

  /// Basketball: a ball with the cross seams and two side curves.
  void _basketball(Canvas canvas, Paint line, Paint soft) {
    _ball(canvas, const Offset(12, 12), 9.4, line, soft);
    canvas.drawLine(const Offset(12, 2.6), const Offset(12, 21.4), line);
    canvas.drawLine(const Offset(2.6, 12), const Offset(21.4, 12), line);
    final left = Path()
      ..moveTo(5.3, 4.9)
      ..cubicTo(9.4, 8.4, 9.4, 15.6, 5.3, 19.1);
    final right = Path()
      ..moveTo(18.7, 4.9)
      ..cubicTo(14.6, 8.4, 14.6, 15.6, 18.7, 19.1);
    canvas.drawPath(left, line..strokeWidth = 1.3);
    canvas.drawPath(right, line);
    line.strokeWidth = 1.7;
  }

  /// Pickleball: a solid paddle with a handle, and a perforated ball.
  void _pickleball(Canvas canvas, Paint line, Paint soft, Paint solid) {
    _rotated(canvas, const Offset(10, 11), -35, () {
      final face = RRect.fromRectAndRadius(const Rect.fromLTWH(4.6, 2.2, 10.8, 11.8), const Radius.circular(4.6));
      canvas.drawRRect(face, soft);
      canvas.drawRRect(face, line);
      canvas.drawLine(const Offset(10, 14), const Offset(10, 19.6), line..strokeWidth = 2.6);
      line.strokeWidth = 1.7;
    });
    const ball = Offset(18, 17.6);
    canvas.drawCircle(ball, 4, soft);
    canvas.drawCircle(ball, 4, line..strokeWidth = 1.4);
    line.strokeWidth = 1.7;
    for (final d in const [Offset(-1.3, -1.2), Offset(1.4, -0.6), Offset(-0.2, 1.4)]) {
      canvas.drawCircle(ball + d, 0.55, solid);
    }
  }

  /// Padel: a round-headed racket with holes, and a small ball.
  void _padel(Canvas canvas, Paint line, Paint soft, Paint solid) {
    _rotated(canvas, const Offset(10, 10), -35, () {
      final head = RRect.fromRectAndRadius(const Rect.fromLTWH(4.2, 1.8, 11.6, 12.4), const Radius.circular(5.8));
      canvas.drawRRect(head, soft);
      canvas.drawRRect(head, line);
      canvas.drawLine(const Offset(10, 14.2), const Offset(10, 20.4), line..strokeWidth = 2.6);
      line.strokeWidth = 1.7;
      for (final p in const [Offset(8, 5.2), Offset(12, 5.2), Offset(10, 8), Offset(7.4, 10.4), Offset(12.6, 10.4)]) {
        canvas.drawCircle(p, 0.7, solid);
      }
    });
    canvas.drawCircle(const Offset(19, 18.4), 2.5, solid);
  }

  /// Volleyball: a ball with three curved panels.
  void _volleyball(Canvas canvas, Paint line, Paint soft) {
    _ball(canvas, const Offset(12, 12), 9.4, line, soft);
    final a = Path()
      ..moveTo(12, 2.6)
      ..cubicTo(8.5, 7, 9, 11.5, 14.8, 14.2);
    final b = Path()
      ..moveTo(3.4, 8.2)
      ..cubicTo(8.8, 7.6, 13, 9.6, 15.6, 14.8)
      ..cubicTo(16.6, 17, 16.6, 19, 15.4, 20.6);
    final c = Path()
      ..moveTo(19.6, 7.4)
      ..cubicTo(15.4, 9.4, 12.4, 12.6, 11.6, 17.6)
      ..cubicTo(11.4, 19, 11.6, 20.2, 12, 21.4);
    canvas.drawPath(a, line..strokeWidth = 1.4);
    canvas.drawPath(b, line);
    canvas.drawPath(c, line);
    line.strokeWidth = 1.7;
  }

  /// Table tennis: a round bat with a handle, and the small ball.
  void _tableTennis(Canvas canvas, Paint line, Paint soft, Paint solid) {
    _rotated(canvas, const Offset(10, 10), -35, () {
      canvas.drawCircle(const Offset(10, 8.4), 6.4, soft);
      canvas.drawCircle(const Offset(10, 8.4), 6.4, line);
      canvas.drawLine(const Offset(10, 14.8), const Offset(10, 20.4), line..strokeWidth = 2.6);
      line.strokeWidth = 1.7;
    });
    canvas.drawCircle(const Offset(19, 18.6), 2.4, solid);
  }

  /// Squash: a small-headed racket with strings, and a ball.
  void _squash(Canvas canvas, Paint line, Paint soft, Paint solid) {
    _rotated(canvas, const Offset(10, 10), -35, () {
      final head = RRect.fromRectAndRadius(const Rect.fromLTWH(5.2, 1.6, 9.6, 12.6), const Radius.circular(4.8));
      canvas.drawRRect(head, soft);
      canvas.drawRRect(head, line);
      final strings = line..strokeWidth = 0.9;
      for (final x in const [8.0, 10.0, 12.0]) {
        canvas.drawLine(Offset(x, 3.6), Offset(x, 12.2), strings);
      }
      for (final y in const [5.6, 8.0, 10.4]) {
        canvas.drawLine(Offset(6.4, y), Offset(13.6, y), strings);
      }
      line.strokeWidth = 1.7;
      canvas.drawLine(const Offset(10, 14.2), const Offset(10, 20.4), line);
    });
    canvas.drawCircle(const Offset(19, 18.6), 2.5, solid);
  }

  /// Any other sport: a trophy (a player can still tell it is "sport").
  void _other(Canvas canvas, Paint line, Paint soft, Paint solid) {
    final cup = Path()
      ..moveTo(7, 3.6)
      ..lineTo(17, 3.6)
      ..lineTo(17, 9.4)
      ..quadraticBezierTo(17, 14, 12, 14)
      ..quadraticBezierTo(7, 14, 7, 9.4)
      ..close();
    canvas.drawPath(cup, soft);
    canvas.drawPath(cup, line);
    canvas.drawPath(Path()..moveTo(7, 5.4)..quadraticBezierTo(3.4, 5.4, 3.8, 8.2)..quadraticBezierTo(4.2, 10.6, 7.4, 10.8), line);
    canvas.drawPath(Path()..moveTo(17, 5.4)..quadraticBezierTo(20.6, 5.4, 20.2, 8.2)..quadraticBezierTo(19.8, 10.6, 16.6, 10.8), line);
    canvas.drawLine(const Offset(12, 14), const Offset(12, 18.2), line);
    canvas.drawLine(const Offset(8.4, 20.4), const Offset(15.6, 20.4), line);
    canvas.drawCircle(const Offset(12, 8.6), 1.3, solid);
  }

  @override
  bool shouldRepaint(SportIconPainter old) => old.kind != kind || old.color != color;
}
