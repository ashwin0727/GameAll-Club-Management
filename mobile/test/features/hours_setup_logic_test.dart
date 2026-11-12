import 'package:flutter_test/flutter_test.dart';

import 'package:gameall_club_mobile/data/models/operating_hours.dart';
import 'package:gameall_club_mobile/features/onboarding/hours_setup_logic.dart';

DayPlan _plan({int day = 1, bool open = true, String from = '06:00', String to = '23:00', bool h24 = false}) => DayPlan(dayOfWeek: day, isOpen: open, open: from, close: to, is24Hours: h24);

void main() {
  group('a new venue\'s plan', () {
    test('is open Monday to Saturday 6 AM - 11 PM and closed on Sunday', () {
      final plans = defaultPlans();
      expect([for (final p in plans) if (p.isOpen) p.dayOfWeek], [1, 2, 3, 4, 5, 6]);
      expect(plans.firstWhere((p) => p.dayOfWeek == 0).isOpen, isFalse);
      expect(detectMode(plans), HoursMode.standard);
    });
  });

  group('plans <-> schedule', () {
    test('one span per open day, and closed days carry no slots', () {
      final days = scheduleFromPlans(defaultPlans(), null);
      final mon = days.firstWhere((d) => d.dayOfWeek == 1);
      expect([for (final s in mon.slots) (s.startTime, s.endTime, s.crossesMidnight)], [('06:00', '23:00', false)]);
      expect(days.firstWhere((d) => d.dayOfWeek == 0).isClosed, isTrue);
      expect(days.firstWhere((d) => d.dayOfWeek == 0).slots, isEmpty);
    });

    test('a close at midnight or after crosses midnight', () {
      final days = scheduleFromPlans([_plan(from: '07:00', to: '00:00')], null);
      final slot = days.firstWhere((d) => d.dayOfWeek == 1).slots.single;
      expect((slot.startTime, slot.endTime, slot.crossesMidnight), ('07:00', '00:00', true));
    });

    test('a break splits the day into two slots, and reading it back folds it into one span again', () {
      const brk = BreakTime('13:00', '14:00');
      final days = scheduleFromPlans(defaultPlans(), brk);
      final mon = days.firstWhere((d) => d.dayOfWeek == 1);
      expect([for (final s in mon.slots) (s.startTime, s.endTime)], [('06:00', '13:00'), ('14:00', '23:00')]);

      final back = plansFromSchedule(days);
      final m = back.firstWhere((p) => p.dayOfWeek == 1);
      expect((m.isOpen, m.open, m.close), (true, '06:00', '23:00'));
      expect(back.firstWhere((p) => p.dayOfWeek == 0).isOpen, isFalse);
    });

    test('a break outside a day\'s hours leaves that day whole', () {
      final days = scheduleFromPlans([_plan(to: '12:00')], const BreakTime('13:00', '14:00'));
      expect(days.firstWhere((d) => d.dayOfWeek == 1).slots, hasLength(1));
    });

    test('24-hour days stay 24-hour, and an older day with no slots reads back as closed', () {
      final days = scheduleFromPlans([_plan(h24: true)], null);
      expect(days.firstWhere((d) => d.dayOfWeek == 1).is24Hours, isTrue);
      expect(plansFromSchedule(days).firstWhere((p) => p.dayOfWeek == 1).is24Hours, isTrue);
      final old = plansFromSchedule(const [OperatingDay(dayOfWeek: 2, isClosed: false, is24Hours: false, slots: [])]);
      expect(old.firstWhere((p) => p.dayOfWeek == 2).isOpen, isFalse);
    });
  });

  group('standard or custom', () {
    test('standard when every open day shares the same hours, custom otherwise', () {
      expect(detectMode(applyStandard([1, 2, 3], '06:00', '22:00')), HoursMode.standard);
      final mixed = applyStandard([1, 2, 3], '06:00', '22:00')..firstWhere((p) => p.dayOfWeek == 2).close = '21:00';
      expect(detectMode(mixed), HoursMode.custom);
    });

    test('applyStandard opens only the chosen days', () {
      final plans = applyStandard([1, 6], '07:00', '20:00');
      expect([for (final p in plans) if (p.isOpen) p.dayOfWeek]..sort(), [1, 6]);
    });
  });

  group('hours', () {
    test('counts a day, overnight, with a break and as 24 hours', () {
      expect(dailyMinutes(_plan(), null), 17 * 60);
      expect(dailyMinutes(_plan(from: '07:00', to: '00:00'), null), 17 * 60);
      expect(dailyMinutes(_plan(), const BreakTime('13:00', '14:00')), 16 * 60);
      expect(dailyMinutes(_plan(h24: true), null), 1440);
      expect(dailyMinutes(_plan(open: false), null), 0);
    });

    test('adds up the whole week', () {
      final week = [_plan(day: 1), _plan(day: 2), _plan(day: 3, to: '22:00'), _plan(day: 4), _plan(day: 5), _plan(day: 6, from: '07:00', to: '00:00'), _plan(day: 0, open: false)];
      expect(weeklyMinutes(week, null), (17 + 17 + 16 + 17 + 17 + 17) * 60);
    });

    test('formats hours and describes a plan', () {
      expect(formatHours(17 * 60), '17 Hours');
      expect(formatHours(60), '1 Hour');
      expect(formatHours(1050), '17.5 Hours');
      expect(describePlan(_plan()), '6:00 AM – 11:00 PM');
      expect(describePlan(_plan(from: '07:00', to: '00:00')), '7:00 AM – 12:00 AM (next day)');
      expect(describePlan(_plan(open: false)), 'Closed');
      expect(describePlan(_plan(h24: true)), 'Open 24 hours');
    });

    test('the time list is every half hour, midnight first', () {
      expect(timeOptions, hasLength(48));
      expect(timeOptions.first, (value: '00:00', label: '12:00 AM'));
      expect(timeOptions.last, (value: '23:30', label: '11:30 PM'));
    });
  });

  group('validation', () {
    test('needs at least one open day, and opening and closing cannot match', () {
      expect(validatePlans(applyStandard([], '06:00', '23:00'), null).general, 'Select at least one operating day.');
      expect(validatePlans([_plan(to: '06:00')], null).byDay[1], 'Opening and closing time cannot be the same.');
      expect(validatePlans(defaultPlans(), null).any, isFalse);
    });

    test('the break must be a real range inside every open day\'s hours', () {
      final plans = defaultPlans();
      expect(validatePlans(plans, const BreakTime('13:00', '13:00')).breakTime, 'The break’s start and end time cannot be the same.');
      expect(validatePlans(plans, const BreakTime('05:00', '07:00')).breakTime, 'The break must fall inside the working hours of every open day.');
      expect(validatePlans(plans, const BreakTime('13:00', '14:00')).breakTime, isNull);
    });

    test('breakFitsDay is strict about the edges and handles an overnight day', () {
      expect(breakFitsDay(_plan(), const BreakTime('06:00', '07:00')), isFalse);
      expect(breakFitsDay(_plan(), const BreakTime('22:00', '23:00')), isFalse);
      expect(breakFitsDay(_plan(), const BreakTime('12:00', '12:30')), isTrue);
      expect(breakFitsDay(_plan(from: '19:00', to: '02:00'), const BreakTime('23:00', '23:30')), isTrue);
    });
  });

  group('closures', () {
    const today = '2026-09-10';
    const ok = ClosureEntry(date: '2026-12-25', name: 'Christmas');

    test('accepts a future date with a name, and today', () {
      expect(closureProblem(ok, const [], today), isNull);
      expect(closureProblem(const ClosureEntry(date: today, name: 'Maintenance'), const [], today), isNull);
    });

    test('needs a date, not in the past, and a name of 2-60 characters', () {
      expect(closureProblem(const ClosureEntry(date: '', name: 'x'), const [], today), 'Select a date.');
      expect(closureProblem(const ClosureEntry(date: '2026-09-01', name: 'Event'), const [], today), 'Choose today or a future date.');
      expect(closureProblem(const ClosureEntry(date: '2026-12-25', name: ' '), const [], today), 'Enter a name of at least 2 characters.');
      expect(closureProblem(ClosureEntry(date: '2026-12-25', name: 'x' * 61), const [], today), 'Keep the name under 60 characters.');
    });

    test('a date can be closed once, and editing may keep its own past date', () {
      expect(closureProblem(ok, const [ClosureEntry(date: '2026-12-25', name: 'Other')], today), 'This date is already marked as closed.');
      const existing = ClosureEntry(date: '2026-08-15', name: 'Independence Day');
      expect(closureProblem(const ClosureEntry(date: '2026-08-15', name: 'Independence Day!'), const [existing], today, editing: existing), isNull);
    });

    test('sorts earliest first and formats the date', () {
      expect([for (final c in sortClosures(const [ClosureEntry(date: '2027-01-01', name: 'b'), ClosureEntry(date: '2026-08-15', name: 'a')])) c.date], ['2026-08-15', '2027-01-01']);
      expect(formatClosureDate('2026-08-15'), '15 Aug 2026 (Sat)');
      expect(formatClosureDate('2027-01-01'), '01 Jan 2027 (Fri)');
      expect(isoDate(DateTime(2026, 3, 5)), '2026-03-05');
    });
  });
}
