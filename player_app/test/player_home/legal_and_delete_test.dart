import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_player/core/theme/app_theme.dart';
import 'package:gameall_player/core/utils/external_links.dart';
import 'package:gameall_player/core/utils/legal_links.dart';
import 'package:gameall_player/features/auth/application/auth_providers.dart';
import 'package:gameall_player/features/auth/data/player_auth_repository.dart';
import 'package:gameall_player/features/auth/domain/player_profile.dart';
import 'package:gameall_player/features/auth/presentation/login_flow.dart';
import 'package:gameall_player/features/profile/data/account_repository.dart';
import 'package:gameall_player/features/profile/presentation/preferences_page.dart';

const _me = PlayerProfile(id: 'u1', fullName: 'Uma', phone: '8925643891');

class _Auth implements PlayerAuthRepository {
  bool signedIn = true;
  final _c = StreamController<void>.broadcast();
  @override
  bool get isConfigured => true;
  @override
  bool get isSignedIn => signedIn;
  @override
  Stream<void> get changes => _c.stream;
  @override
  Future<LoginStart> beginLogin(String phone) async =>
      const LoginStart(LoginNext.enterCode);
  @override
  Future<void> sendCode(String phone) async {}
  @override
  Future<void> verifyCode(String phone, String code) async {}
  @override
  Future<PlayerProfile?> myProfile() async => signedIn ? _me : null;
  @override
  Future<PlayerProfile> register({
    required String fullName,
    required String email,
  }) async => _me;
  @override
  Future<void> signOut() async {
    signedIn = false;
  }
}

class _Accounts implements AccountRepository {
  _Accounts({this.result = const AccountDeleted(), this.error});
  final AccountDeletion result;
  final String? error;
  int calls = 0;
  @override
  Future<AccountDeletion> deleteMyAccount() async {
    calls++;
    if (error != null) throw AccountDeletionException(error!);
    return result;
  }
}

class _Harness {
  final opened = <Uri>[];
  final auth = _Auth();
}

Future<_Harness> _pump(
  WidgetTester tester,
  Widget home, {
  AccountRepository? accounts,
}) async {
  tester.view.physicalSize = const Size(1000, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final h = _Harness();
  final c = ProviderContainer(
    overrides: [
      linkOpenerProvider.overrideWithValue((u) async {
        h.opened.add(u);
        return true;
      }),
      playerAuthRepositoryProvider.overrideWithValue(h.auth),
      if (accounts != null) accountRepositoryProvider.overrideWithValue(accounts),
    ],
  );
  addTearDown(c.dispose);
  await c.read(authControllerProvider.future);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(theme: AppTheme.dark(), home: home),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async => tester.pumpWidget(const SizedBox()));
  return h;
}

