/// Reports & Analytics — a count-over-time area chart (Phase 9.3).
///
/// The mobile counterpart of the web's booking-trend chart. `mobile/` has no
/// chart package, so it's a [CustomPainter] over Flutter primitives, exactly
/// like revenue_trend_chart.dart.
///
/// The chart's ONLY data source is the server-aggregated trend RPC — each
/// point is a bucket the database computed, never counted from a client-side
/// list. The one number derived here is the vertical scale (the largest
/// bucket), a drawing dimension.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';

class CountTrendPoint {
  const CountTrendPoint({required this.date, required this.value});
  final String date;
  final int value;
}

class CountTrendChart extends StatelessWidget {
  const CountTrendChart({super.key, required this.points, this.emptyMessage = 'No data for this period.'});

  final List<CountTrendPoint> points;
  final String emptyMessage;

  static final DateFormat _axisDate = DateFormat('d MMM');

  String _axisLabel(String isoDate) => _axisDate.format(DateTime.parse(isoDate));

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Center(child: Text(emptyMessage, style: AppTypography.secondary(context))),
      );
    }

    var peak = 0;
    for (final p in points) {
      if (p.value > peak) peak = p.value;
    }

    return Semantics(
      label: 'Trend chart, ${points.length} points, peak $peak',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$peak', style: AppTypography.caption(context)),
          const SizedBox(height: AppSpacing.xs),
          SizedBox(
            height: 160,
            width: double.infinity,
            child: CustomPaint(painter: _CountTrendPainter(points: points, peak: peak)),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Text(_axisLabel(points.first.date), style: AppTypography.caption(context)),
              const Spacer(),
              if (points.length > 1)
                Text(_axisLabel(points.last.date), style: AppTypography.caption(context)),
            ],
          ),
        ],
      ),
    );
  }
}

class _CountTrendPainter extends CustomPainter {
  _CountTrendPainter({required this.points, required this.peak});

  final List<CountTrendPoint> points;
  final int peak;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = size.height * (i / 3);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final scaleMax = peak <= 0 ? 1 : peak;

    Offset offsetFor(int index) {
      final dx = points.length == 1 ? size.width / 2 : size.width * (index / (points.length - 1));
      final dy = size.height - (size.height * (points[index].value / scaleMax));
      return Offset(dx, dy);
    }

    final linePoints = List.generate(points.length, offsetFor);

    if (linePoints.length == 1) {
      canvas.drawCircle(linePoints.first, 4, Paint()..color = AppColors.primary);
      return;
    }

    final linePath = Path()..moveTo(linePoints.first.dx, linePoints.first.dy);
    for (final p in linePoints.skip(1)) {
      linePath.lineTo(p.dx, p.dy);
    }

    final areaPath = Path.from(linePath)
      ..lineTo(linePoints.last.dx, size.height)
      ..lineTo(linePoints.first.dx, size.height)
      ..close();

    canvas.drawPath(
      areaPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.primary.withValues(alpha: 0.35),
            AppColors.primary.withValues(alpha: 0.02),
          ],
        ).createShader(Offset.zero & size),
    );

    canvas.drawPath(
      linePath,
      Paint()
        ..color = AppColors.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_CountTrendPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.peak != peak;
}
