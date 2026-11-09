import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'sport_icon.dart';

/// A picture of a court or pitch for a venue that has no photo of its own: an evening scene in perspective with floodlights, the
/// floor in the sport's colours and its real line markings (badminton court and net, striped turf with a goal, cricket pitch,
/// basketball court, tennis court, volleyball court, or a plain multi-sport hall). Drawn in code, so it is sharp at any size, adds
/// nothing to the download and works offline.
class VenueScene extends StatelessWidget {
  const VenueScene({super.key, required this.sport});

  /// The venue's main sport as the database spells it; null draws the plain hall.
  final String? sport;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.expand(
      child: CustomPaint(painter: VenueScenePainter(sportKindOf(sport))),
    ),
  );
}

class VenueScenePainter extends CustomPainter {
  const VenueScenePainter(this.kind);

  final SportKind kind;

  // ── the scene's look per sport ────────────────────────────────────────
  _Look get _look => switch (kind) {
    SportKind.badminton => const _Look(
      floorNear: Color(0xFF1E8A57),
      floorFar: Color(0xFF0F5A3A),
      surround: Color(0xFF0C3B52),
      indoor: true,
    ),
    SportKind.football => const _Look(
      floorNear: Color(0xFF2F9E44),
      floorFar: Color(0xFF1B6B2E),
      surround: Color(0xFF123524),
      indoor: false,
    ),
    SportKind.cricket => const _Look(
      floorNear: Color(0xFF34A04A),
      floorFar: Color(0xFF1D6E31),
      surround: Color(0xFF123524),
      indoor: false,
    ),
    SportKind.basketball => const _Look(
      floorNear: Color(0xFFC98A47),
      floorFar: Color(0xFF8E5A28),
      surround: Color(0xFF3A2A4E),
      indoor: true,
    ),
    SportKind.volleyball => const _Look(
      floorNear: Color(0xFFD29A55),
      floorFar: Color(0xFF9A6630),
      surround: Color(0xFF1F3552),
      indoor: true,
    ),
    SportKind.tennis ||
    SportKind.pickleball ||
    SportKind.padel ||
    SportKind.squash ||
    SportKind.tableTennis => const _Look(
      floorNear: Color(0xFF2F6FC4),
      floorFar: Color(0xFF1B4585),
      surround: Color(0xFF1B6B4E),
      indoor: false,
    ),
    SportKind.other => const _Look(
      floorNear: Color(0xFF3A63B8),
      floorFar: Color(0xFF21408A),
      surround: Color(0xFF2B2150),
      indoor: true,
    ),
  };

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final look = _look;
    final rect = Offset.zero & size;
    final hy = h * 0.40; // horizon (where the floor meets the back wall)

