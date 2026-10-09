import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gameall_club_mobile/core/theme/app_theme.dart';
import 'package:gameall_club_mobile/data/models/membership.dart';
import 'package:gameall_club_mobile/data/repositories/membership_repository.dart';
import 'package:gameall_club_mobile/data/repositories/repository_providers.dart';
import 'package:gameall_club_mobile/features/memberships/membership_plan_edit_sheet.dart';

class _Fake implements MembershipRepository {
  String? savedName;
  int? savedJoining;

  @override
  Future<List<MembershipPlan>> getFacilityPlans(String facilityId, {bool activeOnly = false}) async => [_plan('other', 'Evening')];

  @override
  Future<MembershipPlan> updatePlan(String planId,
      {String? name, int? priceInr, int? durationDays, List<String>? features, bool? isActive, String? description, String? category,
      int? joiningFeeInr, int? securityDepositInr, bool setBadge = false, String? badgeText}) async {
    savedName = name;
    savedJoining = joiningFeeInr;
    expect(priceInr, isNull, reason: 'the price is locked');
    return _plan(planId, name ?? 'x');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MembershipPlan _plan(String id, String name) => MembershipPlan(
      id: id,
      facilityId: 'f',
      name: name,
      priceInr: 2500,
      durationDays: 30,
      features: const [],
      isActive: true,
      createdAt: DateTime(2026),
    );

void main() {
  Future<_Fake> open(WidgetTester tester) async {
    final fake = _Fake();
    tester.view.physicalSize = const Size(390 * 3, 1800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [membershipRepositoryProvider.overrideWithValue(fake)],
        child: MaterialApp(theme: AppTheme.light(), home: Scaffold(body: MembershipPlanEditSheet(plan: _plan('p1', 'Morning')))),
      ),
    );
    return fake;
  }

  testWidgets('name and fees are editable; price and duration are locked', (tester) async {
    final fake = await open(tester);
    expect(find.widgetWithText(TextField, 'Plan Name *'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Joining Fee (₹)'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Security Deposit (₹)'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Price (₹)'), findsNothing);
    expect(find.byIcon(Icons.lock_outline), findsNWidgets(2));

    await tester.enterText(find.widgetWithText(TextField, 'Plan Name *'), 'Early Morning');
    await tester.enterText(find.widgetWithText(TextField, 'Joining Fee (₹)'), '300');
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();
    expect(fake.savedName, 'Early Morning');
    expect(fake.savedJoining, 300);
  });

  testWidgets('a name another plan already has is refused', (tester) async {
    final fake = await open(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Plan Name *'), 'evening');
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();
    expect(find.text('Another plan already has this name.'), findsOneWidget);
    expect(fake.savedName, isNull);
  });
}
