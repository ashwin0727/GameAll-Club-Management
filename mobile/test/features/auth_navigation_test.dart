import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gameall_club_mobile/core/routing/app_routes.dart';
import 'package:gameall_club_mobile/core/routing/page_transitions.dart';
import 'package:gameall_club_mobile/data/repositories/auth_repository.dart';
import 'package:gameall_club_mobile/data/repositories/repository_providers.dart';
import 'package:gameall_club_mobile/features/authentication/create_account_screen.dart';
import 'package:gameall_club_mobile/features/authentication/session_controller.dart';
import 'package:gameall_club_mobile/features/authentication/sign_in_screen.dart';
import 'package:gameall_club_mobile/features/authentication/welcome_screen.dart';

class _FakeAuth extends Fake implements AuthRepository {}

class _FakeSession extends SessionController {
  @override
  SessionState build() => const SessionState(isLoading: false);

  @override
  Future<void> refresh() async {}
}

/// The real login and Create Account pages, wired with the app's own transitions.
GoRouter _router(String initial) => GoRouter(
      initialLocation: initial,
      routes: [
        GoRoute(path: AppRoutes.welcome, pageBuilder: (c, s) => fadeThroughCovered(s, const WelcomeScreen())),
        GoRoute(path: AppRoutes.signIn, pageBuilder: (c, s) => fadeThroughCovered(s, const SignInScreen())),
        GoRoute(path: AppRoutes.createAccount, pageBuilder: (c, s) => slideOver(s, const CreateAccountScreen())),
        GoRoute(path: AppRoutes.intro, pageBuilder: (c, s) => slideOver(s, const Scaffold(body: Text('intro page')))),
      ],
    );

Widget _app(GoRouter router) => ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(_FakeAuth()), sessionControllerProvider.overrideWith(_FakeSession.new)],
      child: MaterialApp.router(routerConfig: router),
    );

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(780, 1688); // 390 x 844 dp
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  group('Login <-> Create Account', () {
    testWidgets('Create Account then Log in returns to the same login page, with what was typed still there', (tester) async {
      _phone(tester);
      final router = _router(AppRoutes.signIn);
      await tester.pumpWidget(_app(router));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Email Address'), 'keep@me.com');

      await _tap(tester, find.widgetWithText(TextButton, 'Create Account'));
      expect(find.text('Create Your Account'), findsOneWidget);

      await _tap(tester, find.widgetWithText(TextButton, 'Log in'));
      expect(find.text('Welcome to GameAll'), findsOneWidget);
      expect(find.text('Create Your Account'), findsNothing);
      // The page that was underneath came back; no second login page was built.
      expect(find.text('keep@me.com'), findsOneWidget);
      expect(router.canPop(), isFalse);
    });

    testWidgets('it works round and round without piling up pages', (tester) async {
      _phone(tester);
      final router = _router(AppRoutes.signIn);
      await tester.pumpWidget(_app(router));
      await tester.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        await _tap(tester, find.widgetWithText(TextButton, 'Create Account'));
        expect(find.text('Create Your Account'), findsOneWidget);
        await _tap(tester, find.widgetWithText(TextButton, 'Log in'));
        expect(find.text('Welcome to GameAll'), findsOneWidget);
      }
      expect(router.canPop(), isFalse);
    });

    testWidgets('Log in from Create Account opens the login page when it was reached from the intro', (tester) async {
      _phone(tester);
      final router = _router(AppRoutes.welcome);
      await tester.pumpWidget(_app(router));
      await tester.pumpAndSettle();
      router.go(AppRoutes.createAccount); // as after the intro: no login page underneath
      await tester.pumpAndSettle();
      expect(find.text('Create Your Account'), findsOneWidget);

      await _tap(tester, find.widgetWithText(TextButton, 'Log in'));
      expect(find.text('Welcome to GameAll'), findsOneWidget);
    });

    testWidgets('mid-transition the login page underneath stays visible, it never goes see-through', (tester) async {
      _phone(tester);
      final router = _router(AppRoutes.signIn);
      await tester.pumpWidget(_app(router));
      await tester.pumpAndSettle();

      final link = find.widgetWithText(TextButton, 'Create Account');
      await tester.ensureVisible(link);
      await tester.pumpAndSettle();
      await tester.tap(link);
      await tester.pump(); // start the slide
      for (final ms in [60, 90, 90, 90]) {
        await tester.pump(Duration(milliseconds: ms));
        // The login page sits under a stack of FadeTransitions; their product is how visible it is right now.
        var visible = 1.0;
        tester.element(find.byType(SignInScreen, skipOffstage: false)).visitAncestorElements((e) {
          final w = e.widget;
          if (w is FadeTransition) visible *= w.opacity.value;
          return true;
        });
        expect(visible, greaterThan(0.75), reason: 'login page went see-through $ms ms into the slide');
      }
      await tester.pumpAndSettle();
    });
  });

  group('transition used by pages that others slide over', () {
    Widget build(Widget Function(BuildContext, Animation<double>, Animation<double>, Widget) builder, double secondary) {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(
          builder: (context) => builder(context, const AlwaysStoppedAnimation(1.0), AlwaysStoppedAnimation(secondary), const SizedBox(key: ValueKey('page'))),
        ),
      );
    }

    double visibility(WidgetTester tester) {
      var v = 1.0;
      tester.element(find.byKey(const ValueKey('page'))).visitAncestorElements((e) {
        final w = e.widget;
        if (w is FadeTransition) v *= w.opacity.value;
        return true;
      });
      return v;
    }

    testWidgets('the old fade-through fully hides a covered page (the glitch)', (tester) async {
      await tester.pumpWidget(build(appFadeThroughTransition, 1.0));
      expect(visibility(tester), closeTo(0, 0.01));
    });

    testWidgets('the covered-aware version keeps a covered page clearly visible', (tester) async {
      await tester.pumpWidget(build(appFadeCoveredTransition, 1.0));
      expect(visibility(tester), greaterThan(0.8));
    });

    testWidgets('and shows an uncovered page fully', (tester) async {
      await tester.pumpWidget(build(appFadeCoveredTransition, 0.0));
      expect(visibility(tester), closeTo(1.0, 0.01));
    });
  });
}
