import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gameall_club_mobile/core/theme/app_theme.dart';
import 'package:gameall_club_mobile/data/models/facility.dart';
import 'package:gameall_club_mobile/data/models/membership.dart';
import 'package:gameall_club_mobile/data/models/membership_session.dart';
import 'package:gameall_club_mobile/data/models/playing_area.dart';
import 'package:gameall_club_mobile/data/models/sport.dart';
import 'package:gameall_club_mobile/data/repositories/membership_repository.dart';
import 'package:gameall_club_mobile/data/repositories/membership_session_repository.dart';
import 'package:gameall_club_mobile/data/repositories/playing_area_repository.dart';
import 'package:gameall_club_mobile/data/repositories/repository_providers.dart';
import 'package:gameall_club_mobile/data/repositories/sports_repository.dart';
import 'package:gameall_club_mobile/features/authentication/session_controller.dart';
import 'package:gameall_club_mobile/features/memberships/membership_plan_wizard_screen.dart';

/// Drives the Create Plan wizard end to end — Plan Details → Plan Configuration → Court Access →
/// Review & Create — against fake repositories, checking both that every step lays out without a
/// rendering error and that what is saved is what was entered.

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

class _FakePlayingAreas implements PlayingAreaRepository {
  @override
  Future<List<PlayingArea>> getPlayingAreas(String facilityId) async => const [
        PlayingArea(
          id: 'court-1',
          facilityId: 'facility-1',
          facilitySportId: 'fs-1',
          sportId: 'sport-1',
          name: 'Court 1',
          areaType: 'INDOOR',
          status: 'ACTIVE',
          bookingEnabled: true,
          archived: false,
          displayOrder: 0,
        ),
        PlayingArea(
          id: 'court-2',
          facilityId: 'facility-1',
          facilitySportId: 'fs-1',
          sportId: 'sport-1',
          name: 'Court 2',
          areaType: 'OUTDOOR',
          status: 'ACTIVE',
          bookingEnabled: true,
          archived: false,
          displayOrder: 1,
        ),
        PlayingArea(
          id: 'court-off',
          facilityId: 'facility-1',
          facilitySportId: 'fs-1',
          sportId: 'sport-1',
          name: 'Closed Court',
          areaType: 'INDOOR',
          status: 'INACTIVE',
          bookingEnabled: true,
          archived: false,
          displayOrder: 2,
        ),
      ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSports implements SportsRepository {
  @override
  Future<List<Sport>> getActiveSports() async => const [
        Sport(id: 'sport-1', name: 'Badminton', code: 'BADMINTON', icon: '🏸', description: '', isActive: true),
      ];

  @override
  Future<List<FacilitySport>> getFacilitySports(String facilityId) async =>
      const [FacilitySport(id: 'fs-1', facilityId: 'facility-1', sportId: 'sport-1', enabled: true)];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMembership implements MembershipRepository {
  final created = <MembershipPlanInput>[];
  int failBatchesTimes = 0;

  @override
  Future<List<MembershipPlan>> getFacilityPlans(String facilityId, {bool activeOnly = false}) async => const [];

  @override
  Future<List<AssignableBatch>> listAssignableBatches(String facilityId, {String? planId}) async => const [];

  @override
  Future<MembershipPlan> createPlan(MembershipPlanInput input) async {
    created.add(input);
    return MembershipPlan(
      id: 'plan-1',
      facilityId: input.facilityId,
      name: input.name,
      priceInr: input.priceInr,
      durationDays: input.durationDays,
      features: input.features,
      isActive: true,
      createdAt: DateTime(2026, 10, 9),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSessions implements MembershipSessionRepository {
  final batches = <MembershipBatchInput>[];

  @override
  Future<MembershipBatch> createBatch(MembershipBatchInput input) async {
    batches.add(input);
    return MembershipBatch(
      id: 'batch-${batches.length}',
      facilityId: input.facilityId,
      planId: input.planId,
      facilitySportId: input.facilitySportId,
      courtId: input.courtId,
      name: input.name,
      daysOfWeek: input.daysOfWeek,
      startTime: input.startTime,
      endTime: input.endTime,
      capacity: input.capacity,
      isActive: true,
      createdAt: DateTime(2026, 10, 9),
      updatedAt: DateTime(2026, 10, 9),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakeMembership membership;
  late _FakeSessions sessions;
  bool? popped;

  Future<void> open(WidgetTester tester) async {
    membership = _FakeMembership();
    sessions = _FakeSessions();
    popped = null;
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionControllerProvider.overrideWith(_FakeSession.new),
          playingAreaRepositoryProvider.overrideWithValue(_FakePlayingAreas()),
          sportsRepositoryProvider.overrideWithValue(_FakeSports()),
          membershipRepositoryProvider.overrideWithValue(membership),
          membershipSessionRepositoryProvider.overrideWithValue(sessions),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async => popped = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(builder: (_) => const MembershipPlanWizardScreen()),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// The wizard is a lazy ListView, so anything below the fold does not exist until scrolled to.
  Future<Finder> reveal(WidgetTester tester, Finder finder) async {
    // Scroll by jumping, not by simulated drags: a drag ends with a fling whose momentum would keep
    // scrolling the list after the app has (correctly) reset it to the top.
    final position = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    for (var i = 0; i < 60 && finder.evaluate().isEmpty; i++) {
      position.jumpTo((position.pixels + 150).clamp(0, position.maxScrollExtent));
      await tester.pump();
    }
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    return finder;
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.tap(await reveal(tester, find.text(text)));
    await tester.pumpAndSettle();
  }

  Future<void> enterField(WidgetTester tester, String label, String value) async {
    await tester.enterText(await reveal(tester, find.widgetWithText(TextField, label)), value);
    await tester.pump();
  }

  Future<void> tapNext(WidgetTester tester) async {
    await tester.tap(find.textContaining('Next: '));
    await tester.pumpAndSettle();
  }

  Future<void> tapCreate(WidgetTester tester) async {
    // "Create Plan" is also the app bar title — the button is the one to press.
    await tester.tap(find.widgetWithText(FilledButton, 'Create Plan'));
    await tester.pumpAndSettle();
  }

  testWidgets('step 1 shows the Plan Details fields and the four-step header', (tester) async {
    await open(tester);
    expect(tester.takeException(), isNull);
    for (final t in ['Basic Info', 'Pricing', 'Court Access', 'Review', 'Plan Details', 'Plan Badge']) {
      expect(find.text(t), findsWidgets, reason: t);
    }
    expect(find.text('Plan Name *'), findsOneWidget);
    expect(find.text('Regular Membership'), findsOneWidget); // the category dropdown's default
  });

  testWidgets('Next is blocked, with a message, until the plan has a name', (tester) async {
    await open(tester);
    await tapNext(tester);
    expect(find.text('Plan name is required.'), findsOneWidget);
    expect(find.text('Plan Configuration'), findsNothing);
  });

  testWidgets('the category dropdown lists the five categories', (tester) async {
    await open(tester);
    await tester.tap(find.text('Regular Membership'));
    await tester.pumpAndSettle();
    for (final c in ['Premium Membership', 'Student Membership', 'Corporate Membership', 'Other']) {
      expect(find.text(c), findsWidgets, reason: c);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('walks all four steps and saves the plan and its time slot', (tester) async {
    await open(tester);

    // 1 — Plan Details
    await tester.enterText(find.widgetWithText(TextField, 'Plan Name *'), 'Monthly Membership');
    await tester.pump();
    await tapNext(tester);
    expect(find.text('Plan Type *'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 2 — Plan Configuration: a price is required
    await tapNext(tester);
    expect(find.text('Price must be greater than 0.'), findsOneWidget);
    await enterField(tester, 'Price (₹) *', '2500');
    await enterField(tester, 'Joining Fee (Optional)', '500');
    await tapNext(tester);
    expect(find.text('Select Courts'), findsOneWidget);
    expect(find.text('Closed Court'), findsNothing); // inactive courts are not offered
    expect(tester.takeException(), isNull);

    // 3 — Court Access: needs a court and a slot
    await tapNext(tester);
    expect(find.text('Select at least one court.'), findsOneWidget);
    await tapText(tester, 'Court 1');
    await tapText(tester, 'Add Time Slot');
    await reveal(tester, find.text('Start'));
    expect(find.text('Start'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tapNext(tester);

    // 4 — Review & Create
    expect(find.text('Review & Create'), findsWidgets);
    expect(find.text('Monthly Membership'), findsWidgets);
    expect(find.text('₹2,500'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tapCreate(tester);

    expect(membership.created, hasLength(1));
    final plan = membership.created.single;
    expect(plan.name, 'Monthly Membership');
    expect(plan.priceInr, 2500);
    expect(plan.durationDays, 30);
    expect(plan.planType, 'TIME_BASED');
    expect(plan.category, 'Regular Membership');
    expect(plan.joiningFeeInr, 500);
    expect(plan.securityDepositInr, isNull);
    expect(plan.badgeText, 'Popular');

    expect(sessions.batches, hasLength(1));
    final slot = sessions.batches.single;
    expect(slot.planId, 'plan-1');
    expect(slot.courtId, 'court-1');
    expect(slot.facilitySportId, 'fs-1');
    expect(slot.daysOfWeek, [1, 2, 3, 4, 5]);
    expect(slot.startTime, '07:00');
    expect(slot.endTime, '08:00');
    expect(slot.capacity, 999);

    expect(popped, isTrue, reason: 'the wizard closes with true so the Plans list refreshes');
    expect(find.text('Plan Created Successfully!'), findsOneWidget);
    expect(find.text('View Plan'), findsOneWidget);
    expect(find.text('Create Another Plan'), findsOneWidget);
    expect(find.text('Go to Membership Plans'), findsOneWidget);
    expect(find.text('Total Amount'), findsOneWidget);
  });

  testWidgets('a recurring plan shows its billing options and saves as RECURRING', (tester) async {
    await open(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Plan Name *'), 'Auto Plan');
    await tester.pump();
    await tapNext(tester);

    await tapText(tester, 'Recurring');
    expect(find.text('Billing Interval *'), findsOneWidget);
    await reveal(tester, find.text('Auto-Renewal'));
    expect(find.text('Recurring Payment'), findsOneWidget);
    expect(find.text('Auto-Renewal'), findsOneWidget);
    expect(find.text('Price per billing cycle (₹) *'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await enterField(tester, 'Price per billing cycle (₹) *', '1000');
    await tapNext(tester);
    await tapText(tester, 'Court 1');
    await tapText(tester, 'Add Time Slot');
    await tapNext(tester);
    await tapCreate(tester);

    expect(membership.created.single.planType, 'RECURRING');
    expect(membership.created.single.priceInr, 1000);
  });

  testWidgets('turning the badge off saves no badge', (tester) async {
    await open(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Plan Name *'), 'No Badge');
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Badge text'), findsNothing);
    await tapNext(tester);
    await enterField(tester, 'Price (₹) *', '900');
    await tapNext(tester);
    await tapText(tester, 'Court 2');
    await tapText(tester, 'Add Time Slot');
    await tapNext(tester);
    await tapCreate(tester);

    expect(membership.created.single.badgeText, isNull);
    expect(sessions.batches.single.courtId, 'court-2');
  });

  testWidgets('every step opens at its top, even after scrolling the one before it', (tester) async {
    await open(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Plan Name *'), 'Scroll Check');
    await tester.pump();
    await tapNext(tester);

    // Scroll to the bottom of Plan Configuration, then move on.
    await enterField(tester, 'Security Deposit (Optional)', '1000');
    await enterField(tester, 'Price (₹) *', '2500');
    double offset() => tester.state<ScrollableState>(find.byType(Scrollable).first).position.pixels;
    await reveal(tester, find.text('This membership has a fixed duration and will expire automatically at the end of the selected period.'));
    expect(offset(), greaterThan(0), reason: 'the test needs to have scrolled down first');

    await tapNext(tester);
    expect(offset(), 0, reason: 'Court Access must open at its top, not part-way down');
    expect(find.text('Court Access'), findsWidgets);
    expect(find.text('Select Courts'), findsOneWidget);
  });

  testWidgets('Back returns to the previous step and keeps what was typed', (tester) async {
    await open(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Plan Name *'), 'Keep Me');
    await tester.pump();
    await tapNext(tester);
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Keep Me'), findsOneWidget);
  });
}
