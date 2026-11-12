import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gameall_club_mobile/core/routing/app_routes.dart';
import 'package:gameall_club_mobile/features/authentication/intro_screen.dart';
import 'package:gameall_club_mobile/features/authentication/welcome_screen.dart';

Widget _app() {
  final router = GoRouter(
    initialLocation: AppRoutes.welcome,
    routes: [
      GoRoute(path: AppRoutes.welcome, builder: (_, _) => const WelcomeScreen()),
      GoRoute(path: AppRoutes.intro, builder: (_, _) => const IntroScreen()),
      GoRoute(path: AppRoutes.createAccount, builder: (_, _) => const Scaffold(body: Text('create-account page'))),
      GoRoute(path: AppRoutes.signIn, builder: (_, _) => const Scaffold(body: Text('sign-in page'))),
    ],
  );
  return MaterialApp.router(routerConfig: router);
}

void main() {
  group('WelcomeScreen', () {
    testWidgets('shows the pitch and both entry points', (tester) async {
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      expect(find.text('Run Your Sports Facility Smarter'), findsOneWidget);
      expect(find.text('Get Started'), findsOneWidget);
      expect(find.text('Already have an account?'), findsOneWidget);
      expect(find.text('Log In'), findsOneWidget);
    });

    testWidgets('the Get Started label and the Log In prompt are as large as on the login page', (tester) async {
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      TextStyle styleOf(String text) => tester.widget<Text>(find.text(text)).style!;
      expect(styleOf('Get Started').fontSize, 19);
      expect(styleOf('Already have an account?').fontSize, 17);
      expect(styleOf('Log In').fontSize, 17);
      expect(tester.getSize(find.byKey(const ValueKey('welcome-log-in'))).height, greaterThanOrEqualTo(48));
    });

    testWidgets('Get Started opens the intro, Log In opens sign in', (tester) async {
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('welcome-get-started')));
      await tester.pumpAndSettle();
      expect(find.text('Simplify Bookings'), findsOneWidget);

      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('welcome-log-in')));
      await tester.pumpAndSettle();
      expect(find.text('sign-in page'), findsOneWidget);
    });

    testWidgets('does not overflow on a small phone at large text', (tester) async {
      tester.view.physicalSize = const Size(640, 1136); // 320 x 568 dp
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MediaQuery(data: const MediaQueryData(size: Size(320, 568), textScaler: TextScaler.linear(1.5)), child: _app()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('IntroScreen', () {
    Future<void> openIntro(WidgetTester tester) async {
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('welcome-get-started')));
      await tester.pumpAndSettle();
    }

    testWidgets('starts on Simplify Bookings, with Skip at the top right', (tester) async {
      await openIntro(tester);
      expect(find.text('Simplify Bookings'), findsOneWidget);
      expect(find.byKey(const ValueKey('intro-skip')), findsOneWidget);
      // Top right: the Skip button sits in the right half and the top fifth of the screen.
      final skip = tester.getCenter(find.byKey(const ValueKey('intro-skip')));
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      expect(skip.dx, greaterThan(screen.width / 2));
      expect(skip.dy, lessThan(screen.height / 5));
    });

    testWidgets('moves to the next page by itself after five seconds, not before', (tester) async {
      await openIntro(tester);
      await tester.pump(const Duration(seconds: 4));
      expect(find.text('Simplify Bookings'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.text('Grow Your Business'), findsOneWidget);
      expect(find.text('create-account page'), findsNothing);
    });

    testWidgets('after the last page it goes on to Create Account', (tester) async {
      await openIntro(tester);
      await tester.pump(introAutoAdvance + const Duration(milliseconds: 100));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      await tester.pump(introAutoAdvance + const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(find.text('create-account page'), findsOneWidget);
    });

    testWidgets('Skip goes straight to Create Account', (tester) async {
      await openIntro(tester);
      await tester.tap(find.byKey(const ValueKey('intro-skip')));
      await tester.pumpAndSettle();
      expect(find.text('create-account page'), findsOneWidget);
    });

    testWidgets('swiping moves on and restarts the five-second countdown', (tester) async {
      await openIntro(tester);
      await tester.pump(const Duration(seconds: 3));
      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.text('Grow Your Business'), findsOneWidget);

      // Four seconds after the swipe is still the second page: the timer started over at the swipe.
      await tester.pump(const Duration(seconds: 4));
      expect(find.text('Grow Your Business'), findsOneWidget);
      expect(find.text('create-account page'), findsNothing);
    });

    testWidgets('does not overflow on a small phone at large text', (tester) async {
      tester.view.physicalSize = const Size(640, 1136);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MediaQuery(data: const MediaQueryData(size: Size(320, 568), textScaler: TextScaler.linear(1.5)), child: _app()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('welcome-get-started')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