void main() {
  test('the legal pages are on the one website both apps share', () {
    expect(legalUri(LegalPage.privacy).toString(), endsWith('/privacy'));
    expect(legalUri(LegalPage.terms).toString(), endsWith('/terms'));
    expect(legalUri(LegalPage.refunds).toString(), endsWith('/refund-policy'));
    expect(
      legalUri(LegalPage.deleteAccount).toString(),
      endsWith('/delete-account'),
    );
    expect(legalUri(LegalPage.terms).scheme, 'https');
  });

  group('Support & Legal', () {
    testWidgets('Terms, Privacy and Refund policy each open their page', (
      tester,
    ) async {
      final h = await _pump(
        tester,
        SupportLegalPage(onNavigate: (_) {}),
      );
      for (final (key, page) in [
        ('sl-terms', LegalPage.terms),
        ('sl-privacy', LegalPage.privacy),
        ('sl-refunds', LegalPage.refunds),
      ]) {
        await tester.ensureVisible(find.byKey(ValueKey(key)));
        await tester.tap(find.byKey(ValueKey(key)));
        await tester.pump();
        expect(h.opened.last, legalUri(page), reason: key);
      }
    });

    testWidgets(
      'Delete my account asks first, needs DELETE typed, then deletes and signs out',
      (tester) async {
        final accounts = _Accounts();
        final h = await _pump(
          tester,
          SupportLegalPage(onNavigate: (_) {}),
          accounts: accounts,
        );
        await tester.ensureVisible(find.byKey(const ValueKey('sl-delete')));
        await tester.tap(find.byKey(const ValueKey('sl-delete')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('delete-dialog')), findsOneWidget);

        // nothing happens until the word is typed
        TextButton confirm() => tester.widget<TextButton>(
          find.byKey(const ValueKey('delete-confirm')),
        );
        expect(confirm().onPressed, isNull);
        await tester.enterText(
          find.byKey(const ValueKey('delete-confirm-field')),
          'delete me',
        );
        await tester.pump();
        expect(confirm().onPressed, isNull);
        expect(accounts.calls, 0);

        await tester.enterText(
          find.byKey(const ValueKey('delete-confirm-field')),
          'DELETE',
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('delete-confirm')));
        await tester.pumpAndSettle();
        expect(accounts.calls, 1);
        expect(h.auth.signedIn, isFalse, reason: 'signed out afterwards');
      },
    );

    testWidgets('Cancel leaves the account alone', (tester) async {
      final accounts = _Accounts();
      final h = await _pump(
        tester,
        SupportLegalPage(onNavigate: (_) {}),
        accounts: accounts,
      );
      await tester.ensureVisible(find.byKey(const ValueKey('sl-delete')));
      await tester.tap(find.byKey(const ValueKey('sl-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('delete-cancel')));
      await tester.pumpAndSettle();
      expect(accounts.calls, 0);
      expect(h.auth.signedIn, isTrue);
    });

    testWidgets('a failure is shown in the dialog and the player stays signed in', (
      tester,
    ) async {
      final accounts = _Accounts(error: 'Try again in a minute.');
      final h = await _pump(
        tester,
        SupportLegalPage(onNavigate: (_) {}),
        accounts: accounts,
      );
      await tester.ensureVisible(find.byKey(const ValueKey('sl-delete')));
      await tester.tap(find.byKey(const ValueKey('sl-delete')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('delete-confirm-field')),
        'DELETE',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('delete-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('Try again in a minute.'), findsOneWidget);
      expect(find.byKey(const ValueKey('delete-dialog')), findsOneWidget);
      expect(h.auth.signedIn, isTrue);
    });

    testWidgets(
      'a closed (not yet deleted) account says so, then still signs the phone out',
      (tester) async {
        final h = await _pump(
          tester,
          SupportLegalPage(onNavigate: (_) {}),
          accounts: _Accounts(result: const AccountClosedForNow()),
        );
        await tester.ensureVisible(find.byKey(const ValueKey('sl-delete')));
        await tester.tap(find.byKey(const ValueKey('sl-delete')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('delete-confirm-field')),
          'DELETE',
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('delete-confirm')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('delete-closed')), findsOneWidget);
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        expect(h.auth.signedIn, isFalse);
      },
    );
  });

  testWidgets('the sign-in screen links Terms and Privacy to the real pages', (
    tester,
  ) async {
    final h = await _pump(tester, const Scaffold(body: LoginFlow()));
    Future<void> tapSpan(String text) async {
      final rich = tester
          .widgetList<RichText>(find.byType(RichText))
          .firstWhere((r) => r.text.toPlainText().contains(text));
      final root = rich.text as TextSpan;
      TextSpan? found;
      root.visitChildren((s) {
        if (s is TextSpan && s.text == text) found = s;
        return true;
      });
      expect(found, isNotNull, reason: '"$text" is in the sign-in text');
      expect(found!.recognizer, isNotNull, reason: '"$text" is tappable');
      (found!.recognizer! as dynamic).onTap();
      await tester.pump();
    }

    await tapSpan('Terms & Conditions');
    expect(h.opened.last, legalUri(LegalPage.terms));
    await tapSpan('Privacy Policy.');
    expect(h.opened.last, legalUri(LegalPage.privacy));
  });
}
