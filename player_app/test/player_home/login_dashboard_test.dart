import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_player/core/theme/app_theme.dart';
import 'package:gameall_player/core/widgets/gameall_buttons.dart';
import 'package:gameall_player/features/auth/application/auth_providers.dart';
import 'package:gameall_player/features/auth/data/player_auth_repository.dart';
import 'package:gameall_player/features/auth/domain/player_profile.dart';
import 'package:gameall_player/features/player_home/application/player_home_controller.dart';
import 'package:gameall_player/features/player_home/data/player_home_repository.dart';
import 'package:gameall_player/features/player_home/domain/player_dashboard_models.dart';
import 'package:gameall_player/features/player_home/domain/player_home_models.dart';
import 'package:gameall_player/features/player_home/presentation/widgets/player_bottom_nav.dart';
import 'package:gameall_player/features/shell/player_shell.dart';

class FakeAuth implements PlayerAuthRepository {
  FakeAuth({this.signedIn = false, this.profile});

  bool signedIn;
  PlayerProfile? profile;
  final sent = <String>[];
  String? registeredName;
  String? registeredEmail;
  bool failSend = false;
  final _changes = StreamController<void>.broadcast();

  @override
  bool get isConfigured => true;
  @override
  bool get isSignedIn => signedIn;
  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<void> sendCode(String phone) async {
    if (failSend) throw const AuthFailure("We couldn't send the code right now. Please try again in a moment.");
    sent.add(phone);
  }

  @override
  Future<void> verifyCode(String phone, String code) async {
    if (code != '123456') throw const AuthFailure("That code isn't right, or it has expired. Check it or ask for a new one.");
    signedIn = true;
    _changes.add(null);
  }

  @override
  Future<PlayerProfile?> myProfile() async => profile;

  @override
  Future<PlayerProfile> register({required String fullName, required String email}) async {
    registeredName = fullName;
    registeredEmail = email;
    return profile = PlayerProfile(id: 'p1', fullName: fullName.trim(), phone: '9876543210', email: email);
  }

  @override
  Future<void> signOut() async {
    signedIn = false;
    profile = null;
    _changes.add(null);
  }
}

class FakeHome implements PlayerHomeRepository {
  FakeHome(this.data);
  PlayerHomeData data;
  @override
  Future<PlayerHomeData> load() async => data;
}

PlayerHomeData signedInData() => PlayerHomeData(
      fullName: 'Uma Shankar',
      phone: '9876543210',
      signedIn: true,
      unreadNotifications: 0,
      hasActiveMembership: true,
      hasActiveCoaching: true,
      hasBookingHistory: true,
      upcomingBookings: const [],
      memberships: const [
        ActiveMembership(id: 'm1', planName: 'Evening Play', venueName: 'PlayZone Arena', batchName: 'Evening Play', days: [1, 2, 3, 4, 5], startTime: '18:00', endTime: '19:00'),
        ActiveMembership(id: 'm2', planName: 'Weekend Pro', venueName: 'Ace Academy', days: [6, 0], startTime: '07:00', endTime: '08:00'),
        ActiveMembership(id: 'm3', planName: 'Morning Fit', venueName: 'Ace Academy'),
      ],
      coaching: [ActiveCoaching(id: 'c1', programName: 'Intermediate Batch', venueName: 'Ace Academy', nextSession: DateTime.now().add(const Duration(days: 1)), nextSessionEnd: DateTime.now().add(const Duration(days: 1, hours: 1)))],
      guestBookings: GuestBookingSummary(count: 2, nextStart: DateTime.now().add(const Duration(days: 2)), nextEnd: DateTime.now().add(const Duration(days: 2, hours: 1)), nextVenue: 'PlayZone Arena'),
      schedule: [
        ScheduleItem(kind: ScheduleKind.coaching, title: 'Intermediate Batch', venueName: 'Ace Academy', courtName: 'Court 2', startTime: DateTime.now().add(const Duration(hours: 3)), endTime: DateTime.now().add(const Duration(hours: 4))),
        ScheduleItem(kind: ScheduleKind.membership, title: 'Evening Play', venueName: 'PlayZone Arena', courtName: 'Court 1', startTime: DateTime.now().add(const Duration(days: 1)), endTime: DateTime.now().add(const Duration(days: 1, hours: 1))),
      ],
      courtsToday: [ScheduleItem(kind: ScheduleKind.coaching, title: 'Intermediate Batch', venueName: 'Ace Academy', courtName: 'Court 2', startTime: DateTime.now().add(const Duration(hours: 3)), endTime: DateTime.now().add(const Duration(hours: 4)))],
    );

