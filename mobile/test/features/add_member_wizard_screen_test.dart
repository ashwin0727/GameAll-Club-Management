import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gameall_club_mobile/core/theme/app_theme.dart';
import 'package:gameall_club_mobile/data/models/facility.dart';
import 'package:gameall_club_mobile/data/models/membership.dart';
import 'package:gameall_club_mobile/data/models/membership_session.dart';
import 'package:gameall_club_mobile/data/repositories/membership_repository.dart';
import 'package:gameall_club_mobile/data/repositories/membership_session_repository.dart';
import 'package:gameall_club_mobile/data/repositories/repository_providers.dart';
import 'package:gameall_club_mobile/features/authentication/session_controller.dart';
import 'package:gameall_club_mobile/features/memberships/add_member_wizard_screen.dart';

/// Add Member wizard end to end: Personal Information → Select Plan → Review → Payment. The member's
/// court and timings must come from the plan, with no schedule step.

Facility _facility() => Facility(
      id: 'facility-1',
      ownerId: 'owner-1',
      name: 'Test Arena',
      type: FacilityType.multiSport,
      businessEmail: 'o@x.com',
      businessPhone: '900',
      address: const FacilityAddress(line1: 'a', area: 'b', city: 'c', state: 'd', country: 'India', pinCode: '600001'),
      status: 'ACTIVE',
      onboardingStep: OnboardingStep.completed,
    );

class _FakeSession extends SessionController {
  @override
  SessionState build() => SessionState(user: null, facility: _facility(), isLoading: false);
}

AssignableBatch _batch(String id, String start) => AssignableBatch(
      batchId: id,
      name: 'b',
      planId: 'plan-1',
      courtId: 'c1',
      courtName: 'Court 1',
      facilitySportId: 'fs',
      sportName: 'Badminton',
      daysOfWeek: const [1, 2, 3],
      startTime: '$start:00',
      endTime: '${(int.parse(start.substring(0, 2)) + 1).toString().padLeft(2, '0')}:00:00',
      capacity: 999,
      enrolledCount: 0,
      spare: 999,
    );

class _FakeMembership implements MembershipRepository {
  CreateMembershipFullInput? created;
  final paid = <String>[];

  @override
  Future<List<MembershipPlan>> getFacilityPlans(String facilityId, {bool activeOnly = false}) async => [
        MembershipPlan(
          id: 'plan-1',
          facilityId: facilityId,
          name: 'Monthly Membership',
          priceInr: 2500,
          durationDays: 30,
          features: const [],
          isActive: true,
          createdAt: DateTime(2026, 10, 1),
        ),
      ];

  @override
  Future<List<AssignableBatch>> listAssignableBatches(String facilityId, {String? planId}) async =>
      [_batch('b1', '07:00'), _batch('b2', '18:00')];

  @override
  Future<MembershipListResult> listMemberships(String facilityId, MembershipListParams params) async =>
      const MembershipListResult(rows: [], totalCount: 0);

  @override
  Future<Membership> createMembershipFull(CreateMembershipFullInput input) async {
    created = input;
    return Membership.fromJson({
      'id': 'ms-1',
      'member_id': 'm-1',
      'facility_id': input.facilityId,
      'name': input.name,
      'membership_type': 'INDIVIDUAL',
      'start_date': '2026-10-09',
      'end_date': '2026-11-07',
      'status': 'ACTIVE',
      'created_at': '2026-10-09T00:00:00Z',
    }, planName: 'Monthly Membership');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSessions implements MembershipSessionRepository {
  final assigned = <String>[];

  @override
  Future<MembershipBatchMember> assignBatchMember(String batchId, String memberId, {String? membershipId}) async {
    assigned.add(batchId);
    return MembershipBatchMember(id: 'x', batchId: batchId, memberId: memberId, membershipId: membershipId, createdAt: DateTime(2026, 10, 9));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('the member joins the plan\'s own slots — no schedule step', (tester) async {
    final membership = _FakeMembership();
    final sessions = _FakeSessions();
    tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionControllerProvider.overrideWith(_FakeSession.new),
          membershipRepositoryProvider.overrideWithValue(membership),
          membershipSessionRepositoryProvider.overrideWithValue(sessions),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const AddMemberWizardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Playing Schedule'), findsNothing);

    await tester.enterText(find.widgetWithText(TextField, 'Full Name *'), 'Arun Kumar');
    await tester.enterText(find.widgetWithText(TextField, 'Phone Number *'), '9876543210');
    await tester.tap(find.textContaining('Next: Select Plan'));
    await tester.pumpAndSettle();

    // Plan step: choose the plan, its courts and timings appear read-only.
    await tester.tap(find.text('Monthly Membership'));
    await tester.pumpAndSettle();
    expect(find.text('Court 1'), findsNWidgets(2));
    expect(find.text('7:00 AM - 8:00 AM'), findsOneWidget);
    expect(find.text('6:00 PM - 7:00 PM'), findsOneWidget);

    await tester.tap(find.textContaining('Next: Review'));
    await tester.pumpAndSettle();
    expect(find.text('Review & Confirm'), findsWidgets);
    await tester.tap(find.textContaining('Next: Payment'));
    await tester.pumpAndSettle();

    // Record an offline payment.
    await tester.tap(find.text('Record Offline Payment'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Payment Amount *'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Collected By *'), 'Staff');
    await tester.tap(find.widgetWithText(FilledButton, 'Create Member'));
    await tester.pumpAndSettle();

    expect(membership.created?.batchId, 'b1');
    expect(membership.created?.paymentMode, MembershipPaymentMode.paid);
    expect(membership.created?.fullName, 'Arun Kumar');
    expect(sessions.assigned, ['b2']);
  });
}
