import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gameall_club_mobile/core/routing/app_routes.dart';
import 'package:gameall_club_mobile/data/repositories/repository_providers.dart';
import 'package:gameall_club_mobile/data/repositories/staff_repository.dart';
import 'package:gameall_club_mobile/data/services/supabase_provider.dart';
import 'package:gameall_club_mobile/features/authentication/session_controller.dart';
import 'package:gameall_club_mobile/features/staff/set_password_screen.dart';

final _calls = <String>[];

class _FakeAuthClient extends Fake implements GoTrueClient {
  Object? failWith;

  @override
  Future<UserResponse> updateUser(UserAttributes attributes, {String? emailRedirectTo, String? nonce}) async {
    _calls.add('updateUser ${attributes.password}');
    final f = failWith;
    if (f != null) throw f;
    return UserResponse.fromJson({'id': 'u1', 'aud': 'authenticated', 'created_at': '2024-01-01T00:00:00Z', 'app_metadata': <String, dynamic>{}, 'user_metadata': <String, dynamic>{}});
  }
}

class _FakeClient extends Fake implements SupabaseClient {
  _FakeClient(this._auth);
  final _FakeAuthClient _auth;

  @override
  GoTrueClient get auth => _auth;
}

class _FakeStaff extends Fake implements StaffRepository {
  @override
  Future<void> markPasswordResetComplete() async => _calls.add('markComplete');
}

class _FakeSession extends SessionController {
  @override
  SessionState build() => const SessionState(isLoading: false);

  @override
  Future<void> refresh() async => _calls.add('refresh');

  @override
  Future<void> signOut() async => _calls.add('signOut');
}

