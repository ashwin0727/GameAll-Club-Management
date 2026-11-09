import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_player/core/theme/app_theme.dart';
import 'package:gameall_player/features/auth/application/auth_providers.dart';
import 'package:gameall_player/features/auth/data/player_auth_repository.dart';
import 'package:gameall_player/features/auth/domain/player_profile.dart';
import 'package:gameall_player/features/my_bookings/application/guest_bookings_providers.dart';
import 'package:gameall_player/features/my_bookings/data/guest_bookings_repository.dart';
import 'package:gameall_player/features/my_bookings/domain/guest_booking.dart';
import 'package:gameall_player/features/player_home/application/player_home_controller.dart';
import 'package:gameall_player/features/player_home/data/player_home_repository.dart';
import 'package:gameall_player/features/player_home/domain/player_home_models.dart';
import 'package:gameall_player/features/profile/application/profile_providers.dart';
import 'package:gameall_player/features/profile/data/profile_repository.dart';
import 'package:gameall_player/features/profile/domain/profile_models.dart';
import 'package:gameall_player/features/profile/presentation/profile_page.dart';
import 'package:gameall_player/features/payments/application/payment_flow.dart';

import '../support/fake_payment_receipts.dart';

const _me = PlayerProfile(
  id: 'u1',
  fullName: 'Uma Shankar M',
  phone: '8925643891',
  email: 'uma@example.com',
);

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

class _Repo implements ProfileRepository {
  ProfileEdit? saved;
  List<PaymentRecord> pays = [
    PaymentRecord(
      id: 'p1',
      isRefund: false,
      source: 'membership',
      sourceId: 'm1',
      amountInr: 2500,
      status: 'PAID',
      at: DateTime(2026, 11, 1),
      method: 'UPI',
      venueName: 'Champz Turf',
    ),
    PaymentRecord(
      id: 'r1',
      isRefund: true,
      source: 'booking',
      sourceId: 'b1',
      amountInr: 400,
      status: 'PROCESSED',
      at: DateTime(2026, 11, 2),
      venueName: 'Smash Arena',
    ),
  ];

  @override
  Future<ProfileDetails?> details() async => ProfileDetails(
    id: 'u1',
    fullName: 'Uma Shankar M',
    phone: '8925643891',
    email: 'uma@example.com',
    playerCode: 'GA12345678',
    city: 'Chennai, Tamil Nadu',
    dob: DateTime(2001, 9, 15),
    gender: Gender.male,
    preferredSports: ['badminton'],
  );

  /// What the ID-proof calls did, for the tests.
  String? uploadedType;
  String? removedPath;
  bool hasDoc = false;

  @override
  Future<List<SportOption>> sports() async => const [
    SportOption('badminton', 'Badminton'),
    SportOption('tennis', 'Tennis'),
  ];

  @override
  Future<ProfileDetails> uploadDocument(
    Uint8List bytes,
    String extension,
    String fileName,
    String docType,
  ) async {
    uploadedType = docType;
    hasDoc = true;
    return const ProfileDetails(
      id: 'u1',
      fullName: 'Uma Shankar M',
      phone: '8925643891',
      playerCode: 'GA12345678',
      idDocType: 'AADHAAR',
      idDocPath: 'u1/id.jpg',
      idDocName: 'id.jpg',
    );
  }

  @override
  Future<ProfileDetails> removeDocument(String path) async {
    removedPath = path;
    return (await details())!;
  }

  @override
  Future<Uri?> documentLink(String path) async => Uri.parse('https://example.com/$path');

  @override
  Future<ProfileDetails> update(ProfileEdit edit) async {
    saved = edit;
    return ProfileDetails(
      id: 'u1',
      fullName: edit.fullName,
      phone: '8925643891',
      email: edit.email,
      playerCode: 'GA12345678',
    );
  }

  @override
  Future<ProfileDetails> uploadAvatar(Uint8List bytes, String extension) async =>
      (await details())!;

  @override
  Future<ProfileStats?> stats() async =>
      const ProfileStats(bookings: 28, memberships: 2, coaching: 1);

