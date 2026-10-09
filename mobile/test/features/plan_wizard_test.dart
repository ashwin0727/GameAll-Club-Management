import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/features/memberships/plan_wizard.dart';

/// The Create Plan wizard's rules — the same ones the web's create-plan-wizard.ts applies.
void main() {
  PlanWizardDraft valid() => PlanWizardDraft()
    ..name = 'Monthly Membership'
    ..priceInr = 2500
    ..courtIds = ['c1']
    ..timeWindows = [
      PlanTimeWindow(id: 'w1', courtId: 'c1', daysOfWeek: [1, 2, 3]),
    ];

  group('step 1 — Plan Details', () {
    test('a name is required', () {
      expect(planFieldErrors(0, PlanWizardDraft())['name'], 'Plan name is required.');
      expect(planFieldErrors(0, PlanWizardDraft()..name = '   ')['name'], isNotNull);
    });
    test('a name makes it valid', () => expect(validatePlanStep(0, PlanWizardDraft()..name = 'Gold'), isNull));
    test('the description is capped at 200 characters', () {
      final d = PlanWizardDraft()
        ..name = 'Gold'
        ..description = 'x' * 201;
      expect(planFieldErrors(0, d)['description'], isNotNull);
      d.description = 'x' * 200;
      expect(planFieldErrors(0, d)['description'], isNull);
    });
    test('the category defaults to the first of the five the web offers', () {
      expect(planCategories, ['Regular Membership', 'Premium Membership', 'Student Membership', 'Corporate Membership', 'Other']);
      expect(PlanWizardDraft().category, 'Regular Membership');
    });
    test('the badge defaults on, reading "Popular"', () {
      final d = PlanWizardDraft();
      expect((d.showBadge, d.badgeText), (true, 'Popular'));
    });
  });

  group('step 2 — Plan Configuration', () {
    test('the price must be above zero', () {
      expect(planFieldErrors(1, PlanWizardDraft())['priceInr'], 'Price must be greater than 0.');
      expect(planFieldErrors(1, PlanWizardDraft()..priceInr = 100), isEmpty);
    });
    test('a blank or zero custom duration is rejected', () {
      final d = PlanWizardDraft()
        ..priceInr = 100
        ..durationDays = 0;
      expect(planFieldErrors(1, d)['durationDays'], isNotNull);
    });
    test('defaults to a time-based, one-month plan', () {
      final d = PlanWizardDraft();
      expect((d.planType, d.durationDays, d.isRecurring), ('TIME_BASED', 30, false));
    });
    test('the presets are 1, 3, 6 and 12 months plus Custom', () {
      expect(durationPresets.map((p) => p.days), [30, 90, 180, 365, null]);
    });
  });

  group('step 3 — Court Access', () {
    test('needs a court, a playing day and a time slot', () {
      final errors = planFieldErrors(2, PlanWizardDraft()..playingDays = []);
      expect(errors.keys, containsAll(['courtIds', 'playingDays', 'timeWindows']));
    });
    test('a slot must end after it starts', () {
      final d = valid()
        ..timeWindows = [
          PlanTimeWindow(id: 'w', courtId: 'c1', daysOfWeek: [1], startTime: '09:00', endTime: '08:00'),
        ];
      expect(planFieldErrors(2, d)['timeWindows'], contains('end time after its start time'));
    });
    test('a slot cannot start and end at the same time', () {
      final d = valid()
        ..timeWindows = [
          PlanTimeWindow(id: 'w', courtId: 'c1', daysOfWeek: [1], startTime: '09:00', endTime: '09:00'),
        ];
      expect(planFieldErrors(2, d)['timeWindows'], isNotNull);
    });
    test('a slot with no days is rejected', () {
      final d = valid()..timeWindows = [PlanTimeWindow(id: 'w', courtId: 'c1', daysOfWeek: [])];
      expect(planFieldErrors(2, d)['timeWindows'], 'Every time slot needs at least one day.');
    });
    test('a complete step has no errors', () => expect(planFieldErrors(2, valid()), isEmpty));
    test('new slots default to a generous capacity, not a 1-member cap', () {
      expect(PlanTimeWindow(id: 'w', courtId: 'c', daysOfWeek: [1]).capacity, 999);
    });
  });

  group('step access', () {
    test('Review only opens once steps 1-3 are valid', () {
      expect(furthestReachablePlanStep(PlanWizardDraft()), 0);
      expect(furthestReachablePlanStep(PlanWizardDraft()..name = 'Gold'), 1);
      expect(furthestReachablePlanStep(valid()), 3);
    });
    test('four steps with the expected titles', () {
      expect(planWizardSteps.map((s) => s.title), ['Plan Details', 'Plan Configuration', 'Court Access', 'Review & Create']);
      expect(planWizardSteps.map((s) => s.label), ['Basic Info', 'Pricing', 'Court Access', 'Review']);
    });
  });

  group('overlapping slots', () {
    PlanTimeWindow w(String id, String court, List<int> days, String start, String end) =>
        PlanTimeWindow(id: id, courtId: court, daysOfWeek: days, startTime: start, endTime: end);

    test('same court, shared day, overlapping time', () {
      expect(windowsOverlap(w('a', 'c1', [1, 2], '07:00', '09:00'), w('b', 'c1', [2, 3], '08:00', '10:00')), isTrue);
    });
    test('back-to-back slots do not overlap', () {
      expect(windowsOverlap(w('a', 'c1', [1], '07:00', '08:00'), w('b', 'c1', [1], '08:00', '09:00')), isFalse);
    });
    test('a different court or a different day does not overlap', () {
      expect(windowsOverlap(w('a', 'c1', [1], '07:00', '09:00'), w('b', 'c2', [1], '07:00', '09:00')), isFalse);
      expect(windowsOverlap(w('a', 'c1', [1], '07:00', '09:00'), w('b', 'c1', [2], '07:00', '09:00')), isFalse);
    });
    test('findOverlap ignores the slot itself and returns the other one', () {
      final a = w('a', 'c1', [1], '07:00', '09:00');
      final b = w('b', 'c1', [1], '08:00', '10:00');
      expect(findOverlap([a, b], a)?.id, 'b');
      expect(findOverlap([a], a), isNull);
    });
  });

  group('labels', () {
    test('duration', () {
      expect(planWizardDurationLabel(30), '1 Month');
      expect(planWizardDurationLabel(90), '3 Months');
      expect(planWizardDurationLabel(365), '12 Months');
    });
    test('billing interval', () {
      expect(planBillingIntervalLabel(30), 'every month');
      expect(planBillingIntervalLabel(180), 'every 6 months');
    });
    test('price unit', () {
      expect(planPriceUnit(30), 'month');
      expect(planPriceUnit(90), '3 months');
    });
    test('a duration under a month still counts as one', () => expect(planMonths(10), 1));
  });

  test('saved features are trimmed and blanks dropped', () {
    final d = PlanWizardDraft()..features = [' Court Access ', '', '   ', 'Locker'];
    expect(composePlanFeatures(d), ['Court Access', 'Locker']);
  });

  test('draft keys for new slots are unique', () {
    expect(newPlanWindowId(), isNot(newPlanWindowId()));
  });
}
