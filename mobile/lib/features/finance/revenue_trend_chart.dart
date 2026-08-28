import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/finance.dart';
import 'finance_presentation.dart';

/// Mirrors src/features/finance/components/revenue-trend-chart.tsx.
///
/// The web uses recharts; mobile has no chart package in pubspec.yaml and
/// this phase deliberately does not add one, so the same area chart is drawn
/// with a [CustomPainter] over Flutter primitives.
///
/// The chart's ONLY data source is `get_revenue_trend` — each point is a
/// server-aggregated bucket, never computed from a client-side transaction
/// list (spec §"Revenue Chart"). The one number this widget derives is the
/// plot's vertical scale (the largest gross bucket), which is a drawing
/// dimension, not a figure shown to the owner as a total.
///
/// Axis labels are real [Text] widgets outside the painted area rather than
/// text painted into the canvas, so they scale with the system font size
/// instead of staying pinned at a hard-coded size.
class RevenueTrendChart extends StatelessWidget {
  const RevenueTrendChart({super.key, required this.points});

  final List<RevenueTrendPoint> points;

  static final DateFormat _axisDate = DateFormat('d MMM');

  String _axisLabel(String isoDate) => _axisDate.format(DateTime.parse(isoDate));

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Center(
          child: Text('No revenue data for this period.', style: AppTypography.secondary(context)),
        ),
      );
    }

    var peakMinor = 0;
    for (final point in points) {
      if (point.grossMinor > peakMinor) peakMinor = point.grossMinor;
    }

    return Semantics(
      label: 'Revenue trend chart, ${points.length} points, peak ${financeAmount(peakMinor)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(financeAmount(peakMinor), style: AppTypography.caption(context)),
          const SizedBox(height: AppSpacing.xs),
          SizedBox(
            height: 160,
            width: double.infinity,
            child: CustomPaint(
              painter: _RevenueTrendPainter(points: points, peakMinor: peakMinor),
            ),
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

class _RevenueTrendPainter extends CustomPainter {
  _RevenueTrendPainter({required this.points, required this.peakMinor});

  final List<RevenueTrendPoint> points;
  final int peakMinor;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = size.height * (i / 3);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // A flat all-zero period still draws a baseline rather than dividing by
    // zero or inventing a scale.
    final scaleMax = peakMinor <= 0 ? 1 : peakMinor;

    Offset offsetFor(int index) {
      final dx = points.length == 1 ? size.width / 2 : size.width * (index / (points.length - 1));
      final dy = size.height - (size.height * (points[index].grossMinor / scaleMax));
      return Offset(dx, dy);
    }

    final linePoints = List.generate(points.length, offsetFor);

    if (linePoints.length == 1) {
      canvas.drawCircle(
        linePoints.first,
        4,
        Paint()..color = AppColors.primary,
      );
      return;
    }

    final linePath = Path()..moveTo(linePoints.first.dx, linePoints.first.dy);
    for (final point in linePoints.skip(1)) {
      linePath.lineTo(point.dx, point.dy);
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
  bool shouldRepaint(_RevenueTrendPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.peakMinor != peakMinor;
}