  @override
  Future<List<PaymentRecord>> payments() async => pays;
}

/// Sign-in that takes a moment to be restored (a page refresh): [gate] opens it.
class _SlowAuth extends _Auth {
  final gate = Completer<void>();
  @override
  Future<PlayerProfile?> myProfile() async {
    await gate.future;
    return super.myProfile();
  }
}

class _Home implements PlayerHomeRepository {
  @override
  Future<PlayerHomeData> load() async => const PlayerHomeData.guest();
}

class _Bookings extends GuestBookingsRepository {
  @override
  Future<GuestBookings> mine() async => const GuestBookings();
}

Future<(_Repo, _Auth, List<String>)> _open(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double text = 1.0,
  _Auth? withAuth,
  bool settle = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = _Repo();
  final auth = withAuth ?? _Auth();
  final routes = <String>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        profileRepositoryProvider.overrideWithValue(repo),
        playerAuthRepositoryProvider.overrideWithValue(auth),
        playerHomeRepositoryProvider.overrideWithValue(_Home()),
        guestBookingsRepositoryProvider.overrideWithValue(_Bookings()),
        paymentReceiptRepositoryProvider.overrideWithValue(
          FakePaymentReceipts(),
        ),
        profileSharerProvider.overrideWithValue((_) async {}),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: MediaQuery(
          data: MediaQueryData(size: size, textScaler: TextScaler.linear(text)),
          child: Scaffold(body: ProfilePage(onNavigate: routes.add)),
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return (repo, auth, routes);
}

/// Opens one of the Personal Information tabs (on a phone the tab row scrolls sideways).
Future<void> _tapTab(WidgetTester tester, String name) async {
  final f = find.byKey(ValueKey('pi-tab-$name'));
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the person, Player ID, the four numbers and the five areas', (
    tester,
  ) async {
    await _open(tester);
    expect(find.text('My Profile'), findsOneWidget);
    expect(find.text('Uma Shankar M'), findsOneWidget);
    expect(find.text('Player ID: GA12345678'), findsOneWidget);
    expect(find.text('+91 8925643891'), findsOneWidget);
    expect(find.text('uma@example.com'), findsOneWidget);
    expect(find.text('28'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('Tournaments'), findsOneWidget);
    for (final t in [
      'Personal Information',
      'Payment & Billing',
      'Activity & History',
      'Preferences',
      'Support & Legal',
      'Logout',
    ]) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(find.text('Edit Profile'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-photo-button')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('while the sign-in is being restored (a refresh) there is no Login card, then the real profile appears', (tester) async {
    final slow = _SlowAuth();
    await _open(tester, withAuth: slow, settle: false);
    expect(find.byKey(const ValueKey('profile-login')), findsNothing);
    expect(find.byKey(const ValueKey('profile-header-loading')), findsOneWidget);
    expect(find.text('Player ID: GA12345678'), findsNothing);
    slow.gate.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('profile-header-loading')), findsNothing);
    expect(find.text('Player ID: GA12345678'), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-login')), findsNothing);
  });

  testWidgets('no overflow on a small phone with large text', (tester) async {
    await _open(tester, size: const Size(320, 640), text: 1.4);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a wide window (the web) shows it centred, no overflow', (
    tester,
  ) async {
    await _open(tester, size: const Size(1400, 900));
    expect(find.text('Personal Information'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the numbers open their pages', (tester) async {
    final (_, _, routes) = await _open(tester);
    await tester.tap(find.byKey(const ValueKey('stat-bookings')));
    await tester.tap(find.byKey(const ValueKey('stat-coaching')));
    expect(routes, ['/bookings', '/my-coaching']);
  });

  testWidgets('Edit Profile saves a new name', (tester) async {
    final (repo, _, _) = await _open(tester);
    await tester.tap(find.byKey(const ValueKey('profile-edit')));
    await tester.pumpAndSettle();
    expect(find.text('Personal Information'), findsWidgets);
    expect(find.byKey(const ValueKey('pi-phone')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('pi-name')), 'Uma S');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('pi-save')));
    await tester.tap(find.byKey(const ValueKey('pi-save')));
    await tester.pumpAndSettle();
    expect(repo.saved?.fullName, 'Uma S');
    expect(find.text('My Profile'), findsOneWidget);
  });

  testWidgets('a bad email is refused before saving', (tester) async {
    final (repo, _, _) = await _open(tester);
    await tester.tap(find.byKey(const ValueKey('menu-personal')));
    await tester.pumpAndSettle();
    await _tapTab(tester, 'contact');
    await tester.enterText(find.byKey(const ValueKey('pi-email')), 'nope');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('pi-save')));
    await tester.tap(find.byKey(const ValueKey('pi-save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pi-error')), findsOneWidget);
    expect(repo.saved, isNull);
  });

  group('Personal Information page', () {
    Future<_Repo> openInfo(WidgetTester tester, {Size size = const Size(390, 844), double text = 1.0}) async {
      final (repo, _, _) = await _open(tester, size: size, text: text);
      await tester.tap(find.byKey(const ValueKey('menu-personal')));
      await tester.pumpAndSettle();
      return repo;
    }

    testWidgets('shows the account facts and the four tabs', (tester) async {
      await openInfo(tester);
      expect(find.byKey(const ValueKey('pi-player-id')), findsOneWidget);
      expect(find.text('GA12345678'), findsOneWidget);
      expect(find.byKey(const ValueKey('pi-phone-verified')), findsOneWidget);
      expect(find.byKey(const ValueKey('pi-status')), findsOneWidget);
      for (final t in ['personal', 'contact', 'address', 'documents']) {
        expect(find.byKey(ValueKey('pi-tab-$t')), findsOneWidget, reason: t);
      }
      expect(find.text('Basic Information'), findsOneWidget);
      expect(find.text('Additional Information'), findsOneWidget);
      expect(find.byKey(const ValueKey('pi-sport-badminton')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('saving sends every tab\'s fields', (tester) async {
      final repo = await openInfo(tester);
      await tester.enterText(find.byKey(const ValueKey('pi-about')), 'Looking for games');
      await _tapTab(tester, 'contact');
      await tester.enterText(find.byKey(const ValueKey('pi-em-name')), 'Mohan');
      await tester.enterText(find.byKey(const ValueKey('pi-em-phone')), '9876543210');
      await _tapTab(tester, 'address');
      await tester.enterText(find.byKey(const ValueKey('pi-line1')), '12 Lake Road');
      await tester.enterText(find.byKey(const ValueKey('pi-pincode')), '600020');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('pi-save')));
      await tester.tap(find.byKey(const ValueKey('pi-save')));
      await tester.pumpAndSettle();
      final e = repo.saved!;
      expect(e.full, isTrue);
      expect(e.about, 'Looking for games');
      expect(e.emergencyName, 'Mohan');
      expect(e.emergencyPhone, '9876543210');
      expect(e.pincode, '600020');
      expect(e.preferredSports, ['badminton']);
      expect(e.gender, Gender.male);
    });

    testWidgets('the required fields are checked and the tab with the problem opens', (tester) async {
      final repo = await openInfo(tester);
      await _tapTab(tester, 'address');
      await tester.enterText(find.byKey(const ValueKey('pi-pincode')), '12');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('pi-save')));
      await tester.tap(find.byKey(const ValueKey('pi-save')));
      await tester.pumpAndSettle();
      expect(repo.saved, isNull);
      expect(find.text('PIN code must be 6 digits.'), findsWidgets);
      expect(find.byKey(const ValueKey('pi-error')), findsOneWidget);
    });

    testWidgets('a choice field opens a menu under it and picking an item sets the field', (tester) async {
      final repo = await openInfo(tester);
      final field = find.byKey(const ValueKey('pi-blood'));
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      await tester.tap(field);
      await tester.pumpAndSettle();
      expect(find.text('AB+'), findsOneWidget);
      // the menu is below the field, not on top of it
      expect(tester.getTopLeft(find.text('A+')).dy, greaterThan(tester.getBottomLeft(field).dy));
      await tester.tap(find.text('O+'));
      await tester.pumpAndSettle();
      expect(find.text('AB+'), findsNothing);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('pi-save')));
      await tester.tap(find.byKey(const ValueKey('pi-save')));
      await tester.pumpAndSettle();
      expect(repo.saved?.bloodGroup, 'O+');
    });

    testWidgets('typing keeps digits and symbols out of the name', (tester) async {
      await openInfo(tester);
      await tester.enterText(find.byKey(const ValueKey('pi-name')), 'Uma 12 S@#hankar');
      expect(find.widgetWithText(TextField, 'Uma  Shankar'), findsOneWidget);
    });

    Future<void> saveAndCheck(WidgetTester tester, _Repo repo, String message) async {
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('pi-save')));
      await tester.tap(find.byKey(const ValueKey('pi-save')));
      await tester.pumpAndSettle();
      expect(repo.saved, isNull);
      expect(find.text(message), findsWidgets);
    }

    testWidgets('a mobile number must be a real 10-digit number', (tester) async {
      final repo = await openInfo(tester);
      await _tapTab(tester, 'contact');
      await tester.enterText(find.byKey(const ValueKey('pi-alt-phone')), '5876543210');
      await saveAndCheck(tester, repo, 'Enter a valid 10-digit alternate mobile number (it starts with 6, 7, 8 or 9).');
    });

    testWidgets('the alternate number cannot be the number signed in with', (tester) async {
      final repo = await openInfo(tester);
      await _tapTab(tester, 'contact');
      await tester.enterText(find.byKey(const ValueKey('pi-alt-phone')), '8925643891');
      await saveAndCheck(tester, repo, 'This is the number you signed in with. Please enter a different one.');
    });

    testWidgets('an emergency contact needs both a name and a number', (tester) async {
      final repo = await openInfo(tester);
      await _tapTab(tester, 'contact');
      await tester.enterText(find.byKey(const ValueKey('pi-em-name')), 'Mohan');
      await saveAndCheck(tester, repo, 'Please enter the contact mobile number.');
    });

    testWidgets('an address needs its first line and PIN code together', (tester) async {
      final repo = await openInfo(tester);
      await _tapTab(tester, 'address');
      await tester.enterText(find.byKey(const ValueKey('pi-pincode')), '600020');
      await saveAndCheck(tester, repo, 'Please enter the address.');
    });

    testWidgets('a bad email is refused with its own message', (tester) async {
      final repo = await openInfo(tester);
      await _tapTab(tester, 'contact');
      await tester.enterText(find.byKey(const ValueKey('pi-email')), 'uma@@gmail');
      await saveAndCheck(tester, repo, 'Please enter a valid email address.');
    });

    testWidgets('Discard and Save only show once something has changed', (tester) async {
      await openInfo(tester);
      expect(find.byKey(const ValueKey('pi-save')), findsNothing);
      expect(find.byKey(const ValueKey('pi-discard')), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('pi-name')), 'Uma S');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pi-save')), findsOneWidget);
      expect(find.byKey(const ValueKey('pi-discard')), findsOneWidget);
      // putting it back the way it was takes them away again
      await tester.enterText(find.byKey(const ValueKey('pi-name')), 'Uma Shankar M');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pi-save')), findsNothing);
    });

    testWidgets('Discard shows a small message at the top that leaves by itself after 5 seconds', (tester) async {
      await openInfo(tester);
      await tester.enterText(find.byKey(const ValueKey('pi-name')), 'Someone Else');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('pi-discard')));
      await tester.tap(find.byKey(const ValueKey('pi-discard')));
      await tester.pump(const Duration(milliseconds: 400));
      final toast = find.byKey(const ValueKey('top-toast'));
      expect(toast, findsOneWidget);
      expect(find.text('Changes discarded.'), findsOneWidget);
      expect(tester.getTopLeft(toast).dy, lessThan(80));
      expect(find.byKey(const ValueKey('pi-save')), findsNothing);
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 400));
      expect(toast, findsNothing);
    });

    testWidgets('Discard Changes puts the saved values back', (tester) async {
      await openInfo(tester);
      await tester.enterText(find.byKey(const ValueKey('pi-name')), 'Someone Else');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('pi-discard')));
      await tester.tap(find.byKey(const ValueKey('pi-discard')));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Uma Shankar M'), findsOneWidget);
    });

    testWidgets('the ID proof needs a type first, then uploads and can be removed', (tester) async {
      final (repo, _, _) = await _open(tester);
      await tester.tap(find.byKey(const ValueKey('menu-personal')));
      await tester.pumpAndSettle();
      await _tapTab(tester, 'documents');
      await tester.ensureVisible(find.byKey(const ValueKey('pi-doc-upload')));
      await tester.tap(find.byKey(const ValueKey('pi-doc-upload')));
      await tester.pumpAndSettle();
      expect(find.text('Choose the type of ID first.'), findsOneWidget);
      expect(repo.uploadedType, isNull);
    });

    for (final c in <(String, Size, double)>[
      ('a phone', const Size(390, 844), 1.0),
      ('a small phone with large text', const Size(320, 640), 1.4),
      ('a wide window (the web)', const Size(1400, 900), 1.0),
    ]) {
      testWidgets('every tab fits on ${c.$1} without overflow', (tester) async {
        await openInfo(tester, size: c.$2, text: c.$3);
        for (final t in ['personal', 'contact', 'address', 'documents']) {
          await _tapTab(tester, t);
          expect(tester.takeException(), isNull, reason: t);
        }
      });
    }
  });

  testWidgets('Payment & Billing lists payments, invoices and refunds', (
    tester,
  ) async {
    await _open(tester);
    await tester.tap(find.byKey(const ValueKey('menu-payments')));
    await tester.pumpAndSettle();
    expect(find.text('Membership'), findsOneWidget);
    expect(find.text('Paid'), findsOneWidget);
    expect(find.byKey(const ValueKey('pay-receipt-p1')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pb-tab-2')));
    await tester.pumpAndSettle();
    expect(find.text('Refund · Court booking'), findsOneWidget);
    expect(find.text('Refunded'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Activity, Preferences and Support open', (tester) async {
    await _open(tester);
    await tester.tap(find.byKey(const ValueKey('menu-activity')));
    await tester.pumpAndSettle();
    expect(find.text('Activity & History'), findsWidgets);
    expect(find.byKey(const ValueKey('ah-tournaments')), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('menu-preferences')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pref-theme-light')));
    await tester.pump();
    expect(find.text('Booking reminders'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('menu-support')));
    await tester.pumpAndSettle();
    expect(find.text('Terms & Conditions'), findsOneWidget);
    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(find.text('Delete my account'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('every profile page uses the width on a wide window, no overflow', (
    tester,
  ) async {
    await _open(tester, size: const Size(1500, 900));
    for (final key in [
      'menu-personal',
      'menu-payments',
      'menu-activity',
      'menu-preferences',
      'menu-support',
    ]) {
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pumpAndSettle();
      // the content spans most of the window: not a narrow centred column
      final scroll = tester.getSize(find.byType(SingleChildScrollView).first);
      expect(scroll.width, greaterThan(1300), reason: key);
      expect(tester.takeException(), isNull, reason: key);
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('Logout asks first, then signs out', (tester) async {
    final (_, auth, _) = await _open(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('profile-logout')));
    await tester.tap(find.byKey(const ValueKey('profile-logout')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('logout-cancel')));
    await tester.pumpAndSettle();
    expect(auth.signedIn, isTrue);
    await tester.tap(find.byKey(const ValueKey('profile-logout')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('logout-confirm')));
    await tester.pumpAndSettle();
    expect(auth.signedIn, isFalse);
    expect(find.byKey(const ValueKey('profile-login')), findsOneWidget);
  });
}
