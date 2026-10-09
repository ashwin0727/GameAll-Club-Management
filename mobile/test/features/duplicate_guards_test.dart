import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/data/models/membership.dart';
import 'package:gameall_club_mobile/features/memberships/duplicate_guards.dart';

SlotShape slot(List<int> days, String start, String end, {String court = 'c1'}) =>
    SlotShape(courtId: court, daysOfWeek: days, startTime: start, endTime: end);

AssignableBatch batch(String id, String plan, List<int> days, String start, String end, {String court = 'c1'}) => AssignableBatch(
      batchId: id,
      name: 'b',
      planId: plan,
      courtId: court,
      courtName: 'Court',
      facilitySportId: 'fs',
      sportName: 'Badminton',
      daysOfWeek: days,
      startTime: start,
      endTime: end,
      capacity: 999,
      enrolledCount: 0,
      spare: 999,
    );

MembershipPlan plan(String id, String name) => MembershipPlan(
      id: id,
      facilityId: 'f',
      name: name,
      priceInr: 1,
      durationDays: 30,
      features: const [],
      isActive: true,
      createdAt: DateTime(2026),
    );

MembershipListRow row({String phone = '9876543210', String planId = 'p1', String planName = 'Morning', MembershipListStatus status = MembershipListStatus.active}) =>
    MembershipListRow(
      membershipId: 'm1',
      memberId: 'x',
      memberName: 'Arun',
      memberPhone: phone,
      planId: planId,
      planName: planName,
      monthlyPriceInr: 1,
      status: status,
      startDate: DateTime(2026, 10, 1),
      endDate: DateTime(2026, 10, 31),
    );

void main() {
  const monFri = [1, 2, 3, 4, 5];
  final plans = [plan('p1', 'Morning')];
  final batches = [batch('b1', 'p1', monFri, '05:00:00', '06:00:00')];

  group('findDuplicatePlan', () {
    test('flags the exact same days and timing', () {
      expect(findDuplicatePlan([slot(monFri, '05:00', '06:00')], plans, batches)?.id, 'p1');
    });
    test('ignores day order', () => expect(findDuplicatePlan([slot([5, 4, 3, 2, 1], '05:00', '06:00')], plans, batches)?.id, 'p1'));
    test('allows Mon-Sun at the same hours', () {
      expect(findDuplicatePlan([slot([0, 1, 2, 3, 4, 5, 6], '05:00', '06:00')], plans, batches), isNull);
    });
    test('allows different hours or another court', () {
      expect(findDuplicatePlan([slot(monFri, '06:00', '07:00')], plans, batches), isNull);
      expect(findDuplicatePlan([slot(monFri, '05:00', '06:00', court: 'c2')], plans, batches), isNull);
    });
    test('needs the whole slot set to match', () {
      expect(findDuplicatePlan([slot(monFri, '05:00', '06:00'), slot(monFri, '18:00', '19:00')], plans, batches), isNull);
    });
    test('skips the plan being edited and empty drafts', () {
      expect(findDuplicatePlan([slot(monFri, '05:00', '06:00')], plans, batches, ignorePlanId: 'p1'), isNull);
      expect(findDuplicatePlan([], plans, batches), isNull);
    });
  });

  group('findDuplicateMember', () {
    final p = plan('p1', 'Morning');
    test('same phone on the same plan, however typed', () {
      expect(findDuplicateMember([row()], p, '+91 98765 43210'), isNotNull);
      expect(findDuplicateMember([row()], p, '9876543210'), isNotNull);
    });
    test('another plan, another person, or a lapsed membership is fine', () {
      expect(findDuplicateMember([row(planId: 'p2', planName: 'Evening')], p, '9876543210'), isNull);
      expect(findDuplicateMember([row(phone: '9000000000')], p, '9876543210'), isNull);
      expect(findDuplicateMember([row(status: MembershipListStatus.inactive)], p, '9876543210'), isNull);
    });
    test('matches by plan name when there is no plan id', () {
      expect(findDuplicateMember([row(planId: '')], p, '9876543210'), isNotNull);
    });
    test('ignores a too-short number', () => expect(findDuplicateMember([row()], p, '98'), isNull));
  });
}
