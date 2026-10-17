import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/data/models/operating_hours.dart';
import 'package:gameall_club_mobile/features/onboarding/operating_hours_summary.dart';

void main() {
  test('formatTime12h', () {
    expect(formatTime12h('06:00'), '6:00 AM');
    expect(formatTime12h('23:30:00'), '11:30 PM');
    expect(formatTime12h('00:00'), '12:00 AM');
    expect(formatTime12h('12:00'), '12:00 PM');
  });

  test('identical consecutive days collapse into one line', () {
    final week = OperatingDay.defaultWeek();
    final groups = groupOperatingDays(week);
    expect(groups, hasLength(1));
    expect(groups.first.label, 'Monday – Sunday');
  });

  test('a closed weekend splits from the weekdays', () {
    final week = OperatingDay.defaultWeek().map((d) => d.dayOfWeek == 0 || d.dayOfWeek == 6 ? d.copyWith(isClosed: true, slots: const []) : d).toList();
    final groups = groupOperatingDays(week);
    expect(groups.map((g) => g.label).toList(), ['Monday – Friday', 'Saturday – Sunday']);
    expect(groups.last.description, 'Closed');
  });

  test('24 hours reads as Open 24 hours', () {
    final week = OperatingDay.defaultWeek().map((d) => d.copyWith(isClosed: false, is24Hours: true)).toList();
    expect(groupOperatingDays(week).single.description, 'Open 24 hours');
  });
}