Future<(FakeAuth, ProviderContainer)> pump(WidgetTester tester, {FakeAuth? auth, PlayerHomeData? home, Size size = const Size(1600, 900), PlayerTab tab = PlayerTab.home}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final a = auth ?? FakeAuth();
  final container = ProviderContainer(overrides: [playerAuthRepositoryProvider.overrideWithValue(a), playerHomeRepositoryProvider.overrideWithValue(FakeHome(home ?? const PlayerHomeData.guest()))]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp(theme: AppTheme.dark(), home: PlayerShell(initialTab: tab))));
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
  addTearDown(() async => tester.pumpWidget(const SizedBox()));
  return (a, container);
}

Future<void> openLogin(WidgetTester tester) async {
  await tester.tap(find.text('Login'));
  await tester.pumpAndSettle();
}

bool continueEnabled(WidgetTester tester) => tester.widget<GameAllButton>(find.byType(GameAllButton).last).onPressed != null;

/// A signed-in player's profile and Home that arrive late, like a reload on a slow connection.
class SlowAuth extends FakeAuth {
  SlowAuth() : super(signedIn: true);
  final profileGate = Completer<PlayerProfile?>();
  @override
  Future<PlayerProfile?> myProfile() => profileGate.future;
}

class SlowHome implements PlayerHomeRepository {
  final gate = Completer<PlayerHomeData>();
  @override
  Future<PlayerHomeData> load() => gate.future;
}

