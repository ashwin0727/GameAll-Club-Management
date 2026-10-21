import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';

/// One bucket of a [MetricTrendChart].
class TrendPoint {
  const TrendPoint(this.date, this.value, {this.label});

  /// yyyy-MM-dd
  final String date;
  final num value;

  /// Replaces the formatted date on the axis and in the tooltip (e.g. "6 PM"
  /// for an hour-of-day chart, where [date] is not meaningful).
  final String? label;
}

/// A smooth gradient area chart with a touch-and-drag read-out — the mobile
/// twin of the web `MetricTrendChart`. Colours come from the caller (a metric
/// keeps its colour across the card and its chart) and everything else from
/// the theme tokens, so it follows light/dark mode.
///
/// Axis labels are real [Text] widgets, so they scale with the system font.
class MetricTrendChart extends StatefulWidget {
  const MetricTrendChart({
    super.key,
    required this.points,
    required this.color,
    required this.formatValue,
    this.height = 190,
    this.axisFormat,
    this.emptyMessage = 'Nothing to show for these dates.',
  });

  final List<TrendPoint> points;
  final Color color;

  /// Full value for the read-out ("₹12,400", "18").
  final String Function(num value) formatValue;
  final double height;
  final String emptyMessage;

  /// Y-axis label; defaults to [compact].
  final String Function(num value)? axisFormat;

  /// Axis label: 0, 10K, 1.2L … (money is rendered in rupees by the caller's
  /// scale, so this works on any plain number).
  static String compact(num v) {
    if (v <= 0) return '0';
    if (v >= 10000000) return '${_trim(v / 10000000)}Cr';
    if (v >= 100000) return '${_trim(v / 100000)}L';
    if (v >= 1000) return '${_trim(v / 1000)}K';
    return v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
  }

  static String _trim(double x) => x == x.roundToDouble() ? x.round().toString() : x.toStringAsFixed(1);

  @override
  State<MetricTrendChart> createState() => _MetricTrendChartState();
}

class _MetricTrendChartState extends State<MetricTrendChart> {
  static final DateFormat _axis = DateFormat('d MMM');
  static final DateFormat _full = DateFormat('EEE, d MMM yyyy');

  int? _active;

  @override
  void didUpdateWidget(covariant MetricTrendChart old) {
    super.didUpdateWidget(old);
    if (old.points != widget.points) _active = null;
  }

  void _select(Offset local, double width) {
    final n = widget.points.length;
    if (n == 0) return;
    final i = n == 1 ? 0 : ((local.dx / width) * (n - 1)).round().clamp(0, n - 1);
    if (i != _active) setState(() => _active = i);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final points = widget.points;
    if (points.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Center(child: Text(widget.emptyMessage, style: AppTypography.secondary(context))),
      );
    }

    var peak = 0.0;
    for (final p in points) {
      if (p.value > peak) peak = p.value.toDouble();
    }
    // Round the scale up to a tidy ceiling so the gridlines read cleanly.
    final scaleMax = peak <= 0 ? 1.0 : _niceCeil(peak);
    final axisStyle = TextStyle(fontSize: 10, color: tokens.textSecondary);
    final labelCount = points.length >= 5 ? 5 : points.length;
    final labelIdx = <int>{
      for (var i = 0; i < labelCount; i++)
        labelCount == 1 ? 0 : (i * (points.length - 1) / (labelCount - 1)).round(),
    }.toList()
      ..sort();

