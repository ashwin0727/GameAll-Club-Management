import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_player/core/routing/app_routes.dart';
import 'package:gameall_player/core/theme/app_theme.dart';
import 'package:gameall_player/core/widgets/pressable.dart';
import 'package:gameall_player/features/player_home/application/player_home_controller.dart';
import 'package:gameall_player/features/player_home/data/player_home_repository.dart';
import 'package:gameall_player/features/player_home/domain/player_home_models.dart';
import 'package:gameall_player/features/shell/player_shell.dart';

class FakeRepository implements PlayerHomeRepository {
  FakeRepository(this.data);
  PlayerHomeData data;
  int loads = 0;

  @override
  Future<PlayerHomeData> load() async {
    loads++;
    return data;
  }
}

PlayerHomeData playerData({
  bool membership = false,
  bool coaching = false,
  bool history = false,
  List<UpcomingBooking> bookings = const [],
  String name = 'Alex Kumar',
  int unread = 0,
}) =>
    PlayerHomeData(
      fullName: name,
      unreadNotifications: unread,
      hasActiveMembership: membership,
      hasActiveCoaching: coaching,
      hasBookingHistory: history,
      upcomingBookings: bookings,
    );

class Harness {
  Harness(this.routes, this.container);
  final List<String> routes;
  final ProviderContainer container;
}

