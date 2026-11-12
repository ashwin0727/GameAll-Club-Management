import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/core/routing/app_router.dart';
import 'package:gameall_club_mobile/features/authentication/splash_screen.dart';

void main() {
  setUp(() => splashGate.value = false);

  testWidgets('SplashView paints the tagline immediately, with no backend needed', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SplashView()));
    expect(find.text('Manage · Book · Grow'), findsOneWidget);
    expect(find.text('Your Sports Facility'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('the splash route lets the router move on once the hold time has passed, not before', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: SplashScreen())));
    expect(splashGate.value, isFalse);

    await tester.pump(const Duration(milliseconds: 500));
    expect(splashGate.value, isFalse);

    await tester.pump(splashHold + const Duration(milliseconds: 100));
    expect(splashGate.value, isTrue);
  });
}
