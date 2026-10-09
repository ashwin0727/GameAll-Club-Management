import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/data/models/membership.dart';
import 'package:gameall_club_mobile/features/memberships/plan_created_screen.dart';

MembershipPlan plan({int? joining, int? deposit}) => MembershipPlan(
      id: 'p',
      facilityId: 'f',
      name: 'Badminton Monthly',
      priceInr: 2500,
      durationDays: 30,
      features: const [],
      isActive: true,
      createdAt: DateTime(2026, 9, 15, 10, 30),
      joiningFeeInr: joining,
      securityDepositInr: deposit,
    );

void main() {
  test('total amount adds joining fee and deposit', () {
    expect(planTotalAmountInr(plan(joining: 200)), 2700);
    expect(planTotalAmountInr(plan()), 2500);
  });
  test('subtitle', () {
    expect(planSubtitle('Regular Membership', 'Badminton'), 'Regular Plan • Badminton');
    expect(planSubtitle(null, null), '');
  });
  test('created on and feature count', () {
    expect(planCreatedOn(DateTime(2026, 9, 15, 10, 30)), '15 Sep 2026, 10:30 AM');
    expect(featureCountLabel(6), '6 features');
    expect(featureCountLabel(1), '1 feature');
  });
}