    return Semantics(
      label: 'Trend chart, ${points.length} points, peak ${widget.formatValue(peak)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: widget.height,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 38,
                  height: widget.height,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (final f in const [1.0, 2 / 3, 1 / 3, 0.0])
                        Text((widget.axisFormat ?? MetricTrendChart.compact)(scaleMax * f), style: axisStyle),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: LayoutBuilder(builder: (context, c) {
                    final size = Size(c.maxWidth, widget.height);
                    final plot = _plot(points, scaleMax, size);
                    final a = _active;
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (d) => _select(d.localPosition, size.width),
                      onHorizontalDragStart: (d) => _select(d.localPosition, size.width),
                      onHorizontalDragUpdate: (d) => _select(d.localPosition, size.width),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          CustomPaint(
                            size: size,
                            painter: _ChartPainter(
                              plot: plot,
                              color: widget.color,
                              grid: tokens.borderColor,
                              active: a,
                              surface: tokens.surface1,
                            ),
                          ),
                          if (a != null) _tooltip(tokens, plot[a], size, points[a]),
                        ],
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 44),
            child: points.length == 1
                ? Align(
                    alignment: Alignment.centerRight,
                    child: Text(_axisLabel(points.first), style: AppTypography.caption(context)),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (final i in labelIdx)
                        Text(_axisLabel(points[i]), style: AppTypography.caption(context)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  String _axisLabel(TrendPoint p) => p.label ?? _axis.format(DateTime.parse(p.date));

  Widget _tooltip(AppColorTokens tokens, Offset at, Size size, TrendPoint p) {
    const w = 132.0;
    final left = (at.dx - w / 2).clamp(0.0, (size.width - w).clamp(0.0, double.infinity));
    final top = (at.dy - 54).clamp(-6.0, size.height - 44);
    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: Container(
          width: w,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 6),
          decoration: BoxDecoration(
            color: tokens.surface1,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: widget.color.withValues(alpha: 0.5)),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(p.label ?? _full.format(DateTime.parse(p.date)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 9.5, color: tokens.textSecondary)),
              Text(widget.formatValue(p.value),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: widget.color)),
            ],
          ),
        ),
      ),
    );
  }

  static double _niceCeil(double v) {
    if (v <= 0) return 1;
    var mag = 1.0;
    while (mag * 10 <= v) {
      mag *= 10;
    }
    for (final step in const [1.0, 1.5, 2.0, 3.0, 5.0, 7.5, 10.0]) {
      if (step * mag >= v) return step * mag;
    }
    return 10 * mag;
  }

  static List<Offset> _plot(List<TrendPoint> pts, double scaleMax, Size size) {
    const topPad = 6.0;
    final h = size.height - topPad;
    if (pts.length == 1) {
      return [Offset(size.width / 2, topPad + h - h * (pts.first.value / scaleMax))];
    }
    return [
      for (var i = 0; i < pts.length; i++)
        Offset(size.width * (i / (pts.length - 1)), topPad + h - h * (pts[i].value / scaleMax)),
    ];
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.plot,
    required this.color,
    required this.grid,
    required this.active,
    required this.surface,
  });

  final List<Offset> plot;
  final Color color;
  final Color grid;
  final int? active;
  final Color surface;

  @override
  void paint(Canvas canvas, Size size) {
    const topPad = 6.0;
    final h = size.height - topPad;
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = topPad + h * (i / 3);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (plot.length == 1) {
      canvas.drawCircle(plot.first, 7, Paint()..color = color.withValues(alpha: 0.2));
      canvas.drawCircle(plot.first, 4, Paint()..color = color);
      return;
    }

    final line = Path()..moveTo(plot.first.dx, plot.first.dy);
    for (var i = 1; i < plot.length; i++) {
      final a = plot[i - 1], b = plot[i];
      final cx = (a.dx + b.dx) / 2;
      line.cubicTo(cx, a.dy, cx, b.dy, b.dx, b.dy);
    }
    final area = Path.from(line)
      ..lineTo(plot.last.dx, size.height)
      ..lineTo(plot.first.dx, size.height)
      ..close();

    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.30), color.withValues(alpha: 0.0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // A dot on every bucket only when they are few enough to stay readable.
    if (plot.length <= 14) {
      for (final p in plot) {
        canvas.drawCircle(p, 2.5, Paint()..color = color.withValues(alpha: 0.7));
      }
    }

    final a = active;
    if (a != null && a < plot.length) {
      final p = plot[a];
      canvas.drawLine(
        Offset(p.dx, 0),
        Offset(p.dx, size.height),
        Paint()
          ..color = color.withValues(alpha: 0.35)
          ..strokeWidth = 1,
      );
      canvas.drawCircle(p, 8, Paint()..color = color.withValues(alpha: 0.22));
      canvas.drawCircle(p, 4.5, Paint()..color = surface);
      canvas.drawCircle(
        p,
        4.5,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4,
      );
    }
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.plot != plot || old.color != color || old.active != active || old.grid != grid;
}
