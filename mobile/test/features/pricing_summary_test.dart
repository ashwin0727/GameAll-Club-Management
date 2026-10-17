import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/features/onboarding/pricing_summary.dart';

SummaryPeriod p(String day, num amount, {bool full = true, String? start, String? end}) =>
    SummaryPeriod(dayType: day, coversFullDay: full, startTime: start, endTime: end, amountInr: amount);

List<SummaryPeriod> same() => [p('WEEKDAYS', 300), p('WEEKENDS', 350)];

void main() {
  test('periodLabel', () {
    expect(periodLabel(p('ALL_DAYS', 100)), 'All days · Full day');
    expect(periodLabel(p('WEEKENDS', 100, full: false, start: '06:00', end: '23:00')), 'Weekends · 6:00 AM – 11:00 PM');
  });

  group('groupCustomized', () {
    test('courts that charge the same become one group', () {
      final groups = groupCustomized([CustomizedArea('Court 1', same()), CustomizedArea('Court 2', same()), CustomizedArea('Court 3', same())]);
      expect(groups, hasLength(1));
      expect(groups.single.areaNames, ['Court 1', 'Court 2', 'Court 3']);
    });
    test('different prices stay apart, in first-appearance order', () {
      final groups = groupCustomized([
        CustomizedArea('Court 1', [p('ALL_DAYS', 300)]),
        CustomizedArea('Court 2', [p('ALL_DAYS', 400)]),
        CustomizedArea('Court 3', [p('ALL_DAYS', 300)]),
      ]);
      expect(groups.map((g) => g.areaNames).toList(), [['Court 1', 'Court 3'], ['Court 2']]);
    });
  });

  group('sportSummaryBlocks', () {
    test('every court customized and identical: one "All 3 Courts" block, no unused default', () {
      final blocks = sportSummaryBlocks(
        defaults: [p('ALL_DAYS', 300)],
        customized: [CustomizedArea('Court 1', same()), CustomizedArea('Court 2', same()), CustomizedArea('Court 3', same())],
        areaCount: 3,
        areaLabel: 'Court',
      );
      expect(blocks, hasLength(1));
      expect(blocks.single.title, 'All 3 Courts');
      expect(blocks.single.periods.map((x) => x.amountInr).toList(), [300, 350]);
    });
    test('some customized: the default stays for the rest, matching courts are grouped', () {
      final blocks = sportSummaryBlocks(
        defaults: [p('ALL_DAYS', 200)],
        customized: [CustomizedArea('Court 1', same()), CustomizedArea('Court 2', same())],
        areaCount: 3,
        areaLabel: 'Court',
      );
      expect(blocks.first.title, isNull);
      expect(blocks.first.periods.single.amountInr, 200);
      expect(blocks.last.title, 'Court 1, Court 2 · custom');
    });
    test('a single fully-customized turf is shown by name', () {
      final blocks = sportSummaryBlocks(defaults: const [], customized: [CustomizedArea('Turf 1', [p('ALL_DAYS', 700)])], areaCount: 1, areaLabel: 'Turf');
      expect(blocks.single.title, 'Turf 1 · custom');
    });
    test('nothing customized: just the default', () {
      final blocks = sportSummaryBlocks(defaults: [p('ALL_DAYS', 300)], customized: const [], areaCount: 2, areaLabel: 'Court');
      expect(blocks.single.title, isNull);
    });
  });
}
