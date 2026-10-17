import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/features/coaching/program_wizard.dart';

void main() {
  sessionsPerWeekTests();
  test('the wizard has the same five steps as the web', () {
    expect(programSteps, ['Basic Information', 'Program Details', 'Schedule & Batches', 'Pricing & Settings', 'Review & Create']);
  });

  group('programStructurePresetsForSport', () {
    test('uses the sport\'s own vocabulary, matched by substring', () {
      expect(programStructurePresetsForSport('Badminton'), contains('Smash'));
      expect(programStructurePresetsForSport('Box Cricket'), contains('Batting Technique'));
      expect(programStructurePresetsForSport('Table Tennis'), contains('Spin & Serve'));
    });
    test('falls back to a generic list, never empty', () {
      expect(programStructurePresetsForSport(null), contains('Footwork'));
      expect(programStructurePresetsForSport('Curling'), contains('Match Practice'));
    });
  });

  group('weeks and dates', () {
    test('addWeeksIso', () {
      expect(addWeeksIso(DateTime(2026, 10, 16), 12), '2027-01-08');
      expect(addWeeksIso(DateTime(2026, 12, 25), 1), '2027-01-01');
    });
    test('weeksInProgram: a preset, or the custom span rounded, at least one week', () {
      expect(weeksInProgram(durationWeeks: '12', start: null, customEnd: null), 12);
      expect(weeksInProgram(durationWeeks: 'custom', start: DateTime(2026, 10, 1), customEnd: DateTime(2026, 10, 29)), 4);
      expect(weeksInProgram(durationWeeks: 'custom', start: DateTime(2026, 10, 1), customEnd: DateTime(2026, 10, 3)), 1);
      expect(weeksInProgram(durationWeeks: 'custom', start: DateTime(2026, 10, 10), customEnd: DateTime(2026, 10, 1)), 0);
      expect(weeksInProgram(durationWeeks: 'custom', start: null, customEnd: null), 0);
    });
  });

  group('computeProgramFee', () {
    test('a single fee is the fee, less discount, plus tax on what is left', () {
      final f = computeProgramFee(priceInr: 10000, perSession: false, sessionsPerWeek: 3, weeks: 12, discountInr: 1000, taxApplicable: true, taxPercent: 18);
      expect((f.baseInr, f.taxInr, f.totalInr), (10000, 1620, 10620));
    });
    test('a per-session fee is multiplied over every session in the program', () {
      final f = computeProgramFee(priceInr: 500, perSession: true, sessionsPerWeek: 3, weeks: 12);
      expect((f.totalSessions, f.baseInr, f.totalInr), (36, 18000, 18000));
    });
    test('never goes below zero', () {
      final f = computeProgramFee(priceInr: 500, perSession: false, sessionsPerWeek: 1, weeks: 4, discountInr: 900);
      expect(f.totalInr, 0);
    });
  });

  group('findDuplicateBatch', () {
    const b = DraftBatch(name: 'Morning', daysOfWeek: [1, 3], startTime: '06:00', endTime: '07:00', capacity: 10, courtId: 'c1');
    test('same name', () => expect(findDuplicateBatch([b], name: ' morning ', courtId: 'c2', startTime: '08:00', endTime: '09:00', days: [2]), isNotNull));
    test('same court, time and an overlapping day', () => expect(findDuplicateBatch([b], name: 'Other', courtId: 'c1', startTime: '06:00', endTime: '07:00', days: [3, 4]), isNotNull));
    test('a different slot is fine', () => expect(findDuplicateBatch([b], name: 'Other', courtId: 'c1', startTime: '06:00', endTime: '07:00', days: [2]), isNull));
  });

  test('a batch becomes the payload the database expects', () {
    const b = DraftBatch(name: 'A', daysOfWeek: [1], startTime: '16:00', endTime: '17:00', capacity: 12, courtId: 'c1', coachId: 'k1');
    expect(b.toPayload(), {'courtId': 'c1', 'coachId': 'k1', 'name': 'A', 'daysOfWeek': [1], 'startTime': '16:00', 'endTime': '17:00', 'capacity': 12});
  });
}

void sessionsPerWeekTests() {
  test('sessions per week offers every day of the week, 1 to 7', () {
    expect(sessionsPerWeekChoices, [1, 2, 3, 4, 5, 6, 7]);
  });
}
