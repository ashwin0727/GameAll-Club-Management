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
import '../../shared/widgets/metric_trend_chart.dart';

class PeakHoursChart extends StatelessWidget {
  const PeakHoursChart({super.key, required this.rows});

  final List<PeakHourRow> rows;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    if (!rows.any((r) => r.bookedMinutes > 0)) {
      return SizedBox(height: 160, child: _emptyChart(context, tokens));
    }
    // Only the hours the facility is open: a closed hour is not "0% demand".
    final open = rows.where((r) => r.openMinutes > 0).toList()..sort((a, b) => a.hour.compareTo(b.hour));
    return MetricTrendChart(
      points: [
        for (final r in open) TrendPoint('', r.demandPct.clamp(0, 100), label: _hourLabel(r.hour)),
      ],
      color: tokens.violet,
      axisFormat: (v) => '${v.round()}%',
      formatValue: (v) => '${v.round()}% of open time booked',
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
            Text('No Booking Data Yet',
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
