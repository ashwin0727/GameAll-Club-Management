import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_player/features/welcome/welcome_screen.dart';

void main() {
  Future<void> pump(WidgetTester tester, {VoidCallback? onGetStarted, Size size = const Size(390, 844)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: WelcomeScreen(onGetStarted: onGetStarted)));
  }

  testWidgets('shows the brand, tagline, headline, promise and the button', (tester) async {
    await pump(tester);
    expect(find.text('PLAY  ·  BOOK  ·  COMPETE'), findsOneWidget);
    expect(find.text('Your'), findsOneWidget);
    expect(find.text('Badminton'), findsOneWidget);
    expect(find.text('Playground'), findsOneWidget);
    expect(find.text('Book courts, manage memberships, join tournaments and more.'), findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);
    // "Game" + "All" are two coloured spans of one wordmark.
    expect(find.bySemanticsLabel('GameAll'), findsOneWidget);
  });

  testWidgets('Get Started calls back', (tester) async {
    var taps = 0;
    await pump(tester, onGetStarted: () => taps++);
    await tester.tap(find.text('Get Started'));
    expect(taps, 1);
  });

  testWidgets('does not overflow on a small phone or with large system text', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pump(tester, size: const Size(320, 640));
    expect(tester.takeException(), isNull);
  });
}
