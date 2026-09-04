/// Reports & Analytics — shared presentational widgets (Phase 9.1).
///
/// Mirror src/features/reports/components/report-bar-list.tsx and
/// data-table.tsx. Purely presentational — they render values the server
/// computed and never derive one.
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../shared/widgets/app_card.dart';

/// One headline figure for the selected range, with its change vs the
/// preceding window of equal length. Mirrors the web `<KpiStrip>` item.
class ReportKpi {
  const ReportKpi({
    required this.label,
    required this.value,
    this.pct,
    this.invert = false,
    this.onTap,
  });

  final String label;
  final String value;
  final double? pct;

  /// For expenses / money owed, a rise is bad news — colour follows meaning.
  final bool invert;
  final VoidCallback? onTap;
}

/// A reflowing grid of [ReportKpi] cards — 1 or 2 columns by width, like the
/// Finance dashboard.
class ReportKpiGrid extends StatelessWidget {
  const ReportKpiGrid({super.key, required this.items});

  final List<ReportKpi> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 170).floor().clamp(1, 2);
        final width = (constraints.maxWidth - (AppSpacing.md * (columns - 1))) / columns;
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            for (final kpi in items) SizedBox(width: width, child: _KpiCard(kpi: kpi)),
          ],
        );
      },
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.kpi});

  final ReportKpi kpi;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: kpi.onTap,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: Text(kpi.label, style: AppTypography.caption(context))),
              if (kpi.onTap != null) const Icon(Icons.chevron_right, size: 16, color: AppColors.muted),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            kpi.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.xs),
          _KpiDelta(pct: kpi.pct, invert: kpi.invert),
        ],
      ),
    );
  }
}

class _KpiDelta extends StatelessWidget {
  const _KpiDelta({required this.pct, required this.invert});

  final double? pct;
  final bool invert;

  @override
  Widget build(BuildContext context) {
    if (pct == null) {
      return Text('vs last period', style: AppTypography.caption(context));
    }
    final good = invert ? pct! <= 0 : pct! >= 0;
    final colour = good ? context.tokens.success : context.tokens.destructive;
    final rounded = pct! == pct!.roundToDouble() ? pct!.toStringAsFixed(0) : pct!.toStringAsFixed(1);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(pct! >= 0 ? Icons.trending_up : Icons.trending_down, size: 13, color: colour),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            '${pct! > 0 ? '+' : ''}$rounded% vs last period',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colour, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class ReportBar {
  const ReportBar({required this.label, required this.value, this.color, this.caption});

  final String label;
  final num value;
  final Color? color;

  /// Shown in place of the raw value (e.g. "₹50,000 (50%)").
  final String? caption;
}

/// Labelled horizontal bars — the readable companion to a chart, and the
/// whole widget where a chart would be overkill (web spec §7/§14/§42).
class ReportBarList extends StatelessWidget {
  const ReportBarList({super.key, required this.items, this.max});

  final List<ReportBar> items;
  final num? max;

  @override
  Widget build(BuildContext context) {
    final peak = <num>[
      ?max,
      ...items.map((i) => i.value),
      1,
    ].reduce((a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(item.label, overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: AppSpacing.md),
                    Text(
                      item.caption ?? item.value.toString(),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: (item.value / peak).clamp(0, 1).toDouble(),
                    minHeight: 8,
                    backgroundColor: AppColors.border,
                    valueColor: AlwaysStoppedAnimation(item.color ?? AppColors.primary),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class ReportColumn {
  const ReportColumn({required this.label, this.numeric = false});

  final String label;
  final bool numeric;
}

/// The precise, accessible companion under a report chart (web spec §42/§54).
/// [onTapRow], when given, makes each row tappable (drill-down, §28).
class ReportDataTable extends StatelessWidget {
  const ReportDataTable({
    super.key,
    required this.caption,
    required this.columns,
    required this.rows,
    this.onTapRow,
  });

  final String caption;
  final List<ReportColumn> columns;

  /// Each row is a list of cell strings, one per column.
  final List<List<String>> rows;
  final void Function(int rowIndex)? onTapRow;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: caption,
      container: true,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: AppSpacing.lg,
          horizontalMargin: 0,
          headingRowHeight: 36,
          dataRowMinHeight: 40,
          dataRowMaxHeight: 52,
          columns: [
            for (final c in columns) DataColumn(label: Text(c.label), numeric: c.numeric),
          ],
          rows: [
            for (var i = 0; i < rows.length; i++)
              DataRow(
                onSelectChanged: onTapRow == null ? null : (_) => onTapRow!(i),
                cells: [
                  for (var j = 0; j < columns.length; j++)
                    DataCell(Text(j < rows[i].length ? rows[i][j] : '—')),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