/// Opens the Player shell at the given screen size, with a fake data source and a recorder for navigation.
Future<Harness> pumpHome(
  WidgetTester tester, {
  PlayerHomeData? data,
  Size size = const Size(390, 844),
  ThemeMode mode = ThemeMode.dark,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final routes = <String>[];
  final container = ProviderContainer(overrides: [playerHomeRepositoryProvider.overrideWithValue(FakeRepository(data ?? playerData()))]);
  addTearDown(container.dispose);
  container.read(themeModeProvider.notifier).set(mode);
  // A test may open the shell more than once: let the previous one finish unmounting (Riverpod schedules a zero-length dispose timer).
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 1));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: Consumer(
        builder: (context, ref, _) => MaterialApp(
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: ref.watch(themeModeProvider),
          home: PlayerShell(onNavigate: routes.add),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
  // Stop the carousel timer when the test ends.
  addTearDown(() async => tester.pumpWidget(const SizedBox()));
  return Harness(routes, container);
}

UpcomingBooking upcoming({String status = 'confirmed', Duration from = const Duration(days: 1), String sport = 'Badminton'}) {
  final start = DateTime.now().add(from);
  return UpcomingBooking(
    id: 'b-$status-${from.inMinutes}',
    venueName: 'PlayZone Sports Arena',
    sportName: sport,
    courtName: 'Court 2',
    startTime: start,
    endTime: start.add(const Duration(hours: 1)),
    status: status,
  );
}

void main() {
  group('Home page', () {
    testWidgets('loads and greets the player by first name', (tester) async {
      await pumpHome(tester);
      expect(find.text('Hi, Alex 👋'), findsOneWidget);
      expect(find.text('Ready to play today?'), findsOneWidget);
      expect(find.textContaining('Search venues'), findsOneWidget);
      expect(find.text('Your Next Game'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows a skeleton, not wrong data, until the data arrives', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = ProviderContainer(overrides: [playerHomeRepositoryProvider.overrideWithValue(_SlowRepository())]);
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(theme: AppTheme.dark(), home: PlayerShell(onNavigate: (_) {})),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const ValueKey('skeleton')), findsWidgets);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('skeleton')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('membership card follows the enrolment', (tester) async {
      final plain = await pumpHome(tester);
      expect(find.text('Explore\nMemberships'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('shortcut-membership')));
      expect(plain.routes, [AppRoutes.memberships]);

      final enrolled = await pumpHome(tester, data: playerData(membership: true));
      expect(find.text('My\nMembership'), findsOneWidget);
      expect(find.text('Explore\nMemberships'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('shortcut-membership')));
      expect(enrolled.routes, [AppRoutes.myMembership]);
    });

    testWidgets('coaching card follows the enrolment', (tester) async {
      final plain = await pumpHome(tester);
      expect(find.text('Explore\nCoaching'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('shortcut-coaching')));
      expect(plain.routes, [AppRoutes.coaching]);

      final enrolled = await pumpHome(tester, data: playerData(coaching: true));
      expect(find.text('My\nCoaching'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('shortcut-coaching')));
      expect(enrolled.routes, [AppRoutes.myCoaching]);
    });

    testWidgets('Guest Court Booking is always there', (tester) async {
      for (final data in [playerData(), playerData(membership: true, coaching: true), const PlayerHomeData.guest()]) {
        final h = await pumpHome(tester, data: data);
        expect(find.text('Guest\nCourt\nBooking'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('shortcut-guest')));
        expect(h.routes, [AppRoutes.guestBooking]);
      }
    });

    testWidgets('a brand-new player sees "No bookings yet" and a Book a Court button', (tester) async {
      final h = await pumpHome(tester);
      expect(find.text('No bookings yet.'), findsOneWidget);
      await tester.ensureVisible(find.text('Book a Court'));
      await tester.pump();
      await tester.tap(find.text('Book a Court'));
      expect(h.routes, [AppRoutes.guestBooking]);
    });

    testWidgets('a returning player with nothing coming up sees "Ready for your next game?"', (tester) async {
      await pumpHome(tester, data: playerData(history: true));
      expect(find.text('Ready for your next game?'), findsOneWidget);
      expect(find.text('No bookings yet.'), findsNothing);
    });

    testWidgets('shows the next confirmed booking', (tester) async {
      await pumpHome(tester, data: playerData(history: true, bookings: [upcoming(from: const Duration(days: 2)), upcoming(from: const Duration(hours: 6))]));
      expect(find.text('PlayZone Sports Arena'), findsOneWidget);
      expect(find.text('Confirmed'), findsOneWidget);
      expect(find.text('Badminton · Court 2'), findsOneWidget);
      expect(find.textContaining('View All'), findsOneWidget);
      expect(find.text('No bookings yet.'), findsNothing);
    });

    testWidgets('a cancelled booking is not shown as confirmed', (tester) async {
      await pumpHome(tester, data: playerData(history: true, bookings: [upcoming(status: 'cancelled')]));
      expect(find.text('Confirmed'), findsNothing);
      expect(find.text('Ready for your next game?'), findsOneWidget);
    });

    testWidgets('the unread count shows on the bell, and the bell opens notifications', (tester) async {
      final h = await pumpHome(tester, data: playerData(unread: 4));
      expect(find.bySemanticsLabel('Notifications, 4 unread'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Notifications, 4 unread'));
      expect(h.routes, [AppRoutes.notifications]);
    });

    testWidgets('the search bar opens search', (tester) async {
      final h = await pumpHome(tester);
      await tester.tap(find.textContaining('Search venues'));
      expect(h.routes, [AppRoutes.search]);
    });

    testWidgets('the location pin opens the city picker and the choice sticks', (tester) async {
      final h = await pumpHome(tester);
      expect(h.container.read(selectedCityProvider), 'Bangalore, Karnataka');
      await tester.tap(find.byIcon(Icons.location_on_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Choose your city'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('city-Chennai, Tamil Nadu')));
      await tester.pumpAndSettle();
      expect(find.text('Choose your city'), findsNothing);
      expect(h.container.read(selectedCityProvider), 'Chennai, Tamil Nadu');
    });

    testWidgets('choosing a sport selects it', (tester) async {
      final h = await pumpHome(tester);
      expect(h.container.read(selectedSportProvider), 'all');
      await tester.tap(find.byKey(const ValueKey('sport-football')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(h.container.read(selectedSportProvider), 'football');
    });

    testWidgets('the selected sport narrows "Your Next Game"', (tester) async {
      final h = await pumpHome(tester, data: playerData(history: true, bookings: [upcoming(sport: 'Badminton')]));
      expect(find.text('Confirmed'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('sport-football')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Confirmed'), findsNothing);
      expect(find.text('Ready for your next game?'), findsOneWidget);
      h.container.read(selectedSportProvider.notifier).select('all');
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Confirmed'), findsOneWidget);
    });
  });

  group('Promotional carousel', () {
    testWidgets('starts on the first slide, with the dots inside the card', (tester) async {
      await pumpHome(tester);
      expect(find.text('Find your game,'), findsOneWidget);
      expect(find.text('Book your court.'), findsOneWidget);
      expect(find.text('Explore Courts'), findsOneWidget);
      expect(find.byKey(const ValueKey('promo-dot-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('promo-dot-2')), findsOneWidget);
    });

    testWidgets('turns by itself every 5 seconds', (tester) async {
      await pumpHome(tester);
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 450));
      expect(find.text('Play regularly.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 450));
      expect(find.text('Take your game'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 450));
      expect(find.text('Find your game,'), findsOneWidget);
    });

    testWidgets('can be swiped by hand, both ways', (tester) async {
      await pumpHome(tester);
      await tester.fling(find.byKey(const ValueKey('promo-pages')), const Offset(-300, 0), 1200);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Play regularly.'), findsOneWidget);
      await tester.fling(find.byKey(const ValueKey('promo-pages')), const Offset(300, 0), 1200);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Find your game,'), findsOneWidget);
    });

    testWidgets('does not turn while a finger is on it, and carries on afterwards', (tester) async {
      await pumpHome(tester);
      final gesture = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('promo-pages'))));
      await tester.pump(const Duration(seconds: 12));
      expect(find.text('Find your game,'), findsOneWidget);
      await gesture.up();
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 450));
      expect(find.text('Play regularly.'), findsOneWidget);
    });

    testWidgets('only the button navigates; the timer never does', (tester) async {
      final h = await pumpHome(tester);
      await tester.pump(const Duration(seconds: 15));
      await tester.pump(const Duration(milliseconds: 450));
      expect(h.routes, isEmpty);
    });

    testWidgets('each slide button opens its own page', (tester) async {
      final h = await pumpHome(tester);
      await tester.tap(find.text('Explore Courts'));
      expect(h.routes.last, AppRoutes.guestBooking);

      await tester.fling(find.byKey(const ValueKey('promo-pages')), const Offset(-300, 0), 1200);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      await tester.tap(find.text('Explore Memberships').last);
      expect(h.routes.last, AppRoutes.memberships);

      await tester.fling(find.byKey(const ValueKey('promo-pages')), const Offset(-300, 0), 1200);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      await tester.tap(find.text('Find a Coach'));
      expect(h.routes.last, AppRoutes.coaching);
    });
  });

  group('Navigation', () {
    testWidgets('five destinations; Home, Bookings, Explore and Profile switch tabs', (tester) async {
      await pumpHome(tester);
      for (final label in ['Home', 'Bookings', 'Quick', 'Explore', 'Profile']) {
        expect(find.text(label), findsWidgets);
      }
      await tester.tap(find.byKey(const ValueKey('nav-bookings')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Your upcoming and past bookings will be listed here.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('nav-home')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Hi, Alex 👋'), findsOneWidget);
    });

    testWidgets('the centre button opens the quick actions', (tester) async {
      await pumpHome(tester);
      await tester.tap(find.byKey(const ValueKey('nav-quick')));
      await tester.pumpAndSettle();
      expect(find.text('Book a court'), findsOneWidget);
      expect(find.text('Explore memberships'), findsOneWidget);
      expect(find.text('Find a coach'), findsOneWidget);
    });
  });

  group('Themes', () {
    for (final mode in [ThemeMode.dark, ThemeMode.light]) {
      testWidgets('renders without errors in ${mode.name} mode', (tester) async {
        await pumpHome(tester, mode: mode, data: playerData(history: true, bookings: [upcoming()], membership: true));
        expect(find.text('Hi, Alex 👋'), findsOneWidget);
        final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
        expect(scaffold.backgroundColor, mode == ThemeMode.dark ? const Color(0xFF050C19) : const Color(0xFFF7F9FD));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('switching theme keeps the current screen state', (tester) async {
      final h = await pumpHome(tester);
      await tester.tap(find.byKey(const ValueKey('sport-football')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.fling(find.byKey(const ValueKey('promo-pages')), const Offset(-300, 0), 1200);
      await tester.pump(const Duration(milliseconds: 500));

      h.container.read(themeModeProvider.notifier).toggle();
      await tester.pump(const Duration(milliseconds: 400));

      expect(h.container.read(themeModeProvider), ThemeMode.light);
      expect(h.container.read(selectedSportProvider), 'football');
      expect(find.text('Play regularly.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Profile has the Dark mode switch', (tester) async {
      final h = await pumpHome(tester);
      await tester.tap(find.byKey(const ValueKey('nav-profile')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('theme-switch')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(h.container.read(themeModeProvider), ThemeMode.light);
    });
  });

  group('Layouts', () {
    testWidgets('a small phone does not overflow, even with large system text', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.4;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpHome(tester, size: const Size(320, 640), data: playerData(history: true, bookings: [upcoming()], membership: true, coaching: true));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a wide window shows the desktop layout with the top bar', (tester) async {
      await pumpHome(tester, size: const Size(1280, 800));
      expect(find.text('Your Game,'), findsOneWidget);
      expect(find.text('All in '), findsOneWidget);
      expect(find.text('One Place'), findsOneWidget);
      expect(find.text('Your Next Game'), findsNothing); // web only; the phone layout keeps it
      expect(find.text('Find a Court'), findsOneWidget);
      expect(find.text('How GameAll Works'), findsOneWidget);
      expect(find.text('Real-time Availability'), findsOneWidget);
      expect(find.byKey(const ValueKey('nav-home')), findsNothing); // no bottom bar on the web layout
      expect(find.text('Tournaments'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the web brand bar: Venues, Memberships, Coaching, Tournaments, the city, a bell and a profile circle (no Home link)', (tester) async {
      final h = await pumpHome(tester, size: const Size(1280, 800));
      for (final label in ['Venues', 'Memberships', 'Coaching', 'Tournaments']) {
        expect(find.byKey(ValueKey('nav-$label')), findsOneWidget, reason: label);
      }
      // no Home link (the logo is the way home); the Location button shows the picked city; bell and profile circle on the right
      expect(find.byKey(const ValueKey('nav-Home')), findsNothing);
      expect(find.widgetWithText(Pressable, 'Home'), findsNothing);
      expect(find.descendant(of: find.byKey(const ValueKey('location-button')), matching: find.text('Bangalore, Karnataka')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Notifications')), findsOneWidget);
      expect(find.byIcon(Icons.person_rounded), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('login-button')));
      await tester.tap(find.byKey(const ValueKey('nav-Coaching')));
      await tester.tap(find.byKey(const ValueKey('nav-Memberships')));
      await tester.tap(find.bySemanticsLabel(RegExp('Notifications')));
      expect(h.routes, [AppRoutes.login, AppRoutes.coaching, AppRoutes.memberships, AppRoutes.notifications]);

      // the logo goes to Home from any tab
      await tester.tap(find.text('Venues'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Your Game,'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('brand-home')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Your Game,'), findsOneWidget);
    });

    testWidgets('the Location button opens the city picker', (tester) async {
      await pumpHome(tester, size: const Size(1280, 800));
      await tester.tap(find.byKey(const ValueKey('location-button')));
      await tester.pumpAndSettle();
      expect(find.text('Choose your city'), findsOneWidget);
    });

    testWidgets('on the web the city list is a centred popup, with a close button', (tester) async {
      final h = await pumpHome(tester, size: const Size(1280, 800));
      await tester.tap(find.byKey(const ValueKey('location-button')));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      // centred on the screen, not stuck to the bottom
      final box = tester.getRect(find.descendant(of: find.byType(Dialog), matching: find.byType(Material)).first);
      expect(box.center.dx, closeTo(640, 2));
      expect(box.center.dy, closeTo(400, 60));
      expect(box.width, lessThanOrEqualTo(440));

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(h.container.read(selectedCityProvider), 'Bangalore, Karnataka');

      await tester.tap(find.byKey(const ValueKey('location-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('city-Pune, Maharashtra')));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(h.container.read(selectedCityProvider), 'Pune, Maharashtra');
    });

    testWidgets('on a phone the city list is a bottom sheet', (tester) async {
      await pumpHome(tester);
      await tester.tap(find.byIcon(Icons.location_on_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('a tablet shows the phone layout, centred', (tester) async {
      await pumpHome(tester, size: const Size(700, 1000));
      expect(find.byKey(const ValueKey('nav-home')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

class _SlowRepository implements PlayerHomeRepository {
  @override
  Future<PlayerHomeData> load() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return playerData();
  }
}
