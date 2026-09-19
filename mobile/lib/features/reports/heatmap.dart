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
    final tokens = context.tokens;
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
          width: 26,
          height: 22,
          margin: const EdgeInsets.all(1.5),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: pct == null
                ? tokens.surface2
                : Color.alphaBlend(
                    tokens.primary.withValues(alpha: 0.06 + (pct / 100) * 0.82), tokens.surface1),
            borderRadius: BorderRadius.circular(5),
          ),
          child: pct == null || pct == 0
              ? null
              : Text(
                  pct.toString(),
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: pct >= 55 ? tokens.onAccent(tokens.primary) : tokens.textSecondary,
                  ),
                ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('Lower demand', style: AppTypography.caption(context)),
            const SizedBox(width: AppSpacing.sm),
            for (var i = 0; i <= 4; i++)
              Container(
                width: 14,
                height: 14,
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                decoration: BoxDecoration(
                  color: Color.alphaBlend(
                      tokens.primary.withValues(alpha: 0.1 + (i / 4) * 0.8), tokens.surface1),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            const SizedBox(width: AppSpacing.sm),
            Text('Higher demand', style: AppTypography.caption(context)),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const SizedBox(width: 32),
                  for (final h in hours)
                    SizedBox(
                      width: 29,
                      child: Text(_hourShort(h),
                          textAlign: TextAlign.center, style: AppTypography.caption(context)),
                    ),
                ],
              ),
              for (var dow = 0; dow < _days.length; dow++)
                Row(
                  children: [
                    SizedBox(
                      width: 32,
                      child: Text(_days[dow], style: AppTypography.caption(context)),
                    ),
                    for (final h in hours) cellBox(dow, h),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}
