import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gameall_club_mobile/core/routing/app_routes.dart';
import 'package:gameall_club_mobile/data/repositories/auth_repository.dart';
import 'package:gameall_club_mobile/data/repositories/repository_providers.dart';
import 'package:gameall_club_mobile/features/authentication/session_controller.dart';
import 'package:gameall_club_mobile/features/authentication/sign_in_screen.dart';

class _FakeAuth extends Fake implements AuthRepository {
  final logins = <String>[];

  @override
  Future<void> login({required String email, required String password}) async {
    logins.add('$email / $password');
  }
}

class _FakeSession extends SessionController {
  @override
  SessionState build() => const SessionState(isLoading: false);

  @override
  Future<void> refresh() async {}
}

Widget _app(_FakeAuth auth) {
  final router = GoRouter(
    initialLocation: AppRoutes.signIn,
    routes: [
      GoRoute(path: AppRoutes.signIn, builder: (_, _) => const SignInScreen()),
      GoRoute(path: AppRoutes.createAccount, builder: (_, _) => const Scaffold(body: Text('create-account page'))),
      GoRoute(path: AppRoutes.forgotPassword, builder: (_, _) => const Scaffold(body: Text('forgot-password page'))),
    ],
  );
  return ProviderScope(
    overrides: [authRepositoryProvider.overrideWithValue(auth), sessionControllerProvider.overrideWith(_FakeSession.new)],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  // A phone-sized screen (390 x 844 dp), as the page is designed for.
  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
  }

  testWidgets('shows the welcome heading, the two fields, Forgot Password and the facility picture', (tester) async {
    await tester.pumpWidget(_app(_FakeAuth()));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to GameAll'), findsOneWidget);
    expect(find.text('Login to manage your bookings, memberships, coaching, and more.'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Email Address'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Password'), findsOneWidget);
    expect(find.text('Forgot Password?'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
    expect(find.text('Create Account'), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is Image && w.image is AssetImage && (w.image as AssetImage).assetName == 'assets/images/login_facility.png'), findsOneWidget);
  });

  testWidgets('has no Google button and no alternative login', (tester) async {
    await tester.pumpWidget(_app(_FakeAuth()));
    await tester.pumpAndSettle();
    expect(find.textContaining('Google'), findsNothing);
    expect(find.textContaining('Mobile OTP'), findsNothing);
  });

  testWidgets('asks for both fields, then logs in with what was typed', (tester) async {
    phone(tester);
    final auth = _FakeAuth();
    await tester.pumpWidget(_app(auth));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();
    expect(find.text('Password is required.'), findsOneWidget);
    expect(auth.logins, isEmpty);

    await tester.enterText(find.widgetWithText(TextFormField, 'Email Address'), 'uma@example.com');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'secret123');
    await tester.tap(find.text('Login'));
    await tester.pump();
    expect(auth.logins, ['uma@example.com / secret123']);
  });

  testWidgets('Forgot Password and Create Account open their pages', (tester) async {
    phone(tester);
    await tester.pumpWidget(_app(_FakeAuth()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sign-in-forgot')));
    await tester.pumpAndSettle();
    expect(find.text('forgot-password page'), findsOneWidget);

    await tester.pumpWidget(_app(_FakeAuth()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create Account'));
    await tester.pumpAndSettle();
    expect(find.text('create-account page'), findsOneWidget);
  });

  testWidgets('does not overflow on a small phone at large text', (tester) async {
    tester.view.physicalSize = const Size(640, 1136);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MediaQuery(data: const MediaQueryData(size: Size(320, 568), textScaler: TextScaler.linear(1.5)), child: _app(_FakeAuth())));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
