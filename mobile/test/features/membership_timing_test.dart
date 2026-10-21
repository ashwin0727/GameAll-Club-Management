import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/data/models/analytics.dart';
import 'package:gameall_club_mobile/features/reports/membership_timing.dart';
import 'package:gameall_club_mobile/shared/utils/csv_export.dart';

MembershipBatchRow row({
  String? batchId = 'b-1',
  String sport = 'Badminton',
  String? court = 'Court 1',
  String start = '05:00:00',
  String end = '06:00:00',
  int members = 3,
}) =>
    MembershipBatchRow(
      facilitySportId: 'fs-1',
      sportName: sport,
      courtId: 'c-1',
      courtName: court,
      batchId: batchId,
      batchName: null,
      daysOfWeek: const [1, 2, 3, 4, 5, 6],
      startTime: start,
      endTime: end,
      members: members,
      activeMembers: 2,
      courtMembers: 4,
      sportMembers: 6,
    );

void main() {
  test('formats clock times, ranges and weekdays like the web', () {
    expect(formatClock('05:00:00'), '5:00 AM');
    expect(formatClock('12:30:00'), '12:30 PM');
    expect(formatClock('00:15:00'), '12:15 AM');
    expect(formatTiming('05:00:00', '06:00:00'), '5:00 AM – 6:00 AM');
    expect(formatTiming(null, null), '');
    expect(formatDays([1, 2, 3, 4, 5, 6]), 'Mon–Sat');
    expect(formatDays([0, 6]), 'Sat, Sun');
    expect(formatDays([1, 3, 5]), 'Mon, Wed, Fri');
    expect(formatDays([0, 1, 2, 3, 4, 5, 6]), 'Every day');
  });

  test('groupByCourt folds rows into sport → court → timings and skips the unassigned row', () {
    final groups = groupByCourt([
      row(),
      row(start: '18:00:00', end: '19:00:00'),
      row(court: 'Court 2'),
      row(sport: 'Cricket', court: 'Turf'),
      row(batchId: null, sport: 'Not assigned', court: null),
    ]);
    expect(groups.map((g) => g.sportName), ['Badminton', 'Cricket']);
    expect(groups[0].courts.map((c) => c.courtName), ['Court 1', 'Court 2']);
    expect(groups[0].courts[0].timings, hasLength(2));
  });

  test('buildCsv quotes cells with commas, quotes and newlines', () {
    expect(
      buildCsv([
        ['a', 'b,c', 'say "hi"'],
        [1, null],
      ]),
      'a,"b,c","say ""hi"""\r\n1,',
    );
  });
}
