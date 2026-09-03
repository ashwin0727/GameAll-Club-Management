/// Finance rework — Phase 13: the period-over-period comparison window.
///
/// Mirrors `previousRange` / `changePct` in
/// src/features/finance/components/finance-dashboard.tsx. Nothing here is a
/// monetary figure — [changePct] compares two totals the server already
/// computed, and [previousFinanceRange] only names a date window; the
/// comparison summary itself is fetched, never derived.
library;

import '../../data/models/finance.dart';

/// The window immediately before [range], of the same length — so the
/// dashboard's deltas compare like with like.
///
/// A rolling preset maps to the one before it. A custom range is shifted back
/// by its own span. A preset with no natural predecessor (YESTERDAY,
/// LAST_WEEK, LAST_MONTH) or a half-picked custom range is returned unchanged,
/// matching the web — the delta then simply reads "vs last period".
FinanceDateRange previousFinanceRange(FinanceDateRange range) {
  switch (range.preset) {
    case FinanceDateRangePreset.today:
      return const FinanceDateRange(preset: FinanceDateRangePreset.yesterday);
    case FinanceDateRangePreset.thisWeek:
      return const FinanceDateRange(preset: FinanceDateRangePreset.lastWeek);
    case FinanceDateRangePreset.thisMonth:
      return const FinanceDateRange(preset: FinanceDateRangePreset.lastMonth);
    case FinanceDateRangePreset.custom:
      final start = range.startDate;
      final end = range.endDate;
      if (start == null || end == null) return range;
      final startDate = DateTime.parse(start);
      final endDate = DateTime.parse(end);
      final days = endDate.difference(startDate).inDays + 1;
      final prevEnd = startDate.subtract(const Duration(days: 1));
      final prevStart = prevEnd.subtract(Duration(days: days - 1));
      return FinanceDateRange(
        preset: FinanceDateRangePreset.custom,
        startDate: _iso(prevStart),
        endDate: _iso(prevEnd),
      );
    case FinanceDateRangePreset.yesterday:
    case FinanceDateRangePreset.lastWeek:
    case FinanceDateRangePreset.lastMonth:
      return range;
  }
}

/// Percentage change of [current] against [previous], rounded to one decimal.
/// Null when [previous] is zero — there is nothing to compare against, and a
/// "+100%" from a zero base would overstate it.
double? changePct({required num current, required num previous}) {
  if (previous == 0) return null;
  return ((current - previous) / previous.abs() * 1000).round() / 10;
}

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