    // the hall or the night sky
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, hy),
          look.indoor
              ? [
                  const Color(0xFF070D1A),
                  Color.lerp(look.surround, const Color(0xFF16233B), 0.4)!,
                ]
              : [
                  const Color(0xFF050B18),
                  Color.lerp(look.surround, const Color(0xFF1A2A4A), 0.5)!,
                ],
        ),
    );

    // floodlights: soft glows along the top, with a bright core
    for (final x in const [0.16, 0.5, 0.84]) {
      final c = Offset(w * x, h * 0.06);
      canvas.drawCircle(
        c,
        w * 0.34,
        Paint()
          ..shader = ui.Gradient.radial(c, w * 0.34, [
            const Color(0x40BFE4FF),
            const Color(0x00BFE4FF),
          ]),
      );
      canvas.drawCircle(c, w * 0.018, Paint()..color = const Color(0xFFEAF6FF));
    }

    // the floor, in perspective: a trapezoid from the horizon to the bottom edge
    final nearHalf = w * 0.78;
    final farHalf = w * 0.40;
    final cx = w / 2;
    Offset map(double u, double v) {
      final half = ui.lerpDouble(farHalf, nearHalf, v)!;
      return Offset(cx + (u - 0.5) * 2 * half, ui.lerpDouble(hy, h * 1.04, v)!);
    }

    final floor = Path()
      ..moveTo(map(0, 0).dx, map(0, 0).dy)
      ..lineTo(map(1, 0).dx, map(1, 0).dy)
      ..lineTo(map(1, 1).dx, map(1, 1).dy)
      ..lineTo(map(0, 1).dx, map(0, 1).dy)
      ..close();
    canvas.save();
    canvas.clipRect(rect);
    canvas.drawPath(
      floor,
      Paint()
        ..shader = ui.Gradient.linear(Offset(0, hy), Offset(0, h), [
          look.floorFar,
          look.floorNear,
        ]),
    );

    // the court / pitch markings, then the light on the floor
    _markings(canvas, map, w, h);
    canvas.drawPath(
      floor,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(cx, hy + (h - hy) * 0.35),
          w * 0.62,
          [const Color(0x30FFFFFF), const Color(0x00FFFFFF)],
        ),
    );
    canvas.restore();

    // the back wall's base line, and a darkening at the edges so the middle glows
    canvas.drawLine(
      Offset(0, hy),
      Offset(w, hy),
      Paint()
        ..color = const Color(0x33FFFFFF)
        ..strokeWidth = 1,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(cx, h * 0.55),
          w * 0.75,
          [const Color(0x00000000), const Color(0x66000000)],
          const [0.55, 1.0],
        ),
    );
  }

  // ── markings ──────────────────────────────────────────────────────────

  void _markings(
    Canvas canvas,
    Offset Function(double, double) map,
    double w,
    double h,
  ) {
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, w * 0.0065)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xE6FFFFFF);

    void seg(double u1, double v1, double u2, double v2) =>
        canvas.drawLine(map(u1, v1), map(u2, v2), line);
    void box(double u1, double v1, double u2, double v2) {
      final p = Path()
        ..moveTo(map(u1, v1).dx, map(u1, v1).dy)
        ..lineTo(map(u2, v1).dx, map(u2, v1).dy)
        ..lineTo(map(u2, v2).dx, map(u2, v2).dy)
        ..lineTo(map(u1, v2).dx, map(u1, v2).dy)
        ..close();
      canvas.drawPath(p, line);
    }

    // an ellipse on the floor (a circle seen in perspective), from points mapped through the floor
    void circle(
      double u,
      double v,
      double ru,
      double rv, {
      double from = 0,
      double to = math.pi * 2,
    }) {
      final path = Path();
      const steps = 48;
      for (var i = 0; i <= steps; i++) {
        final a = from + (to - from) * i / steps;
        final p = map(u + ru * math.cos(a), v + rv * math.sin(a));
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, line);
    }

    void net(
      double u1,
      double u2,
      double v,
      double height, {
      Color color = const Color(0xFFF2F6FF),
    }) {
      final a = map(u1, v);
      final b = map(u2, v);
      final top = Paint()
        ..color = color
        ..strokeWidth = line.strokeWidth * 1.4
        ..style = PaintingStyle.stroke;
      final mesh = Paint()
        ..color = color.withValues(alpha: 0.38)
        ..strokeWidth = 0.8
        ..style = PaintingStyle.stroke;
      final lift = Offset(0, -h * height);
      canvas.drawRect(
        Rect.fromPoints(a + lift, b),
        Paint()..color = const Color(0x22FFFFFF),
      );
      const cols = 22;
      for (var i = 0; i <= cols; i++) {
        final x = ui.lerpDouble(a.dx, b.dx, i / cols)!;
        canvas.drawLine(Offset(x, a.dy), Offset(x, a.dy + lift.dy), mesh);
      }
      const rows = 4;
      for (var j = 1; j < rows; j++) {
        final y = a.dy + lift.dy * j / rows;
        canvas.drawLine(Offset(a.dx, y), Offset(b.dx, y), mesh);
      }
      canvas.drawLine(a + lift, b + lift, top);
      // posts
      canvas.drawLine(a, a + lift, top);
      canvas.drawLine(b, b + lift, top);
    }

    switch (kind) {
      case SportKind.badminton:
        box(0.10, 0.10, 0.90, 0.98); // doubles outline
        seg(0.17, 0.10, 0.17, 0.98); // singles sidelines
        seg(0.83, 0.10, 0.83, 0.98);
        seg(0.10, 0.31, 0.90, 0.31); // long service lines (doubles)
        seg(0.10, 0.77, 0.90, 0.77);
        seg(0.10, 0.43, 0.90, 0.43); // short service lines
        seg(0.10, 0.65, 0.90, 0.65);
        seg(0.50, 0.10, 0.50, 0.43); // centre lines
        seg(0.50, 0.65, 0.50, 0.98);
        net(0.07, 0.93, 0.54, 0.075);
      case SportKind.football:
        // mown stripes
        const stripes = 8;
        for (var i = 0; i < stripes; i += 2) {
          final v1 = i / stripes, v2 = (i + 1) / stripes;
          final p = Path()
            ..moveTo(map(0, v1).dx, map(0, v1).dy)
            ..lineTo(map(1, v1).dx, map(1, v1).dy)
            ..lineTo(map(1, v2).dx, map(1, v2).dy)
            ..lineTo(map(0, v2).dx, map(0, v2).dy)
            ..close();
          canvas.drawPath(p, Paint()..color = const Color(0x18000000));
        }
        box(0.08, 0.10, 0.92, 0.98);
        seg(0.08, 0.54, 0.92, 0.54);
        circle(0.5, 0.54, 0.13, 0.12);
        box(0.30, 0.10, 0.70, 0.27); // the far penalty area
        box(0.40, 0.10, 0.60, 0.17);
        box(0.30, 0.81, 0.70, 0.98); // the near penalty area
        // the far goal: frame and net
        final gl = map(0.40, 0.10), gr = map(0.60, 0.10);
        final gTop = Offset(0, -h * 0.085);
        canvas.drawRect(
          Rect.fromPoints(gl + gTop, gr),
          Paint()..color = const Color(0x26FFFFFF),
        );
        for (var i = 0; i <= 12; i++) {
          final x = ui.lerpDouble(gl.dx, gr.dx, i / 12)!;
          canvas.drawLine(
            Offset(x, gl.dy),
            Offset(x, gl.dy + gTop.dy),
            Paint()
              ..color = const Color(0x55FFFFFF)
              ..strokeWidth = 0.7,
          );
        }
        final post = Paint()
          ..color = const Color(0xFFF4F8FF)
          ..strokeWidth = line.strokeWidth * 1.5
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(gl, gl + gTop, post);
        canvas.drawLine(gr, gr + gTop, post);
        canvas.drawLine(gl + gTop, gr + gTop, post);
      case SportKind.cricket:
        // the square's pitch strip
        final strip = Path()
          ..moveTo(map(0.42, 0.12).dx, map(0.42, 0.12).dy)
          ..lineTo(map(0.58, 0.12).dx, map(0.58, 0.12).dy)
          ..lineTo(map(0.58, 0.95).dx, map(0.58, 0.95).dy)
          ..lineTo(map(0.42, 0.95).dx, map(0.42, 0.95).dy)
          ..close();
        canvas.drawPath(
          strip,
          Paint()..color = const Color(0xFFC9B27C).withValues(alpha: 0.85),
        );
        seg(0.40, 0.20, 0.60, 0.20); // creases
        seg(0.40, 0.30, 0.60, 0.30);
        seg(0.40, 0.84, 0.60, 0.84);
        seg(0.40, 0.94, 0.60, 0.94);
        circle(0.5, 0.54, 0.40, 0.34, from: 0, to: math.pi * 2); // the boundary
        // stumps at both ends
        for (final v in const [0.20, 0.94]) {
          for (final u in const [0.475, 0.5, 0.525]) {
            final base = map(u, v);
            canvas.drawLine(
              base,
              base + Offset(0, -h * (v > 0.5 ? 0.075 : 0.045)),
              Paint()
                ..color = const Color(0xFFF7F1DD)
                ..strokeWidth = math.max(1.4, w * 0.007)
                ..strokeCap = StrokeCap.round,
            );
          }
        }
      case SportKind.basketball:
        box(0.08, 0.10, 0.92, 0.98);
        seg(0.08, 0.54, 0.92, 0.54);
        circle(0.5, 0.54, 0.11, 0.10);
        box(0.36, 0.10, 0.64, 0.30); // the keys
        box(0.36, 0.78, 0.64, 0.98);
        circle(0.5, 0.30, 0.11, 0.09, from: 0, to: math.pi); // free-throw arcs
        circle(0.5, 0.78, 0.11, 0.09, from: math.pi, to: math.pi * 2);
        // the far hoop: backboard and rim
        final bb = map(0.5, 0.10);
        canvas.drawRect(
          Rect.fromCenter(
            center: bb + Offset(0, -h * 0.10),
            width: w * 0.13,
            height: h * 0.075,
          ),
          Paint()..color = const Color(0x55FFFFFF),
        );
        canvas.drawRect(
          Rect.fromCenter(
            center: bb + Offset(0, -h * 0.10),
            width: w * 0.13,
            height: h * 0.075,
          ),
          Paint()
            ..style = PaintingStyle.stroke
            ..color = const Color(0xFFF4F8FF)
            ..strokeWidth = 1.4,
        );
        canvas.drawOval(
          Rect.fromCenter(
            center: bb + Offset(0, -h * 0.07),
            width: w * 0.05,
            height: h * 0.014,
          ),
          Paint()
            ..style = PaintingStyle.stroke
            ..color = const Color(0xFFFF7A3C)
            ..strokeWidth = math.max(1.6, w * 0.008),
        );
      case SportKind.tennis ||
          SportKind.pickleball ||
          SportKind.padel ||
          SportKind.squash ||
          SportKind.tableTennis:
        box(0.12, 0.10, 0.88, 0.98);
        seg(0.20, 0.10, 0.20, 0.98); // singles sidelines
        seg(0.80, 0.10, 0.80, 0.98);
        seg(0.20, 0.30, 0.80, 0.30); // service lines
        seg(0.20, 0.78, 0.80, 0.78);
        seg(0.50, 0.30, 0.50, 0.78); // centre service line
        net(0.09, 0.91, 0.54, 0.065);
      case SportKind.volleyball:
        box(0.12, 0.10, 0.88, 0.98);
        seg(0.12, 0.40, 0.88, 0.40); // attack lines
        seg(0.12, 0.68, 0.88, 0.68);
        net(0.08, 0.92, 0.54, 0.11);
      case SportKind.other:
        box(0.10, 0.10, 0.90, 0.98);
        seg(0.10, 0.54, 0.90, 0.54);
        circle(0.5, 0.54, 0.14, 0.13);
        box(0.34, 0.10, 0.66, 0.24);
        box(0.34, 0.84, 0.66, 0.98);
    }
  }

  @override
  bool shouldRepaint(VenueScenePainter old) => old.kind != kind;
}

class _Look {
  const _Look({
    required this.floorNear,
    required this.floorFar,
    required this.surround,
    required this.indoor,
  });

  final Color floorNear;
  final Color floorFar;
  final Color surround;
  final bool indoor;
}
