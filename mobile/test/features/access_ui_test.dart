import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:gameall_club_mobile/data/models/facility.dart';
import 'package:gameall_club_mobile/features/authentication/session_controller.dart';
import 'package:gameall_club_mobile/features/staff/page_access_matrix.dart';
import 'package:gameall_club_mobile/shared/widgets/app_bottom_nav.dart';

Facility _facility() => Facility(
      id: 'facility-1',
      ownerId: 'owner-1',
      name: 'Champz Turf',
      type: FacilityType.multiSport,
      businessEmail: 'o@x.com',
      businessPhone: '900',
      address: const FacilityAddress(line1: 'a', area: 'b', city: 'c', state: 'd', country: 'India', pinCode: '600001'),
      status: 'ACTIVE',
      onboardingStep: OnboardingStep.completed,
    );

class _Session extends SessionController {
  _Session(this._baseRole, this._permissions);
  final String _baseRole;
  final Set<String> _permissions;

  @override
  SessionState build() => SessionState(facility: _facility(), baseRole: _baseRole, permissions: _permissions, isLoading: false);
}

Future<void> _pumpNav(WidgetTester tester, String baseRole, Set<String> permissions) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sessionControllerProvider.overrideWith(() => _Session(baseRole, permissions))],
      child: MaterialApp.router(
        routerConfig: GoRouter(routes: [
          GoRoute(path: '/', builder: (_, _) => const Scaffold(bottomNavigationBar: AppBottomNav(current: AppTab.today))),
        ]),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the bottom bar only shows the tabs the role can open', (tester) async {
    await _pumpNav(tester, 'staff', {'DASHBOARD_VIEW', 'BOOKINGS_VIEW', 'COURTS_VIEW'});
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Calendar'), findsOneWidget);
    expect(find.text('Coaching'), findsNothing);
    expect(find.text('Memberships'), findsNothing);
  });

  testWidgets('a coach-style role sees Coaching only — Today is not on the bar when Home is not granted', (tester) async {
    await _pumpNav(tester, 'staff', {'COACHING_VIEW', 'COACHING_OWN_ONLY'});
    expect(find.text('Coaching'), findsOneWidget);
    expect(find.text('Today'), findsNothing);
    expect(find.text('Calendar'), findsNothing);
  });

  testWidgets('an owner sees every tab', (tester) async {
    await _pumpNav(tester, 'owner', const {});
    for (final t in ['Today', 'Calendar', 'Coaching', 'Memberships']) {
      expect(find.text(t), findsOneWidget);
    }
  });

  testWidgets('more than four accessible destinations: four on the bar, the rest behind "+"', (tester) async {
    await _pumpNav(tester, 'staff', {
      'DASHBOARD_VIEW',
      'BOOKINGS_VIEW',
      'COURTS_VIEW',
      'GUEST_BOOKINGS_VIEW',
      'FINANCE_VIEW',
      'MAINTENANCE_VIEW',
      'USERS_VIEW',
    });
    for (final t in ['Today', 'Calendar', 'Guest Booking', 'Finance']) {
      expect(find.text(t), findsOneWidget, reason: '$t is on the bar');
    }
    expect(find.text('Maintenance'), findsNothing);
    expect(find.text('Staff'), findsNothing);

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Maintenance'), findsOneWidget);
    expect(find.text('Staff'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Refunds'), findsNothing, reason: 'not granted');
  });

  testWidgets('a role missing a usual tab gets the next destination in its place', (tester) async {
    await _pumpNav(tester, 'staff', {'DASHBOARD_VIEW', 'BOOKINGS_VIEW', 'COURTS_VIEW', 'GUEST_BOOKINGS_VIEW'});
    expect(find.text('Guest Booking'), findsOneWidget);
    expect(find.text('Coaching'), findsNothing);
  });

  testWidgets('role editor matrix: "All Edit" on a group grants every key of those pages', (tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var selected = <String>{};
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: SingleChildScrollView(
              child: PageAccessMatrix(
                selected: selected,
                canGrant: (_) => true,
                onChanged: (next) => setState(() => selected = next),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Set all').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('All Edit'));
    await tester.pumpAndSettle();
    expect(selected, containsAll(['DASHBOARD_VIEW', 'BOOKINGS_VIEW', 'BOOKINGS_CANCEL', 'TOURNAMENTS_VIEW']));
    expect(selected.contains('GUEST_BOOKINGS_VIEW'), isFalse, reason: 'other groups are untouched');
  });
}
