import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_player/core/routing/app_routes.dart';
import 'package:gameall_player/core/theme/app_theme.dart';
import 'package:gameall_player/core/widgets/pressable.dart';
import 'package:gameall_player/features/player_home/application/player_home_controller.dart';
import 'package:gameall_player/features/player_home/data/player_home_repository.dart';
import 'package:gameall_player/features/player_home/domain/player_home_models.dart';
import 'package:gameall_player/features/player_home/presentation/widgets/player_bottom_nav.dart';
import 'package:gameall_player/features/shell/coming_soon_page.dart';
import 'package:gameall_player/features/shell/player_shell.dart';
import 'package:gameall_player/features/venues/application/venues_providers.dart';
import 'package:gameall_player/features/venues/data/venue_repository.dart';
import 'package:gameall_player/features/venues/domain/venue.dart';

class FakeVenues implements VenueRepository {
  FakeVenues(this.byCity);
  final Map<String, List<Venue>> byCity;
  final asked = <String>[];

  @override
  Future<List<Venue>> listForLocation(String location) async {
    asked.add(location);
    return byCity[location] ?? const [];
  }
}

class _Home implements PlayerHomeRepository {
  @override
  Future<PlayerHomeData> load() async => const PlayerHomeData.guest();
}

const smash = Venue(id: 'v1', name: 'Smash Arena', city: 'Chennai', state: 'Tamil Nadu', area: 'Adyar', sports: ['Badminton'], courtCount: 3);
const ace = Venue(id: 'v2', name: 'Ace Courts', city: 'Chennai', sports: ['Badminton', 'Tennis'], courtCount: 1);

Future<(FakeVenues, ProviderContainer)> pumpApp(
  WidgetTester tester,
  Widget Function() home, {
  Map<String, List<Venue>>? venues,
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final fake = FakeVenues(venues ?? {'Chennai, Tamil Nadu': [smash, ace]});
  final container = ProviderContainer(overrides: [venueRepositoryProvider.overrideWithValue(fake), playerHomeRepositoryProvider.overrideWithValue(_Home())]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp(theme: AppTheme.dark(), home: home())));
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
  addTearDown(() async => tester.pumpWidget(const SizedBox()));
  return (fake, container);
}

