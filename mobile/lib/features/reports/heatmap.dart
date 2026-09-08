/// Reports & Analytics — demand heatmap (Phase 9.4).
///
/// Mirrors src/features/reports/components/heatmap.tsx. Day-of-week × hour-of-
/// day demand, encoded three ways so it never relies on colour alone
/// (web spec §16/§54): cell background opacity, the number printed in the
/// cell, and a `Semantics` label per cell. Only hours that appear in [cells]
/// are shown as columns.
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/analytics.dart';

const _days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

String _hourShort(int h) {
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12${h < 12 ? 'a' : 'p'}';
}

class Heatmap extends StatelessWidget {
  const Heatmap({super.key, required this.cells});

  final List<HeatmapCell> cells;

  @override
  Widget build(BuildContext context) {
    if (cells.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Center(
          child: Text('No demand data for this period.', style: AppTypography.secondary(context)),
        ),
      );
    }

    final hours = cells.map((c) => c.hour).toSet().toList()..sort();
    final byKey = {for (final c in cells) '${c.dow}-${c.hour}': c};

    Widget cellBox(int dow, int hour) {
      final cell = byKey['$dow-$hour'];
      final pct = cell?.demandPct.round();
      return Semantics(
        label: cell == null
            ? '${_days[dow]} ${hour.toString().padLeft(2, '0')}:00, closed'
            : '${_days[dow]} ${hour.toString().padLeft(2, '0')}:00, $pct% demand',
        child: Container(
          width: 30,
          height: 26,
          margin: const EdgeInsets.all(1),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: pct == null
                ? AppColors.border.withValues(alpha: 0.4)
                : AppColors.primary.withValues(alpha: 0.08 + (pct / 100) * 0.8),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            pct?.toString() ?? '·',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: pct != null && pct >= 55 ? const Color(0xFF07101F) : null,
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(width: 34),
              for (final h in hours)
                SizedBox(
                  width: 32,
                  child: Text(_hourShort(h),
                      textAlign: TextAlign.center, style: AppTypography.caption(context)),
                ),
            ],
          ),
          for (var dow = 0; dow < _days.length; dow++)
            Row(
              children: [
                SizedBox(
                  width: 34,
                  child: Text(_days[dow], style: AppTypography.caption(context)),
                ),
                for (final h in hours) cellBox(dow, h),
              ],
            ),
        ],
      ),
    );
  }
}
