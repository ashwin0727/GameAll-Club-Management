import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/data/models/finance.dart';
import 'package:gameall_club_mobile/features/finance/finance_period.dart';

/// Finance rework — Phase 13: the period-over-period comparison window.
///
/// Mirrors `previousRange` in src/features/finance/components/finance-dashboard.tsx:
/// the window immediately before the selected one, of the same length, so the
/// dashboard's deltas compare like with like. The comparison summary is then
/// FETCHED for this range — never derived — so it is the server's total either
/// way.
void main() {
  group('previousFinanceRange', () {
    test('maps each rolling preset to the one before it', () {
      expect(
        previousFinanceRange(const FinanceDateRange(preset: FinanceDateRangePreset.today)).preset,
        FinanceDateRangePreset.yesterday,
      );
      expect(
        previousFinanceRange(const FinanceDateRange(preset: FinanceDateRangePreset.thisWeek)).preset,
        FinanceDateRangePreset.lastWeek,
      );
      expect(
        previousFinanceRange(const FinanceDateRange(preset: FinanceDateRangePreset.thisMonth)).preset,
        FinanceDateRangePreset.lastMonth,
      );
    });

    test('shifts a custom range back by its own length', () {
      final prev = previousFinanceRange(const FinanceDateRange(
        preset: FinanceDateRangePreset.custom,
        startDate: '2026-08-10',
        endDate: '2026-08-16', // 7 days inclusive
      ));

      expect(prev.preset, FinanceDateRangePreset.custom);
      expect(prev.endDate, '2026-08-09'); // the day before the original start
      expect(prev.startDate, '2026-08-03'); // 7 days ending 2026-08-09
    });

    test('leaves a preset with no natural predecessor unchanged', () {
      // The web returns the same range for YESTERDAY / LAST_WEEK / LAST_MONTH.
      const yesterday = FinanceDateRange(preset: FinanceDateRangePreset.yesterday);
      expect(previousFinanceRange(yesterday).preset, FinanceDateRangePreset.yesterday);
    });

    test('leaves a half-picked custom range unchanged rather than inventing dates', () {
      const halfPicked = FinanceDateRange(
        preset: FinanceDateRangePreset.custom,
        startDate: '2026-08-10',
      );
      expect(previousFinanceRange(halfPicked), halfPicked);
    });
  });

  group('changePct', () {
    test('is a rounded percentage against the previous figure', () {
      expect(changePct(current: 120, previous: 100), 20.0);
      expect(changePct(current: 90, previous: 100), -10.0);
    });

    test('is null when there is nothing to compare against', () {
      expect(changePct(current: 100, previous: 0), isNull);
    });
  });
}
