// Automated UI test — runs the *real* app against your real Supabase
// project on a connected device, exactly like a person tapping through it.
//
// Requires the device already signed in to an account with an onboarded
// facility (courts + sports set up) — this test does not sign in for you.
//
// Run:
//   flutter test integration_test/seed_test_data_test.dart \
//     -d <device-id> --dart-define-from-file=env.json
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:gameall_club_mobile/core/config/app_config.dart';
import 'package:gameall_club_mobile/core/routing/app_routes.dart';
import 'package:gameall_club_mobile/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseAnonKey,
    );
  });

  Future<void> boot(WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: GameAllClubApp()));
    await tester.pumpAndSettle(const Duration(seconds: 5));
  }

  void goTo(WidgetTester tester, String route) {
    final ctx = tester.element(find.byType(MaterialApp));
    GoRouter.of(ctx).push(route);
  }

  testWidgets('creates 5 guest bookings for today', (tester) async {
    await boot(tester);
    expect(
      find.textContaining('Sign in', findRichText: true),
      findsNothing,
      reason: 'Device must already be signed in to an onboarded account before running this test.',
    );

    goTo(tester, AppRoutes.bookings);
    await tester.pumpAndSettle(const Duration(seconds: 3));

    for (var i = 1; i <= 5; i++) {
      final slot = find.text('Available');
      expect(slot, findsWidgets, reason: 'No "Available" slot left to book (#$i) — courts may be fully booked today.');
      await tester.tap(slot.first);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(find.text('Quick Booking'), findsOneWidget, reason: 'Tapping a slot did not open the Quick Booking sheet.');

      await tester.tap(find.text('+ Create New Guest'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'Guest name'), 'Automated Guest $i');
      await tester.enterText(find.widgetWithText(TextField, 'Phone (optional)'), '900000000$i');
      await tester.tap(find.text('Save Guest'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Confirm Booking'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.text('Quick Booking'), findsNothing, reason: 'Booking #$i did not complete — sheet is still open.');
    }
  });

  testWidgets('creates 3 memberships', (tester) async {
    await boot(tester);

    for (var i = 1; i <= 3; i++) {
      goTo(tester, AppRoutes.membershipsNew);
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(find.text('Register a new member'), findsOneWidget, reason: 'Create Membership screen did not open.');

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Automated Member $i'); // Full Name
      await tester.enterText(fields.at(1), '700000000$i'); // Phone Number
      await tester.enterText(fields.at(4), 'Automated Plan $i'); // Membership Name

      await tester.tap(find.text('Select duration'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1 Month').last);
      await tester.pumpAndSettle();

      await tester.enterText(fields.at(6), '500'); // Membership Fee

      await tester.tap(find.text('Create Membership').last);
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(
        find.text('Register a new member'),
        findsNothing,
        reason: 'Membership #$i did not save — form is still open (check for a validation error on screen).',
      );
    }
  });
}
