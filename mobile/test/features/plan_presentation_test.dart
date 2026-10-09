import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/data/models/membership.dart';
import 'package:gameall_club_mobile/features/memberships/plan_presentation.dart';

/// How a plan reads in the Plans list and on Plan Details.
void main() {
  MembershipPlan plan(String name, int price, int days, {bool active = true, String? category}) => MembershipPlan(
        id: name,
        facilityId: 'f1',
        name: name,
        priceInr: price,
        durationDays: days,
        features: const [],
        isActive: active,
        createdAt: DateTime(2026, 9, 1),
        category: category,
      );

  AssignableBatch batch(String planId, String sport) => AssignableBatch(
        batchId: 'b_$planId$sport',
        name: 'B',
        planId: planId,
        courtId: 'c',
        courtName: 'Court 1',
        facilitySportId: 's',
        sportName: sport,
        daysOfWeek: const [1],
        startTime: '07:00',
        endTime: '08:00',
        capacity: 10,
        enrolledCount: 4,
        spare: 6,
      );

  group('planPeriodLabel — the unit after the price', () {
    test('a month', () => expect(planPeriodLabel(30), '/ month'));
    test('a few months', () => expect(planPeriodLabel(90), '/ 3 months'));
    test('a year', () => expect(planPeriodLabel(365), '/ year'));
    test('several years', () => expect(planPeriodLabel(730), '/ 2 years'));
    test('under a month is counted in days', () => expect(planPeriodLabel(15), '/ 15 days'));
    test('one day is singular', () => expect(planPeriodLabel(1), '/ 1 day'));
  });

  group('planDurationLabel', () {
    test('months', () => expect(planDurationLabel(30), '1 Month'));
    test('plural months', () => expect(planDurationLabel(180), '6 Months'));
    test('a year', () => expect(planDurationLabel(365), '1 Year'));
    test('days', () => expect(planDurationLabel(7), '7 Days'));
  });

  group('planMonthlyEquivalentInr', () {
    test('a three-month plan works out per month', () => expect(planMonthlyEquivalentInr(6000, 90), 2000));
    test('a plan of a month or less has none', () {
      expect(planMonthlyEquivalentInr(2500, 30), isNull);
      expect(planMonthlyEquivalentInr(500, 7), isNull);
    });
  });

  group('planSportLabel', () {
    test("a plan's own category wins", () => expect(planSportLabel(plan('A', 1, 30, category: 'Badminton'), [batch('A', 'Tennis')]), 'Badminton'));
    test('otherwise the sport of its slots', () => expect(planSportLabel(plan('A', 1, 30), [batch('A', 'Tennis')]), 'Tennis'));
    test('slots across several sports read as Multi Sport', () {
      expect(planSportLabel(plan('A', 1, 30), [batch('A', 'Tennis'), batch('A', 'Badminton')]), 'Multi Sport');
    });
    test('nothing known gives null', () {
      expect(planSportLabel(plan('A', 1, 30), const []), isNull);
      expect(planSportLabel(plan('A', 1, 30, category: '  '), const []), isNull);
    });
  });

  group('planIcon', () {
    test('names a sport icon where it can', () {
      expect(planIcon(plan('Badminton Monthly', 1, 30)), Icons.sports_tennis_rounded);
      expect(planIcon(plan('Football Annual', 1, 365)), Icons.sports_soccer_rounded);
      expect(planIcon(plan('Fitness Plan', 1, 30)), Icons.fitness_center_rounded);
    });
    test('falls back to a generic membership icon', () => expect(planIcon(plan('Gold', 1, 30)), Icons.card_membership_rounded));
  });

  group('filters and counts', () {
    final plans = [
      plan('Badminton Monthly', 2500, 30, category: 'Badminton'),
      plan('Tennis Quarterly', 6000, 90, category: 'Tennis'),
      plan('Fitness Plan', 2000, 30, active: false, category: 'General Fitness'),
    ];

    test('counts per chip', () {
      final c = planFilterCounts(plans);
      expect((c.all, c.active, c.inactive), (3, 2, 1));
    });
    test('Active and Inactive', () {
      expect(filterPlans(plans, filter: PlanFilter.active), hasLength(2));
      expect(filterPlans(plans, filter: PlanFilter.inactive).single.name, 'Fitness Plan');
    });
    test('search matches the name or the sport, ignoring case', () {
      expect(filterPlans(plans, query: 'tennis').single.name, 'Tennis Quarterly');
      expect(filterPlans(plans, query: 'FITNESS').single.name, 'Fitness Plan');
      expect(filterPlans(plans, query: 'zzz'), isEmpty);
    });
    test('status and search combine', () {
      expect(filterPlans(plans, filter: PlanFilter.inactive, query: 'badminton'), isEmpty);
    });
  });

  group('sortPlans', () {
    final plans = [plan('B', 6000, 90), plan('a', 2500, 30), plan('C', 2000, 30)];

    test('price low to high', () => expect(sortPlans(plans, PlanSort.priceLow).map((p) => p.priceInr), [2000, 2500, 6000]));
    test('price high to low', () => expect(sortPlans(plans, PlanSort.priceHigh).map((p) => p.priceInr), [6000, 2500, 2000]));
    test('name, ignoring case', () => expect(sortPlans(plans, PlanSort.name).map((p) => p.name), ['a', 'B', 'C']));
    test('most members first', () {
      final counts = {'B': 1, 'a': 9, 'C': 4};
      expect(sortPlans(plans, PlanSort.mostMembers, memberCount: (p) => counts[p.name]!).map((p) => p.name), ['a', 'C', 'B']);
    });
    test('does not reorder the list it was given', () {
      sortPlans(plans, PlanSort.name);
      expect(plans.first.name, 'B');
    });
  });

  test('a plan parses the richer columns the web saves, and tolerates their absence', () {
    final full = MembershipPlan.fromJson({
      'id': 'p1',
      'facility_id': 'f1',
      'name': 'Badminton Monthly',
      'price_inr': 2500,
      'duration_days': 30,
      'features': ['Court Access'],
      'is_active': true,
      'created_at': '2026-09-01T00:00:00Z',
      'description': 'Flexible monthly plan',
      'category': 'Badminton',
      'plan_type': 'RECURRING',
      'joining_fee_inr': 500,
      'security_deposit_inr': 1000,
      'badge_text': 'Popular',
    });
    expect(full.isRecurring, isTrue);
    expect((full.description, full.category, full.joiningFeeInr, full.securityDepositInr, full.badgeText),
        ('Flexible monthly plan', 'Badminton', 500, 1000, 'Popular'));

    final bare = MembershipPlan.fromJson({
      'id': 'p2',
      'facility_id': 'f1',
      'name': 'Old plan',
      'price_inr': 100,
      'duration_days': 30,
      'created_at': '2026-09-01T00:00:00Z',
    });
    expect(bare.isRecurring, isFalse);
    expect(bare.description, isNull);
    expect(bare.joiningFeeInr, isNull);
  });
}
