import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/data/models/app_user.dart';
import 'package:gameall_club_mobile/features/authentication/session_controller.dart';
import 'package:gameall_club_mobile/features/profile/profile_screen.dart';

class _Owner extends SessionController {
  @override
  SessionState build() => const SessionState(
        user: AppUser(id: 'u1', fullName: 'Uma Shankar', email: 'uma@example.com', role: 'admin', onboardingCompleted: true),
        baseRole: 'owner',
        isLoading: false,
      );
}

/// [tall]: a screen tall enough to build the whole list at once (the list only builds what is near the screen).
Future<void> _open(WidgetTester tester, {bool tall = true}) async {
  tester.view.physicalSize = tall ? const Size(780, 9000) : const Size(780, 1688); // 390 wide; 4500 or 844 dp tall
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [sessionControllerProvider.overrideWith(_Owner.new)],
    child: const MaterialApp(home: ProfileScreen()),
  ));
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _toggle(WidgetTester tester, String section) async {
  final heading = find.text(section);
  await tester.ensureVisible(heading);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(heading);
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('every management starts closed, with its heading showing', (tester) async {
    await _open(tester);
    expect(find.text('Guest Management'), findsOneWidget);
    expect(find.text('Memberships Management'), findsOneWidget);
    expect(find.text('Membership Plan', skipOffstage: false), findsNothing);
    expect(find.text('Guest Booking', skipOffstage: false), findsNothing);
  });

  testWidgets('a section opens and closes when its heading is tapped', (tester) async {
    await _open(tester);
    await _toggle(tester, 'Memberships Management');
    expect(find.text('Membership Plan'), findsOneWidget);

    await _toggle(tester, 'Memberships Management');
    expect(find.text('Membership Plan', skipOffstage: false), findsNothing);
  });

  testWidgets('opening one section leaves the others open: nothing closes by itself', (tester) async {
    await _open(tester);
    await _toggle(tester, 'Memberships Management');
    await _toggle(tester, 'Finance');
    await _toggle(tester, 'Guest Management');

    // all three are open at once
    expect(find.text('Membership Plan', skipOffstage: false), findsOneWidget);
    expect(find.text('Refunds', skipOffstage: false), findsOneWidget);
    expect(find.text('Guest Booking', skipOffstage: false), findsOneWidget);
  });

  testWidgets('an open section is still open after it has been scrolled out of view and back', (tester) async {
    await _open(tester, tall: false);
    await _toggle(tester, 'Guest Management');
    expect(find.text('Guest Booking'), findsOneWidget);

    // far down the page: the open section is now well outside the list's built area and is discarded
    final list = find.byType(Scrollable).first;
    await tester.drag(list, const Offset(0, -4000));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Guest Booking', skipOffstage: true), findsNothing);

    // and back up
    await tester.drag(list, const Offset(0, 4000));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Guest Management'), findsOneWidget);
    expect(find.text('Guest Booking'), findsOneWidget, reason: 'the section closed itself while it was off-screen');
  });
}