Future<_FakeAuthClient> _open(WidgetTester tester) async {
  _calls.clear();
  tester.view.physicalSize = const Size(780, 1688); // 390 x 844 dp
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final auth = _FakeAuthClient();
  final router = GoRouter(
    initialLocation: AppRoutes.setPassword,
    routes: [
      GoRoute(path: AppRoutes.setPassword, builder: (_, _) => const SetPasswordScreen()),
      GoRoute(path: AppRoutes.signIn, builder: (_, _) => const Scaffold(body: Text('sign-in page'))),
    ],
  );
  await tester.pumpWidget(ProviderScope(
    overrides: [
      supabaseClientProvider.overrideWithValue(_FakeClient(auth)),
      staffRepositoryProvider.overrideWithValue(_FakeStaff()),
      sessionControllerProvider.overrideWith(_FakeSession.new),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return auth;
}

/// Scrolls to the button first: the wide test font makes the page taller than the screen.
Future<void> _tapText(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
}

Finder _newPw() => find.byKey(const ValueKey('reset-new-password'));
Finder _confirmPw() => find.byKey(const ValueKey('reset-confirm-password'));

void main() {
  testWidgets('shows the design: logo, heading, both fields, requirements, Reset Password with an arrow, Back to Login and the picture', (tester) async {
    await _open(tester);
    expect(find.text('Reset Password'), findsNWidgets(2)); // heading + button label
    expect(find.text('Create a new password for your account.'), findsOneWidget);
    expect(find.text('New Password'), findsOneWidget);
    expect(find.text('Confirm New Password'), findsOneWidget);
    expect(find.text('Password Requirements'), findsOneWidget);
    for (final rule in ['At least 8 characters', 'One uppercase letter (A–Z)', 'One number (0–9)', 'One special character (!@#\$%^)']) {
      expect(find.text(rule), findsOneWidget, reason: rule);
    }
    expect(find.byIcon(Icons.arrow_forward_rounded), findsOneWidget);
    expect(find.text('Back to Login'), findsOneWidget);
    expect(find.bySemanticsLabel('A padlock with a refresh badge'), findsOneWidget);
    expect(find.byType(Image), findsWidgets);
  });

  testWidgets('has no back button, and the system back does not leave the page', (tester) async {
    await _open(tester);
    expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);
    expect(find.byIcon(Icons.arrow_back), findsNothing);
    expect(find.byType(BackButton), findsNothing);
    expect(find.byTooltip('Back'), findsNothing);

    await tester.binding.handlePopRoute(); // the phone's own back
    await tester.pumpAndSettle();
    expect(find.text('Create a new password for your account.'), findsOneWidget);
  });

  testWidgets('the requirements tick as the password meets them', (tester) async {
    await _open(tester);
    expect(find.byKey(const ValueKey('rule-met')), findsNothing);
    expect(find.byKey(const ValueKey('rule-open')), findsNWidgets(4));

    await tester.enterText(_newPw(), 'abcdefgh'); // length only
    await tester.pump();
    expect(find.byKey(const ValueKey('rule-met')), findsNWidgets(1));

    await tester.enterText(_newPw(), 'Abcdefg1'); // length, uppercase, number
    await tester.pump();
    expect(find.byKey(const ValueKey('rule-met')), findsNWidgets(3));

    await tester.enterText(_newPw(), 'Abcdef1!');
    await tester.pump();
    expect(find.byKey(const ValueKey('rule-met')), findsNWidgets(4));
    expect(find.byKey(const ValueKey('rule-open')), findsNothing);
  });

  testWidgets('the eye icons show and hide each password', (tester) async {
    await _open(tester);
    EditableText field(Finder f) => tester.widget<EditableText>(find.descendant(of: f, matching: find.byType(EditableText)));
    expect(field(_newPw()).obscureText, isTrue);
    await tester.tap(find.byTooltip('Show password').first);
    await tester.pump();
    expect(field(_newPw()).obscureText, isFalse);
    expect(field(_confirmPw()).obscureText, isTrue);
  });

  testWidgets('the process is unchanged: under 8 characters, or two different passwords, are refused', (tester) async {
    await _open(tester);
    await tester.enterText(_newPw(), 'Ab1!');
    await tester.enterText(_confirmPw(), 'Ab1!');
    await _tapText(tester, find.text('Reset Password').last);
    await tester.pump();
    expect(find.text('Use at least 8 characters.'), findsOneWidget);

    await tester.enterText(_newPw(), 'Abcdef1!');
    await tester.enterText(_confirmPw(), 'Abcdef1?');
    await _tapText(tester, find.text('Reset Password').last);
    await tester.pump();
    expect(find.text('Passwords do not match.'), findsOneWidget);
    expect(_calls, isEmpty);
  });

  testWidgets('the process is unchanged: a good password is saved, the reset flag cleared and the session refreshed', (tester) async {
    await _open(tester);
    await tester.enterText(_newPw(), 'Abcdef1!');
    await tester.enterText(_confirmPw(), 'Abcdef1!');
    await _tapText(tester, find.text('Reset Password').last);
    await tester.pumpAndSettle();
    expect(_calls, ['updateUser Abcdef1!', 'markComplete', 'refresh']);
  });

  testWidgets('a server error shows its message and nothing else runs', (tester) async {
    final auth = await _open(tester);
    auth.failWith = const AuthException('New password should be different from the old password.');
    await tester.enterText(_newPw(), 'Abcdef1!');
    await tester.enterText(_confirmPw(), 'Abcdef1!');
    await _tapText(tester, find.text('Reset Password').last);
    await tester.pumpAndSettle();
    expect(find.text('New password should be different from the old password.'), findsOneWidget);
    expect(_calls, ['updateUser Abcdef1!']);
  });

  testWidgets('Back to Login signs out and opens the login page', (tester) async {
    await _open(tester);
    await _tapText(tester, find.byKey(const ValueKey('reset-back-to-login')));
    await tester.pumpAndSettle();
    expect(_calls, ['signOut']);
    expect(find.text('sign-in page'), findsOneWidget);
  });

  testWidgets('does not overflow on a small phone at large text', (tester) async {
    _calls.clear();
    tester.view.physicalSize = const Size(640, 1136); // 320 x 568 dp
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        supabaseClientProvider.overrideWithValue(_FakeClient(_FakeAuthClient())),
        staffRepositoryProvider.overrideWithValue(_FakeStaff()),
        sessionControllerProvider.overrideWith(_FakeSession.new),
      ],
      child: const MediaQuery(
        data: MediaQueryData(size: Size(320, 568), textScaler: TextScaler.linear(1.5)),
        child: MaterialApp(home: SetPasswordScreen()),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Create a new password for your account.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
