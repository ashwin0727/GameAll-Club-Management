import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gameall_club_mobile/core/theme/app_theme.dart';
import 'package:gameall_club_mobile/data/models/membership.dart';
import 'package:gameall_club_mobile/data/models/membership_session.dart';
import 'package:gameall_club_mobile/data/repositories/membership_repository.dart';
import 'package:gameall_club_mobile/data/repositories/membership_session_repository.dart';
import 'package:gameall_club_mobile/data/repositories/repository_providers.dart';
import 'package:gameall_club_mobile/features/memberships/manage_plan_slots_screen.dart';
import 'package:gameall_club_mobile/features/memberships/plan_slot_edit.dart';

AssignableBatch _batch(int capacity, int enrolled) => AssignableBatch(
      batchId: 'b1',
      name: 'Morning',
      planId: 'p1',
      courtId: 'c1',
      courtName: 'Court 1',
      facilitySportId: 'fs',
      sportName: 'Badminton',
      daysOfWeek: const [1, 2, 3],
      startTime: '07:00:00',
      endTime: '08:00:00',
      capacity: capacity,
      enrolledCount: enrolled,
      spare: capacity - enrolled,
    );

class _FakeMembership implements MembershipRepository {
  int capacity = 20;

  @override
  Future<List<AssignableBatch>> listAssignableBatches(String facilityId, {String? planId}) async => [_batch(capacity, 2)];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSessions implements MembershipSessionRepository {
  int? savedCapacity;

  @override
  Future<MembershipBatch> updateBatch(String batchId,
      {String? name, String? courtId, List<int>? daysOfWeek, String? startTime, String? endTime, int? capacity, bool? isActive}) async {
    savedCapacity = capacity;
    return MembershipBatch(
      id: batchId,
      facilityId: 'f',
      planId: 'p1',
      facilitySportId: 'fs',
      courtId: 'c1',
      name: 'Morning',
      daysOfWeek: const [1],
      startTime: '07:00',
      endTime: '08:00',
      capacity: capacity ?? 0,
      isActive: true,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('validateSlotEdit', () {
    String? v({List<int> days = const [1], String s = '07:00', String e = '08:00', int? cap = 10, int enrolled = 0}) =>
        validateSlotEdit(days: days, startTime: s, endTime: e, capacity: cap, enrolled: enrolled);

    test('valid', () => expect(v(), isNull));
    test('needs a day', () => expect(v(days: []), isNotNull));
    test('end after start', () {
      expect(v(s: '09:00', e: '08:00'), isNotNull);
      expect(v(s: '08:00', e: '08:00'), isNotNull);
    });
    test('capacity at least 1 and not below enrolled', () {
      expect(v(cap: 0), isNotNull);
      expect(v(cap: null), isNotNull);
      expect(v(cap: 3, enrolled: 5), contains('5 members are already'));
      expect(v(cap: 5, enrolled: 5), isNull);
    });
  });

  testWidgets('editing a slot capacity saves it and shows the new number', (tester) async {
    final membership = _FakeMembership();
    final sessions = _FakeSessions();
    tester.view.physicalSize = const Size(390 * 3, 1800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final plan = MembershipPlan(
      id: 'p1',
      facilityId: 'f',
      name: 'Badminton Monthly',
      priceInr: 2500,
      durationDays: 30,
      features: const [],
      isActive: true,
      createdAt: DateTime(2026, 9, 1),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          membershipRepositoryProvider.overrideWithValue(membership),
          membershipSessionRepositoryProvider.overrideWithValue(sessions),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: ManagePlanSlotsScreen(plan: plan, facilityId: 'f', batches: [_batch(20, 2)], members: const []),
        ),
      ),
    );
    expect(find.text('Slot Rules'), findsOneWidget);
    expect(find.text('20'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Slot Settings'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Slot capacity *'), '30');
    membership.capacity = 30;
    await tester.tap(find.widgetWithText(FilledButton, 'Save Changes'));
    await tester.pumpAndSettle();

    expect(sessions.savedCapacity, 30);
    expect(find.text('30'), findsOneWidget);
  });
}
