import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gameall_club_mobile/core/errors/app_exception.dart';
import 'package:gameall_club_mobile/core/routing/app_routes.dart';
import 'package:gameall_club_mobile/data/repositories/auth_repository.dart';
import 'package:gameall_club_mobile/data/repositories/repository_providers.dart';
import 'package:gameall_club_mobile/features/authentication/forgot_password_screen.dart';

class _FakeAuth extends Fake implements AuthRepository {
  final requests = <String>[];
  Object? fail;

  @override
  Future<void> resetPassword(String email) async {
    requests.add(email);
    final f = fail;
    if (f != null) throw f;
  }
}

/// Login page underneath, Forgot Password pushed on top: how the app reaches it.
Widget _app(_FakeAuth auth) {
  final router = GoRouter(
    initialLocation: AppRoutes.signIn,
    routes: [
      GoRoute(
        path: AppRoutes.signIn,
        builder: (context, _) => Scaffold(
          body: Center(
            child: TextButton(onPressed: () => context.push(AppRoutes.forgotPassword), child: const Text('open forgot')),
          ),
        ),
      ),
      GoRoute(path: AppRoutes.forgotPassword, builder: (_, _) => const ForgotPasswordScreen()),
    ],
  );
  return ProviderScope(
    overrides: [authRepositoryProvider.overrideWithValue(auth)],
    child: MaterialApp.router(routerConfig: router),
  );
}

Future<void> _open(WidgetTester tester, _FakeAuth auth) async {
  tester.view.physicalSize = const Size(780, 1688); // 390 x 844 dp
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(auth));
  await tester.pumpAndSettle();
  await tester.tap(find.text('open forgot'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the design: back square, heading, one email field, Send Reset Link with its arrow, Back to Login and the picture', (tester) async {
    await _open(tester, _FakeAuth());
    expect(find.byKey(const ValueKey('forgot-back')), findsOneWidget);
    expect(find.text('Forgot Password?'), findsOneWidget);
    expect(find.textContaining('No worries!'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Email Address'), findsOneWidget);
    expect(find.text('Send Reset Link'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_forward_rounded), findsOneWidget);
    expect(find.text('Back to Login'), findsOneWidget);
    expect(find.bySemanticsLabel('A phone with a padlock and a password reset badge'), findsOneWidget);
  });

  testWidgets('the process is unchanged: a valid email sends the reset link and shows Check Your Email', (tester) async {
    final auth = _FakeAuth();
    await _open(tester, auth);
    await tester.enterText(find.widgetWithText(TextFormField, 'Email Address'), 'uma@example.com');
    await tester.tap(find.text('Send Reset Link'));
    await tester.pumpAndSettle();

    expect(auth.requests, ['uma@example.com']);
    expect(find.text('Check Your Email'), findsOneWidget);
    expect(find.textContaining('If an account exists for uma@example.com'), findsOneWidget);
    expect(find.text('Back to Sign In'), findsOneWidget);
  });

  testWidgets('a bad or empty email is refused before anything is sent', (tester) async {
    final auth = _FakeAuth();
    await _open(tester, auth);
    await tester.tap(find.text('Send Reset Link'));
    await tester.pumpAndSettle();
    expect(auth.requests, isEmpty);
    expect(find.text('Check Your Email'), findsNothing);

    await tester.enterText(find.widgetWithText(TextFormField, 'Email Address'), 'not-an-email');
    await tester.tap(find.text('Send Reset Link'));
    await tester.pumpAndSettle();
    expect(auth.requests, isEmpty);
  });

  testWidgets('a server error shows its message and stays on the form', (tester) async {
    final auth = _FakeAuth()..fail = AppException(AppErrorCode.unauthorized, 'Could not send the email right now.');
    await _open(tester, auth);
    await tester.enterText(find.widgetWithText(TextFormField, 'Email Address'), 'uma@example.com');
    await tester.tap(find.text('Send Reset Link'));
    await tester.pumpAndSettle();
    expect(find.text('Could not send the email right now.'), findsOneWidget);
    expect(find.text('Forgot Password?'), findsOneWidget);
  });

  testWidgets('Back to Login and the back square both return to the login page', (tester) async {
    await _open(tester, _FakeAuth());
    await tester.tap(find.byKey(const ValueKey('forgot-back-to-login')));
    await tester.pumpAndSettle();
    expect(find.text('open forgot'), findsOneWidget);

    await tester.tap(find.text('open forgot'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('forgot-back')));
    await tester.pumpAndSettle();
    expect(find.text('open forgot'), findsOneWidget);
  });

  testWidgets('Back to Sign In on the confirmation also returns to the login page', (tester) async {
    await _open(tester, _FakeAuth());
    await tester.enterText(find.widgetWithText(TextFormField, 'Email Address'), 'uma@example.com');
    await tester.tap(find.text('Send Reset Link'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Back to Sign In'));
    await tester.pumpAndSettle();
    expect(find.text('open forgot'), findsOneWidget);
  });

  testWidgets('does not overflow on a small phone at large text', (tester) async {
    tester.view.physicalSize = const Size(640, 1136); // 320 x 568 dp
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(size: Size(320, 568), textScaler: TextScaler.linear(1.5)),
      child: _app(_FakeAuth()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open forgot'));
    await tester.pumpAndSettle();
    expect(find.text('Forgot Password?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
