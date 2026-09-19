import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
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
/// instead of staying pinned at a hard-coded size. Y-axis gridline labels,
/// a rounded peak-value callout and per-point dot markers are theme-aware
/// (dark/light) rather than hard-coded to the static dark-mode palette.
///
/// A facility with revenue on only ONE day so far (its first sale) still
/// gets a real line, not a lone dot sitting invisibly on the top gridline —
/// [_plotPoints] anchors that single real point against an implied ₹0 start
/// so the shape reads as "revenue rose to X", the same way it will once more
/// days of (very possibly different, higher-or-lower) amounts come in.
class RevenueTrendChart extends StatelessWidget {
  const RevenueTrendChart({super.key, required this.points});

  final List<RevenueTrendPoint> points;

  static final DateFormat _axisDate = DateFormat('d MMM');

  String _axisLabel(String isoDate) => _axisDate.format(DateTime.parse(isoDate));

  /// Compact axis label — "0", "10K", "1.2L" — never the full rupee string,
  /// which would crowd the y-axis column.
  static String _compact(int minor) {
    final v = minor / 100;
    if (v <= 0) return '0';
    if (v >= 100000) {
      final l = v / 100000;
      return '${l == l.roundToDouble() ? l.round() : l.toStringAsFixed(1)}L';
    }
    if (v >= 1000) {
      final k = v / 1000;
      return '${k == k.roundToDouble() ? k.round() : k.toStringAsFixed(1)}K';
    }
    return v.round().toString();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    if (points.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Center(
          child: Text('No revenue data for this period.', style: AppTypography.secondary(context)),
        ),
      );
    }

    var peakMinor = 0;
    for (final p in points) {
      if (p.grossMinor > peakMinor) peakMinor = p.grossMinor;
    }
    final scaleMax = peakMinor <= 0 ? 1 : peakMinor;
    final axisStyle = TextStyle(fontSize: 10, color: tokens.textSecondary);
    final singleRealPoint = points.length == 1;

    // Up to 5 evenly-spaced date labels along the x-axis instead of only
    // the first and last bucket. A lone real day is labelled at the right,
    // where its rising line actually lands (see [_plotPoints]).
    final labelCount = points.length >= 5 ? 5 : points.length;
    final labelIndices = <int>{
      for (var i = 0; i < labelCount; i++)
        (i * (points.length - 1) / (labelCount - 1 == 0 ? 1 : labelCount - 1)).round(),
    }.toList()
      ..sort();

    return Semantics(
      label: 'Revenue trend chart, ${points.length} points, peak ${financeAmount(peakMinor)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 170,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 34,
                  height: 160,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_compact(scaleMax), style: axisStyle),
                      Text(_compact((scaleMax * 2 / 3).round()), style: axisStyle),
                      Text(_compact((scaleMax / 3).round()), style: axisStyle),
                      Text('0', style: axisStyle),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: SizedBox(
                    height: 160,
                    child: LayoutBuilder(builder: (context, constraints) {
                      final size = Size(constraints.maxWidth, constraints.maxHeight);
                      final plot = plotPoints(points, scaleMax, size);
                      final peakOffset = plot.last;
                      const bubbleWidth = 68.0;
                      final bubbleLeft = (peakOffset.dx - bubbleWidth / 2)
                          .clamp(0.0, (size.width - bubbleWidth).clamp(0.0, double.infinity));

                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          CustomPaint(
                            size: size,
                            painter: _RevenueTrendPainter(
                              plot: plot,
                              skipFirstDot: singleRealPoint,
                              lineColor: tokens.primary,
                              gridColor: tokens.borderColor,
                              dotColor: tokens.primary,
                            ),
                          ),
                          Positioned(
                            left: bubbleLeft,
                            top: (peakOffset.dy - 30).clamp(-8.0, size.height),
                            child: IgnorePointer(
                              child: Container(
                                width: bubbleWidth,
                                alignment: Alignment.center,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.sm, vertical: 4),
                                decoration: BoxDecoration(
                                  color: tokens.surface1,
                                  borderRadius: BorderRadius.circular(AppRadius.sm),
                                  border: Border.all(color: tokens.borderColor),
                                  boxShadow: [
                                    BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.08),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2)),
                                  ],
                                ),
                                child: Text(financeAmount(points.last.grossMinor),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w800,
                                        color: tokens.textPrimary)),
                              ),
                            ),
                          ),
                        ],
                      );
                    }),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(left: 40),
            child: singleRealPoint
                ? Align(
                    alignment: Alignment.centerRight,
                    child: Text(_axisLabel(points.first.date), style: AppTypography.caption(context)),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (final i in labelIndices)
                        Text(_axisLabel(points[i].date), style: AppTypography.caption(context)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Pixel positions for every real bucket, plus (when there is only one) an
/// implied ₹0 anchor at the left edge so the single day still draws as a
/// rising line rather than a lone, easily-missed dot. The LAST entry is
/// always the most-recent/real point (the one worth calling out with the
/// value bubble).
List<Offset> plotPoints(List<RevenueTrendPoint> points, int scaleMax, Size size) {
  if (points.length == 1) {
    final y = size.height - (size.height * (points.first.grossMinor / scaleMax));
    return [Offset(0, size.height), Offset(size.width, y)];
  }
  return [
    for (var i = 0; i < points.length; i++)
      Offset(
        size.width * (i / (points.length - 1)),
        size.height - (size.height * (points[i].grossMinor / scaleMax)),
      ),
  ];
}

class _RevenueTrendPainter extends CustomPainter {
  _RevenueTrendPainter({
    required this.plot,
    required this.skipFirstDot,
    required this.lineColor,
    required this.gridColor,
    required this.dotColor,
  });

  /// Pre-computed pixel positions (see [plotPoints]) — the painter never
  /// re-derives them, so it stays in sync with the peak-bubble placement
  /// computed alongside it in [RevenueTrendChart.build].
  final List<Offset> plot;
  final bool skipFirstDot;
  final Color lineColor;
  final Color gridColor;
  final Color dotColor;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = size.height * (i / 3);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (plot.length < 2) {
      if (plot.isNotEmpty) canvas.drawCircle(plot.first, 4, Paint()..color = dotColor);
      return;
    }

    // A smoothed cubic line — the same "wavy, not jagged" treatment as the
    // dashboard's other sparklines — rather than straight segments.
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
          colors: [
            lineColor.withValues(alpha: 0.32),
            lineColor.withValues(alpha: 0.02),
          ],
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

    // Small dots on every real bucket (never on a synthetic zero-anchor), a
    // bigger halo'd dot on the most recent/peak point.
    final startDotIndex = skipFirstDot ? 1 : 0;
    for (var i = startDotIndex; i < plot.length - 1; i++) {
      canvas.drawCircle(plot[i], 2, Paint()..color = lineColor.withValues(alpha: 0.55));
    }
    final peak = plot.last;
    canvas.drawCircle(peak, 6, Paint()..color = lineColor.withValues(alpha: 0.22));
    canvas.drawCircle(peak, 3.5, Paint()..color = dotColor);
  }

  @override
  bool shouldRepaint(_RevenueTrendPainter oldDelegate) =>
      oldDelegate.plot != plot || oldDelegate.lineColor != lineColor;
}
