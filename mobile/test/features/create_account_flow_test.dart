import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gameall_club_mobile/core/errors/app_exception.dart';
import 'package:gameall_club_mobile/core/routing/app_routes.dart';
import 'package:gameall_club_mobile/data/repositories/auth_repository.dart';
import 'package:gameall_club_mobile/data/repositories/repository_providers.dart';
import 'package:gameall_club_mobile/features/authentication/create_account_screen.dart';
import 'package:gameall_club_mobile/features/authentication/session_controller.dart';
import 'package:gameall_club_mobile/features/authentication/signup_draft.dart';
import 'package:gameall_club_mobile/features/authentication/verify_email_screen.dart';
import 'package:gameall_club_mobile/features/authentication/verify_phone_screen.dart';

class _FakeAuth extends Fake implements AuthRepository {
  final calls = <String>[];
  Object? failSend;
  Object? failRegister;

  @override
  Future<void> sendSignupPhoneCode(String phone) async {
    calls.add('sendPhone $phone');
    final f = failSend;
    if (f != null) throw f;
  }

  @override
  Future<String> verifySignupPhoneCode({required String phone, required String code}) async {
    calls.add('verifyPhone $phone $code');
    if (code == '000000') throw AppException(AppErrorCode.unauthorized, 'Incorrect code. 4 attempts left.');
    return 'proof-for-$phone';
  }

  @override
  Future<void> register({required String name, required String email, required String password, String? phone, String? mobileProof}) async {
    calls.add('register $name $email ${phone ?? '-'} ${mobileProof ?? '-'}');
    final f = failRegister;
    if (f != null) throw f;
  }

  @override
  Future<void> verifySignupCode({required String email, required String code}) async {
    calls.add('verifyEmail $code');
    if (code == '000000') throw AppException(AppErrorCode.unauthorized, 'That code is not right.');
  }

  @override
  Future<void> login({required String email, required String password}) async {
    calls.add('login');
  }

  @override
  Future<void> resendVerificationEmail(String email) async {
    calls.add('resendEmail');
  }
}

class _FakeSession extends SessionController {
  int refreshes = 0;

  @override
  SessionState build() => const SessionState(isLoading: false);

  @override
  Future<void> refresh() async {
    refreshes++;
  }
}

GoRouter _router({String initial = AppRoutes.createAccount}) => GoRouter(
      initialLocation: initial,
      routes: [
        GoRoute(path: AppRoutes.welcome, builder: (_, _) => const Scaffold(body: Text('welcome page'))),
        GoRoute(path: AppRoutes.signIn, builder: (_, _) => const Scaffold(body: Text('sign-in page'))),
        GoRoute(path: AppRoutes.createAccount, builder: (_, _) => const CreateAccountScreen()),
        GoRoute(path: AppRoutes.verifyPhone, builder: (_, state) => VerifyPhoneScreen(draft: state.extra! as SignupDraft)),
        GoRoute(path: AppRoutes.verifyEmail, builder: (_, state) => VerifyEmailScreen(draft: state.extra! as SignupDraft)),
      ],
    );

Widget _app(_FakeAuth auth, GoRouter router) => ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(auth), sessionControllerProvider.overrideWith(_FakeSession.new)],
      child: MaterialApp.router(routerConfig: router),
    );

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(780, 1688); // 390 x 844 dp
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
}

Finder _field(String label) => find.widgetWithText(TextFormField, label);
Finder _otp() => find.byKey(const ValueKey('otp-field'));

Future<void> _fillForm(WidgetTester tester, {String phone = '9876543210', String email = 'uma@example.com', String password = 'longenough1'}) async {
  await tester.enterText(_field('Full Name'), 'Uma Shankar');
  await tester.enterText(_field('Mobile Number'), phone);
  await tester.enterText(_field('Email Address'), email);
  await tester.enterText(_field('Password'), password);
  await tester.enterText(_field('Confirm Password'), password);
}

/// Steps the clock by hand: the verification pages run a countdown, and pumpAndSettle would run it to zero.
Future<void> _step(WidgetTester tester) => tester.pump(const Duration(milliseconds: 500));