void main() {
  group('Venue', () {
    test('reads the database answer', () {
      final v = Venue.fromJson({'id': 'x', 'name': 'Smash Arena', 'city': 'Chennai', 'state': 'Tamil Nadu', 'area': ' ', 'logoUrl': null, 'sports': ['Badminton', null], 'courtCount': 2});
      expect(v.area, isNull);
      expect(v.sports, ['Badminton']);
      expect(v.place, 'Chennai');
      expect(v.initials, 'SA');
      expect(smash.place, 'Adyar, Chennai');
    });

    test('splits a picked location into city and state', () {
      expect(splitLocation('Bangalore, Karnataka').city, 'Bangalore');
      expect(splitLocation('Bangalore, Karnataka').state, 'Karnataka');
      expect(splitLocation('Pune').state, isNull);
      expect(cityOf('Delhi NCR, Delhi'), 'Delhi NCR');
    });
  });

  group('Venues tab', () {
    testWidgets('with no venues in the picked city: an icon and a clear sentence naming the city', (tester) async {
      await pumpApp(tester, () => PlayerShell(initialTab: PlayerTab.explore, onNavigate: (_) {}));
      expect(find.byKey(const ValueKey('no-venues')), findsOneWidget);
      expect(find.byIcon(Icons.location_off_outlined), findsOneWidget);
      expect(find.text('No venues in Bangalore yet'), findsOneWidget);
      expect(find.textContaining('Currently no venues have been added for the location you selected'), findsOneWidget);
      expect(find.text('Change location'), findsOneWidget);
    });

    testWidgets('choosing a city that has venues lists them; going to an empty city shows the message again', (tester) async {
      final (fake, container) = await pumpApp(tester, () => PlayerShell(initialTab: PlayerTab.explore, onNavigate: (_) {}));
      await tester.tap(find.text('Change location'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('city-Chennai, Tamil Nadu')));
      await tester.pumpAndSettle();

      expect(container.read(selectedCityProvider), 'Chennai, Tamil Nadu');
      expect(find.byKey(const ValueKey('no-venues')), findsNothing);
      expect(find.text('Smash Arena'), findsOneWidget);
      expect(find.text('Ace Courts'), findsOneWidget);
      expect(find.text('3 courts'), findsOneWidget);
      expect(find.text('1 court'), findsOneWidget);
      expect(fake.asked, containsAll(['Bangalore, Karnataka', 'Chennai, Tamil Nadu']));

      container.read(selectedCityProvider.notifier).select('Kochi, Kerala');
      await tester.pumpAndSettle();
      expect(find.text('No venues in Kochi yet'), findsOneWidget);
      expect(find.text('Smash Arena'), findsNothing);
    });

    testWidgets('a venue card opens booking', (tester) async {
      final routes = <String>[];
      final (_, container) = await pumpApp(tester, () => PlayerShell(initialTab: PlayerTab.explore, onNavigate: routes.add));
      container.read(selectedCityProvider.notifier).select('Chennai, Tamil Nadu');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Smash Arena'));
      expect(routes, [AppRoutes.guestBooking]);
    });

    testWidgets('on the web the empty message also offers Change location, which opens the popup', (tester) async {
      await pumpApp(tester, () => PlayerShell(initialTab: PlayerTab.explore, onNavigate: (_) {}), size: const Size(1280, 800));
      expect(find.byKey(const ValueKey('no-venues')), findsOneWidget);
      await tester.tap(find.text('Change location'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
    });
  });

  group('brand bar pages on the web', () {
    for (final label in ['Venues', 'Memberships', 'Coaching', 'Tournaments']) {
      testWidgets('$label opens inside the page (no back button), title top left, message centred', (tester) async {
        await pumpApp(tester, () => const PlayerShell(), size: const Size(1600, 800));
        await tester.tap(find.descendant(of: find.byType(Pressable), matching: find.text(label)).first);
        await tester.pumpAndSettle();
        expect(find.byType(AppBar), findsNothing);
        expect(find.byType(BackButton), findsNothing);
        expect(find.byKey(const ValueKey('no-venues')), findsOneWidget);
        final title = tester.getTopLeft(find.text(label).last);
        expect(title.dx, lessThan(300));
        final message = tester.getCenter(find.byKey(const ValueKey('no-venues')));
        expect((message.dx - 800).abs(), lessThan(2));
      });
    }
  });

  testWidgets('Find a Court on the web home opens guest booking inside the page, no back button', (tester) async {
    await pumpApp(tester, () => const PlayerShell(), size: const Size(1600, 800));
    await tester.tap(find.text('Find a Court'));
    await tester.pumpAndSettle();
    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(BackButton), findsNothing);
    expect(find.text('Guest Court Booking'), findsOneWidget);
    expect(find.byKey(const ValueKey('no-venues')), findsOneWidget);
    expect(tester.getTopLeft(find.text('Guest Court Booking')).dx, lessThan(300));
  });

  group('every page that depends on the location', () {
    const locationPages = [AppRoutes.guestBooking, AppRoutes.memberships, AppRoutes.coaching, AppRoutes.tournaments, AppRoutes.search];

    for (final route in locationPages) {
      testWidgets('$route shows the no-venues message when the city has none', (tester) async {
        await pumpApp(tester, () => ComingSoonPage.forRoute(route));
        expect(find.byKey(const ValueKey('no-venues')), findsOneWidget);
        expect(find.byIcon(Icons.location_off_outlined), findsOneWidget);
        expect(find.text('No venues in Bangalore yet'), findsOneWidget);
      });

      testWidgets('$route shows its own content when the city has venues', (tester) async {
        final (_, container) = await pumpApp(tester, () => ComingSoonPage.forRoute(route));
        container.read(selectedCityProvider.notifier).select('Chennai, Tamil Nadu');
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('no-venues')), findsNothing);
        expect(find.text('2 venues in Chennai'), findsOneWidget);
      });
    }

    for (final route in [AppRoutes.login, AppRoutes.notifications, AppRoutes.howItWorks, AppRoutes.myMembership, AppRoutes.myCoaching]) {
      testWidgets('$route does not depend on the city', (tester) async {
        await pumpApp(tester, () => ComingSoonPage.forRoute(route));
        expect(find.byKey(const ValueKey('no-venues')), findsNothing);
      });
    }
  });
}
