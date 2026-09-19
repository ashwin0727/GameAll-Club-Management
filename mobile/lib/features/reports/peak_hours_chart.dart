/// Reports → Court Utilization — the "Peak Hours" area chart.
///
/// Same drawing approach as finance/revenue_trend_chart.dart (no chart
/// package in pubspec.yaml, so a [CustomPainter] draws the line/area over a
/// 0-23h × 0-100% grid). The 24-hour axis is fixed rather than derived from
/// the data, since an operating facility's hours only shrink the visible
/// series, not the axis it's plotted against.
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/analytics.dart';

class PeakHoursChart extends StatelessWidget {
  const PeakHoursChart({super.key, required this.rows});

  final List<PeakHourRow> rows;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final byHour = {for (final r in rows) r.hour: r.demandPct};
    final hasData = rows.any((r) => r.bookedMinutes > 0);

    final axisStyle = TextStyle(fontSize: 10, color: tokens.textSecondary);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 170,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 30,
                height: 160,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('100%', style: axisStyle),
                    Text('75%', style: axisStyle),
                    Text('50%', style: axisStyle),
                    Text('25%', style: axisStyle),
                    Text('0%', style: axisStyle),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: SizedBox(
                  height: 160,
                  child: hasData
                      ? LayoutBuilder(
                          builder: (context, constraints) {
                            final size = Size(constraints.maxWidth, constraints.maxHeight);
                            final plot = [
                              for (var h = 0; h <= 23; h++)
                                Offset(
                                  size.width * (h / 23),
                                  size.height - (size.height * ((byHour[h] ?? 0) / 100)),
                                ),
                            ];
                            return CustomPaint(
                              size: size,
                              painter: _PeakHoursPainter(
                                plot: plot,
                                lineColor: tokens.primary,
                                gridColor: tokens.borderColor,
                              ),
                            );
                          },
                        )
                      : _emptyChart(context, tokens),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Padding(
          padding: const EdgeInsets.only(left: 36),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final h in [0, 4, 8, 12, 16, 20])
                Text(_hourLabel(h), style: AppTypography.caption(context)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _emptyChart(BuildContext context, AppColorTokens tokens) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: tokens.borderColor, width: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.access_time_rounded, size: 22, color: tokens.textSecondary),
            const SizedBox(height: AppSpacing.xs),
            Text('No booking data yet',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: tokens.textPrimary)),
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Text(
                "We'll show your busiest hours here once bookings start coming in.",
                textAlign: TextAlign.center,
                style: AppTypography.caption(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _hourLabel(int h) {
    if (h == 0) return '12 AM';
    if (h == 12) return '12 PM';
    return h < 12 ? '$h AM' : '${h - 12} PM';
  }
}

class _PeakHoursPainter extends CustomPainter {
  _PeakHoursPainter({required this.plot, required this.lineColor, required this.gridColor});

  final List<Offset> plot;
  final Color lineColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = size.height * (i / 4);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (plot.length < 2) return;

    final linePath = Path()..moveTo(plot.first.dx, plot.first.dy);
    for (var i = 1; i < plot.length; i++) {
      final p0 = plot[i - 1];
      final p1 = plot[i];
      final cx = (p0.dx + p1.dx) / 2;
      linePath.cubicTo(cx, p0.dy, cx, p1.dy, p1.dx, p1.dy);
    }

    final areaPath = Path.from(linePath)
      ..lineTo(plot.last.dx, size.height)
      ..lineTo(plot.first.dx, size.height)
      ..close();

    canvas.drawPath(
      areaPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [lineColor.withValues(alpha: 0.32), lineColor.withValues(alpha: 0.02)],
        ).createShader(Offset.zero & size),
    );

    canvas.drawPath(
      linePath,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_PeakHoursPainter oldDelegate) =>
      oldDelegate.plot != plot || oldDelegate.lineColor != lineColor;
}