void main() {
  group('reloading while signed in', () {
    for (final size in [const Size(1600, 900), const Size(390, 844)]) {
      testWidgets('never shows the visitor page or Login first (${size.width.toInt()} wide)', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final auth = SlowAuth();
        final home = SlowHome();
        final container = ProviderContainer(overrides: [playerAuthRepositoryProvider.overrideWithValue(auth), playerHomeRepositoryProvider.overrideWithValue(home)]);
        addTearDown(container.dispose);
        await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp(theme: AppTheme.dark(), home: const PlayerShell())));

        void notVisitor() {
          expect(find.text('Your Game,'), findsNothing);
          expect(find.text('Login'), findsNothing);
          expect(find.text('Ready to play today?'), findsNothing);
          expect(find.byKey(const ValueKey('skeleton')), findsWidgets);
        }

        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          notVisitor();
        }
        // the profile arrives first: still waiting for the Home data
        auth.profile = const PlayerProfile(id: 'p1', fullName: 'Uma Shankar', phone: '9876543210');
        auth.profileGate.complete(auth.profile);
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          notVisitor();
        }
        home.gate.complete(signedInData());
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('skeleton')), findsNothing);
        expect(find.text('Your Schedule'), findsOneWidget);
        expect(find.text('Your Game,'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets('a signed-out visitor is not held up', (tester) async {
      await pump(tester);
      expect(find.text('Your Game,'), findsOneWidget);
      expect(find.byKey(const ValueKey('skeleton')), findsNothing);
    });
  });

  group('models', () {
    test('batch days read like a person would say them', () {
      expect(describeDays([1, 2, 3, 4, 5]), 'Mon - Fri');
      expect(describeDays([6, 0]), 'Sat & Sun');
      expect(describeDays([1, 3, 5]), 'Mon, Wed, Fri');
      expect(describeDays([0, 1, 2, 3, 4, 5, 6]), 'Every day');
      expect(describeDays([]), '');
      expect(clock12('18:00'), '6:00 PM');
      expect(clock12('07:30'), '7:30 AM');
      expect(clock12('00:05'), '12:05 AM');
    });

    test('a membership says when it runs, or just the club when it has no batch', () {
      expect(signedInData().memberships[0].when, 'Mon - Fri  ·  6:00 PM - 7:00 PM');
      expect(signedInData().memberships[2].when, 'Ace Academy');
      expect(signedInData().memberships[0].subtitle, 'Evening Play');
    });

    test('the dashboard answer is read in full, and a visitor is not signed in', () {
      final d = PlayerHomeData.fromJson({
        'fullName': 'Uma',
        'phone': '9876543210',
        'email': 'u@x.co',
        'unreadNotifications': 0,
        'hasActiveMembership': true,
        'hasActiveCoaching': false,
        'hasBookingHistory': true,
        'upcomingBookings': [],
        'memberships': [
          {'id': 'a', 'planName': 'Gold', 'venueName': 'V', 'batchName': 'B', 'daysOfWeek': [1, 2], 'startTime': '18:00', 'endTime': '19:00', 'courtName': 'Court 1'},
        ],
        'coaching': [],
        'guestBookings': {'count': 1, 'next': {'startTime': '2030-01-01T10:00:00Z', 'endTime': '2030-01-01T11:00:00Z', 'venueName': 'V', 'courtName': 'Court 1'}},
        'schedule': [
          {'kind': 'membership', 'title': 'B', 'venueName': 'V', 'courtName': 'Court 1', 'startTime': '2030-01-01T10:00:00Z', 'endTime': '2030-01-01T11:00:00Z', 'status': 'confirmed'},
        ],
        'courtsToday': [],
      });
      expect(d.signedIn, isTrue);
      expect(d.memberships.single.planName, 'Gold');
      expect(d.guestBookings.count, 1);
      expect(d.schedule.single.kind, ScheduleKind.membership);
      final visitor = PlayerHomeData.fromJson({'fullName': null, 'upcomingBookings': []});
      expect(visitor.signedIn, isFalse);
      expect(visitor.memberships, isEmpty);
    });

    test('phone and email checks', () {
      expect(isValidIndianMobile('9876543210'), isTrue);
      expect(isValidIndianMobile('1234567890'), isFalse);
      expect(isValidIndianMobile('98765'), isFalse);
      expect(isValidEmail('a@b.co'), isTrue);
      expect(isValidEmail('nope'), isFalse);
      expect(const PlayerProfile(id: 'x', fullName: 'Uma Shankar', phone: '1').initials, 'US');
    });
  });

  group('login', () {
    testWidgets('a new player: phone, code, then name and email, and the bar shows their name', (tester) async {
      final (auth, _) = await pump(tester);
      await openLogin(tester);
      expect(find.byKey(const ValueKey('login-dialog')), findsOneWidget);
      expect(find.text('Login / Signup to continue'), findsOneWidget);
      expect(find.text('Enter your phone number'), findsOneWidget);
      expect(find.text('+91'), findsOneWidget);
      expect(continueEnabled(tester), isFalse);

      await tester.enterText(find.byKey(const ValueKey('login-phone')), '1234567890');
      await tester.pump();
      expect(continueEnabled(tester), isFalse, reason: 'an Indian mobile starts with 6 to 9');
      await tester.enterText(find.byKey(const ValueKey('login-phone')), '9876543210');
      await tester.pump();
      expect(continueEnabled(tester), isTrue);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(auth.sent, ['+919876543210']);
      expect(find.text('Enter the code'), findsOneWidget);
      expect(find.textContaining('+91 9876543210'), findsOneWidget);

      // a wrong code is explained, the right one moves on
      await tester.enterText(find.byKey(const ValueKey('login-code')), '000000');
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('login-error')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('login-code')), '123456');
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Tell us about you'), findsOneWidget);

      // name and a real email are both needed
      await tester.enterText(find.byKey(const ValueKey('login-name')), 'Uma Shankar');
      await tester.enterText(find.byKey(const ValueKey('login-email')), 'not-an-email');
      await tester.pump();
      expect(continueEnabled(tester), isFalse);
      await tester.enterText(find.byKey(const ValueKey('login-email')), 'uma@example.com');
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(auth.registeredName, 'Uma Shankar');
      expect(auth.registeredEmail, 'uma@example.com');
      expect(find.byKey(const ValueKey('login-dialog')), findsNothing);
      expect(find.byKey(const ValueKey('account-menu')), findsOneWidget);
      expect(find.text('Uma'), findsWidgets);
    });

    testWidgets('a returning player goes straight in after the code', (tester) async {
      final auth = FakeAuth(profile: const PlayerProfile(id: 'p1', fullName: 'Uma Shankar', phone: '9876543210', email: 'u@x.co'));
      await pump(tester, auth: auth);
      await openLogin(tester);
      await tester.enterText(find.byKey(const ValueKey('login-phone')), '9876543210');
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('login-code')), '123456');
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Tell us about you'), findsNothing);
      expect(find.byKey(const ValueKey('login-dialog')), findsNothing);
      expect(find.byKey(const ValueKey('account-menu')), findsOneWidget);
    });

    testWidgets('a failed text message is explained, and the number can be changed', (tester) async {
      final auth = FakeAuth()..failSend = true;
      await pump(tester, auth: auth);
      await openLogin(tester);
      await tester.enterText(find.byKey(const ValueKey('login-phone')), '9876543210');
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('login-error')), findsOneWidget);
      expect(find.text('Enter your phone number'), findsOneWidget);
    });

    testWidgets('the close button leaves without signing in', (tester) async {
      await pump(tester);
      await openLogin(tester);
      await tester.tap(find.byKey(const ValueKey('login-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('login-dialog')), findsNothing);
      expect(find.text('Login'), findsOneWidget);
    });

    testWidgets('on a phone the login is a full page, reached from Profile', (tester) async {
      await pump(tester, size: const Size(390, 844), tab: PlayerTab.profile);
      await tester.tap(find.byKey(const ValueKey('profile-login')));
      await tester.pumpAndSettle();
      expect(find.text('Enter your phone number'), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('logging out returns to the visitor Home', (tester) async {
      final auth = FakeAuth(signedIn: true, profile: const PlayerProfile(id: 'p1', fullName: 'Uma Shankar', phone: '9876543210', email: 'u@x.co'));
      await pump(tester, auth: auth, home: signedInData());
      expect(find.text('Welcome back,'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('account-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Log out'));
      await tester.pumpAndSettle();
      expect(auth.signedIn, isFalse);
      expect(find.text('Login'), findsOneWidget);
    });
  });

  group('signed-in Home', () {
    testWidgets('wide: welcome, summary cards, schedule, courts today, quick actions — every active membership and coaching listed', (tester) async {
      final auth = FakeAuth(signedIn: true, profile: const PlayerProfile(id: 'p1', fullName: 'Uma Shankar', phone: '9876543210', email: 'u@x.co'));
      await pump(tester, auth: auth, home: signedInData());
      expect(find.text('Welcome back,'), findsOneWidget);
      expect(find.text('Uma Shankar 👋'), findsOneWidget);
      expect(find.text('Your Game,'), findsNothing, reason: 'the visitor hero is not shown to a signed-in player');
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Enrolled'), findsOneWidget);
      expect(find.text('Guest Bookings'), findsOneWidget);
      // two memberships are listed, the third is counted
      expect(find.text('Mon - Fri  ·  6:00 PM - 7:00 PM'), findsOneWidget);
      expect(find.text('Weekend Pro'), findsOneWidget);
      expect(find.text('+1 more'), findsOneWidget);
      expect(find.text('Intermediate Batch'), findsWidgets);
      expect(find.text('Your Schedule'), findsOneWidget);
      expect(find.text('My Courts (Today)'), findsNothing);
      expect(find.text('Quick Actions'), findsOneWidget);
      for (final a in ['Book a Court', 'View Membership', 'My Coaching', 'Tournaments', 'My Activity']) {
        expect(find.text(a), findsWidgets);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('wide: a player with nothing yet sees invitations, not blanks', (tester) async {
      final auth = FakeAuth(signedIn: true, profile: const PlayerProfile(id: 'p1', fullName: 'Uma Shankar', phone: '9876543210'));
      await pump(
        tester,
        auth: auth,
        home: const PlayerHomeData(fullName: 'Uma Shankar', signedIn: true, unreadNotifications: 0, hasActiveMembership: false, hasActiveCoaching: false, hasBookingHistory: false, upcomingBookings: []),
      );
      expect(find.text('No active membership'), findsOneWidget);
      expect(find.text('No active coaching'), findsOneWidget);
      expect(find.text('No guest bookings'), findsOneWidget);
      expect(find.byKey(const ValueKey('schedule-empty')), findsOneWidget);
    });

    testWidgets('phone: the same information sits below Your Next Game, without overflow', (tester) async {
      final auth = FakeAuth(signedIn: true, profile: const PlayerProfile(id: 'p1', fullName: 'Uma Shankar', phone: '9876543210'));
      await pump(tester, auth: auth, home: signedInData(), size: const Size(390, 844));
      await tester.dragUntilVisible(find.text('Quick Actions'), find.byType(Scrollable).first, const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(find.text('Your Schedule'), findsOneWidget);
      expect(find.text('My Courts (Today)'), findsNothing);
      expect(find.text('Quick Actions'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('phone: a small screen with large text does not overflow', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.4;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final auth = FakeAuth(signedIn: true, profile: const PlayerProfile(id: 'p1', fullName: 'Uma Shankar', phone: '9876543210'));
      await pump(tester, auth: auth, home: signedInData(), size: const Size(320, 640));
      await tester.dragUntilVisible(find.text('Quick Actions'), find.byType(Scrollable).first, const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('a visitor still sees the visitor Home', (tester) async {
      await pump(tester);
      expect(find.text('Your Game,'), findsOneWidget);
      expect(find.text('Welcome back,'), findsNothing);
    });
  });
}