Future<void> _submitForm(WidgetTester tester) async {
  await tester.dragUntilVisible(find.text('Create Account').last, find.byType(SingleChildScrollView).first, const Offset(0, -120));
  await tester.pump();
  await tester.tap(find.text('Create Account').last);
  await _step(tester);
  await _step(tester);
}

Future<void> _enterCode(WidgetTester tester, String code) async {
  await tester.enterText(_otp(), code);
  await tester.pump();
}

Future<void> _tapSubmit(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('otp-submit')));
  await _step(tester);
  await _step(tester);
}

void main() {
  group('Create Account page', () {
    testWidgets('has the fields (with the password twice), no Google button, and no alternative sign-up', (tester) async {
      await tester.pumpWidget(_app(_FakeAuth(), _router()));
      await tester.pumpAndSettle();
      expect(find.text('Create Your Account'), findsOneWidget);
      for (final label in ['Full Name', 'Mobile Number', 'Email Address', 'Password', 'Confirm Password']) {
        expect(_field(label), findsOneWidget, reason: label);
      }
      expect(find.textContaining('Google'), findsNothing);
      expect(find.textContaining('Sign up with Mobile'), findsNothing);
      expect(find.text('Log in'), findsOneWidget);
    });

    testWidgets('Log in is a real button with a tap area of at least 48 px, and it opens sign in', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_app(_FakeAuth(), _router()));
      await tester.pumpAndSettle();
      final button = find.widgetWithText(TextButton, 'Log in');
      expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('sign-in page'), findsOneWidget);
    });

    testWidgets('checks every field before it goes on', (tester) async {
      _phone(tester);
      final auth = _FakeAuth();
      await tester.pumpWidget(_app(auth, _router()));
      await tester.pumpAndSettle();
      await _submitForm(tester);
      expect(find.text('Name is required.'), findsOneWidget);
      expect(find.text('Phone number is required.'), findsOneWidget);
      expect(find.text('Verify Your Number'), findsNothing);

      await _fillForm(tester, phone: '1234567890'); // must start with 6-9
      await _submitForm(tester);
      expect(find.text('Mobile number must start with 6, 7, 8 or 9.'), findsOneWidget);
      expect(auth.calls, isEmpty);
    });

    testWidgets('stops when the two passwords are different', (tester) async {
      _phone(tester);
      final auth = _FakeAuth();
      await tester.pumpWidget(_app(auth, _router()));
      await tester.pumpAndSettle();
      await _fillForm(tester);
      await tester.enterText(_field('Confirm Password'), 'somethingelse');
      await _submitForm(tester);
      expect(find.text('Passwords do not match.'), findsOneWidget);
      expect(auth.calls, isEmpty);
    });

    testWidgets('goes to Verify Your Number first, without creating anything yet', (tester) async {
      _phone(tester);
      final auth = _FakeAuth();
      await tester.pumpWidget(_app(auth, _router()));
      await tester.pumpAndSettle();
      await _fillForm(tester);
      await _submitForm(tester);

      expect(find.text('Verify Your Number'), findsOneWidget);
      expect(find.text('+91 98765 43210'), findsOneWidget);
      // the OTP goes out as the page opens; no account has been created yet
      expect(auth.calls, ['sendPhone 9876543210']);
    });
  });

  group('Verify Your Number', () {
    Future<_FakeAuth> openPhone(WidgetTester tester) async {
      _phone(tester);
      final auth = _FakeAuth();
      await tester.pumpWidget(_app(auth, _router()));
      await tester.pumpAndSettle();
      await _fillForm(tester);
      await _submitForm(tester);
      return auth;
    }

    testWidgets('shows six boxes, the countdown, and a disabled button until all six digits are in', (tester) async {
      await openPhone(tester);
      expect(find.text('We’ve sent a 6-digit OTP to'), findsOneWidget);
      expect(find.textContaining('Resend OTP in ', findRichText: true), findsOneWidget);
      expect(find.textContaining('00:30', findRichText: true), findsOneWidget);
      expect(tester.widget<Opacity>(find.descendant(of: find.byKey(const ValueKey('otp-submit')), matching: find.byType(Opacity)).first).opacity, lessThan(1));

      await _enterCode(tester, '52849');
      expect(find.text('5'), findsOneWidget);
      await _enterCode(tester, '528490');
      for (final d in ['5', '2', '8', '4', '9', '0']) {
        expect(find.text(d), findsOneWidget, reason: 'box for $d');
      }
    });

    testWidgets('the countdown ticks down and then offers Resend OTP, which sends a fresh code', (tester) async {
      final auth = await openPhone(tester);
      await tester.pump(const Duration(seconds: 6));
      expect(find.textContaining('00:24', findRichText: true), findsOneWidget);

      await tester.pump(const Duration(seconds: 25));
      expect(find.byKey(const ValueKey('otp-resend')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('otp-resend')));
      await _step(tester);
      expect(auth.calls.where((c) => c.startsWith('sendPhone')).length, 2);
      expect(find.textContaining('00:30', findRichText: true), findsOneWidget);
      expect(find.text('A new OTP has been sent.'), findsOneWidget);
    });

    testWidgets('a wrong code shows the message and stays on the page', (tester) async {
      final auth = await openPhone(tester);
      await _enterCode(tester, '000000');
      await _tapSubmit(tester);
      expect(find.text('Incorrect code. 4 attempts left.'), findsOneWidget);
      expect(find.text('Verify Your Number'), findsOneWidget);
      expect(auth.calls.any((c) => c.startsWith('register')), isFalse);
    });

    testWidgets('the right code verifies the number, creates the account with the proof, and opens Verify Your Email', (tester) async {
      final auth = await openPhone(tester);
      await _enterCode(tester, '528490');
      await _tapSubmit(tester);

      expect(auth.calls, [
        'sendPhone 9876543210',
        'verifyPhone 9876543210 528490',
        'register Uma Shankar uma@example.com 9876543210 proof-for-9876543210',
      ]);
      expect(find.text('Verify Your Email'), findsOneWidget);
      expect(find.text('uma@example.com'), findsOneWidget);
    });

    testWidgets('Back returns to Create Your Account with everything still typed in, so it can be changed', (tester) async {
      await openPhone(tester);
      await tester.tap(find.byKey(const ValueKey('otp-back')));
      await _step(tester);
      await _step(tester);

      expect(find.text('Create Your Account'), findsOneWidget);
      expect(find.text('Uma Shankar'), findsOneWidget);
      expect(find.text('9876543210'), findsOneWidget);
      expect(find.text('uma@example.com'), findsOneWidget);
    });

    testWidgets('a changed number gets its own OTP', (tester) async {
      final auth = await openPhone(tester);
      await tester.tap(find.byKey(const ValueKey('otp-back')));
      await _step(tester);
      await _step(tester);

      await tester.enterText(_field('Mobile Number'), '9123456780');
      await _submitForm(tester);
      expect(find.text('+91 91234 56780'), findsOneWidget);
      expect(auth.calls, ['sendPhone 9876543210', 'sendPhone 9123456780']);
    });

    testWidgets('if the OTP cannot be sent, the message shows and Resend OTP is available at once', (tester) async {
      _phone(tester);
      final auth = _FakeAuth()..failSend = AppException(AppErrorCode.unauthorized, 'Could not place the call.');
      await tester.pumpWidget(_app(auth, _router()));
      await tester.pumpAndSettle();
      await _fillForm(tester);
      await _submitForm(tester);
      expect(find.text('Could not place the call.'), findsOneWidget);
      expect(find.byKey(const ValueKey('otp-resend')), findsOneWidget);
    });

    testWidgets('if the account cannot be created (email already used), the message shows, Back is open, and the number is not asked again', (tester) async {
      _phone(tester);
      final auth = _FakeAuth()..failRegister = AppException(AppErrorCode.unauthorized, 'An account already exists for this email address.');
      await tester.pumpWidget(_app(auth, _router()));
      await tester.pumpAndSettle();
      await _fillForm(tester);
      await _submitForm(tester);
      await _enterCode(tester, '528490');
      await _tapSubmit(tester);
      expect(find.text('An account already exists for this email address.'), findsOneWidget);
      expect(find.text('Verify Your Number'), findsOneWidget);

      // trying again does not need the code a second time: the number is already verified
      auth.failRegister = null;
      await _tapSubmit(tester);
      expect(auth.calls.where((c) => c.startsWith('verifyPhone')).length, 1);
      expect(find.text('Verify Your Email'), findsOneWidget);
    });

    testWidgets('does not overflow on a small phone at large text', (tester) async {
      tester.view.physicalSize = const Size(640, 1136); // 320 x 568 dp
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final draft = SignupDraft()
        ..name = 'Uma Shankar'
        ..phone = '9876543210'
        ..email = 'a.very.long.email.address@example-company.com'
        ..password = 'longenough1';
      final router = GoRouter(
        initialLocation: AppRoutes.verifyPhone,
        initialExtra: draft,
        routes: [
          GoRoute(path: AppRoutes.verifyPhone, builder: (_, state) => VerifyPhoneScreen(draft: state.extra! as SignupDraft)),
          GoRoute(path: AppRoutes.verifyEmail, builder: (_, state) => VerifyEmailScreen(draft: state.extra! as SignupDraft)),
        ],
      );
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(size: Size(320, 568), textScaler: TextScaler.linear(1.5)),
        child: _app(_FakeAuth(), router),
      ));
      await _step(tester);
      expect(find.text('Verify Your Number'), findsOneWidget);
      expect(tester.takeException(), isNull);

      router.go(AppRoutes.verifyEmail, extra: draft);
      await _step(tester);
      await _step(tester);
      expect(find.text('Verify Your Email'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Verify Your Email', () {
    Future<_FakeAuth> openEmail(WidgetTester tester) async {
      _phone(tester);
      final auth = _FakeAuth();
      await tester.pumpWidget(_app(auth, _router()));
      await tester.pumpAndSettle();
      await _fillForm(tester);
      await _submitForm(tester);
      await _enterCode(tester, '528490');
      await _tapSubmit(tester);
      return auth;
    }

    testWidgets('asks for the emailed code, with a resend countdown', (tester) async {
      await openEmail(tester);
      expect(find.text('Verify Your Email'), findsOneWidget);
      expect(find.text('We’ve sent a 6-digit code to'), findsOneWidget);
      expect(find.textContaining('Resend code in ', findRichText: true), findsOneWidget);
    });

    testWidgets('a wrong code shows the message', (tester) async {
      final auth = await openEmail(tester);
      await _enterCode(tester, '000000');
      await _tapSubmit(tester);
      expect(find.text('That code is not right.'), findsOneWidget);
      expect(auth.calls.contains('login'), isFalse);
    });

    testWidgets('the right code confirms the email, signs in and refreshes the session', (tester) async {
      final auth = await openEmail(tester);
      await _enterCode(tester, '123456');
      await tester.tap(find.byKey(const ValueKey('otp-submit')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(auth.calls.sublist(auth.calls.length - 2), ['verifyEmail 123456', 'login']);
    });

    testWidgets('Resend code works after the countdown', (tester) async {
      final auth = await openEmail(tester);
      await tester.pump(const Duration(seconds: 31));
      await tester.tap(find.byKey(const ValueKey('otp-resend')));
      await _step(tester);
      expect(auth.calls.last, 'resendEmail');
      expect(find.text('A new code has been sent to your email.'), findsOneWidget);
    });

    testWidgets('Back returns to Create Your Account, still filled in, to change the email', (tester) async {
      await openEmail(tester);
      await tester.tap(find.byKey(const ValueKey('otp-back')));
      await _step(tester);
      await _step(tester);
      expect(find.text('Create Your Account'), findsOneWidget);
      expect(find.text('uma@example.com'), findsOneWidget);
    });

    testWidgets('changing only the email skips the OTP: the number is still verified, so the account is created and the email step opens', (tester) async {
      final auth = await openEmail(tester);
      await tester.tap(find.byKey(const ValueKey('otp-back')));
      await _step(tester);
      await _step(tester);

      await tester.enterText(_field('Email Address'), 'new@example.com');
      await _submitForm(tester);

      expect(find.text('Verify Your Email'), findsOneWidget);
      expect(find.text('new@example.com'), findsOneWidget);
      // no second OTP for the number
      expect(auth.calls.where((c) => c.startsWith('sendPhone')).length, 1);
      expect(auth.calls.last, 'register Uma Shankar new@example.com 9876543210 proof-for-9876543210');
    });
  });
}
