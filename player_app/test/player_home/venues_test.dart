import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gameall_player/core/routing/app_routes.dart';
import 'package:gameall_player/core/theme/app_theme.dart';
import 'package:gameall_player/core/widgets/pressable.dart';
import 'package:gameall_player/core/widgets/sport_icon.dart';
import 'package:gameall_player/features/player_home/application/player_home_controller.dart';
import 'package:gameall_player/features/player_home/data/player_home_repository.dart';
import 'package:gameall_player/features/player_home/domain/player_home_models.dart';
import 'package:gameall_player/features/player_home/presentation/widgets/player_bottom_nav.dart';
import 'package:gameall_player/features/shell/coming_soon_page.dart';
import 'package:gameall_player/features/shell/player_pages.dart';
import 'package:gameall_player/features/shell/player_shell.dart';
import 'package:gameall_player/features/venues/application/venue_filters.dart';
import 'package:gameall_player/features/venues/application/venues_providers.dart';
import 'package:gameall_player/features/venues/data/venue_repository.dart';
import 'package:gameall_player/features/venues/domain/venue.dart';
import 'package:gameall_player/features/venues/domain/venue_detail.dart';

/// Venue lists by city and kind: `'Chennai, Tamil Nadu'` -> { venues: [...], memberships: [...], coaching: [...] }.
class FakeVenues extends VenueRepository {
  FakeVenues(this.data, {this.details = const {}, this.slots = const []});
  final Map<String, Map<VenueKind, List<Venue>>> data;
  final Map<String, VenueDetail> details;
  final List<CourtSlots> slots;
  final asked = <String>[];

  @override
  Future<VenueDetail?> getVenue(String venueId) async => details[venueId];

  @override
  Future<List<CourtSlots>> availability(AvailabilityQuery query) async => slots;

  @override
  Future<List<Venue>> listForLocation(String location, {VenueKind kind = VenueKind.venues}) async {
    asked.add('$location|${kind.wire}');
    return data[location]?[kind] ?? const [];
  }
}

class _Home implements PlayerHomeRepository {
  @override
  Future<PlayerHomeData> load() async => const PlayerHomeData.guest();
}

const smash = Venue(
  id: 'v1', name: 'Smash Arena', city: 'Chennai', state: 'Tamil Nadu', area: 'Adyar', sports: ['Badminton', 'Tennis'], courtCount: 3,
  minCourtPriceInr: 400, venueType: VenueType.indoor, amenities: Amenities(changingRooms: true), planNames: ['Gold', 'Silver', 'Bronze'], planCount: 3, minPlanPriceInr: 1500,
);
const ace = Venue(
  id: 'v2', name: 'Ace Courts', city: 'Chennai', sports: ['Cricket'], courtCount: 1,
  minCourtPriceInr: 250, programNames: ['Juniors'], programCount: 1, minProgramPriceInr: 1200,
);

final chennai = {
  'Chennai, Tamil Nadu': {
    VenueKind.venues: [smash, ace],
    VenueKind.memberships: [smash],
    VenueKind.coaching: [ace],
  },
};

Future<(FakeVenues, ProviderContainer)> pumpApp(
  WidgetTester tester,
  Widget Function() home, {
  Map<String, Map<VenueKind, List<Venue>>>? venues,
  Size size = const Size(390, 844),
  String? city,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final fake = FakeVenues(venues ?? chennai);
  final container = ProviderContainer(overrides: [venueRepositoryProvider.overrideWithValue(fake), playerHomeRepositoryProvider.overrideWithValue(_Home())]);
  addTearDown(container.dispose);
  if (city != null) container.read(selectedCityProvider.notifier).select(city);
  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp(theme: AppTheme.dark(), home: home())));
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
  addTearDown(() async => tester.pumpWidget(const SizedBox()));
  return (fake, container);
}

const inChennai = 'Chennai, Tamil Nadu';

/// Scrolls the page until [finder] is on screen, then taps it (the Filters panel is taller than a test window).
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
}

/// Routes the shell was asked to open (the shell's own navigation is replaced in these tests).
final lastRoutes = <String>[];

void main() {
  group('Venue', () {
    test('reads the database answer, including memberships and coaching', () {
      final v = Venue.fromJson({
        'id': 'x', 'name': 'Smash Arena', 'city': 'Chennai', 'state': 'Tamil Nadu', 'area': ' ', 'logoUrl': null, 'heroImageUrl': 'https://img/x.jpg',
        'sports': ['Badminton', null], 'courtCount': 2, 'minCourtPriceInr': 250,
        'memberships': {'count': 2, 'names': ['Gold', 'Silver'], 'minPriceInr': 1500},
        'coaching': {'count': 1, 'names': ['Juniors'], 'minPriceInr': 1200},
      });
      expect(v.area, isNull);
      expect(v.sports, ['Badminton']);
      expect(v.heroImageUrl, 'https://img/x.jpg');
      expect(v.hasTurf, isFalse);
      expect(v.priceFor(VenueKind.venues), 250);
      expect(v.priceFor(VenueKind.memberships), 1500);
      expect(v.chipsFor(VenueKind.coaching), ['Juniors']);
      expect(v.place, 'Chennai');
      expect(v.initials, 'SA');
      expect(smash.place, 'Adyar, Chennai');
    });

    test('an older answer without pictures or prices still reads', () {
      final v = Venue.fromJson({'id': 'x', 'name': 'Old', 'city': 'Pune', 'sports': [], 'courtCount': 1});
      expect(v.heroImageUrl, isNull);
      expect(v.priceFor(VenueKind.venues), isNull);
      expect(v.chipsFor(VenueKind.memberships), isEmpty);
    });

    test('a court rate of 0 is not shown as a price; a repeated city is not repeated', () {
      final v = Venue.fromJson({'id': 'x', 'name': 'Uma', 'city': 'Chennai', 'area': 'chennai', 'sports': ['Badminton'], 'minCourtPriceInr': 0, 'memberships': {'minPriceInr': 0}});
      expect(v.minCourtPriceInr, isNull);
      expect(v.priceFor(VenueKind.venues), isNull);
      expect(v.minPlanPriceInr, isNull);
      expect(v.place, 'Chennai');
    });

    test('every sport name gets its own icon kind', () {
      expect(sportKindOf('Badminton'), SportKind.badminton);
      expect(sportKindOf('Football (5v5)'), SportKind.football);
      expect(sportKindOf('Box Cricket'), SportKind.cricket);
      expect(sportKindOf('Table Tennis'), SportKind.tableTennis);
      expect(sportKindOf('Lawn Tennis'), SportKind.tennis);
      expect(sportKindOf('Pickleball'), SportKind.pickleball);
      expect(sportKindOf('Padel'), SportKind.padel);
      expect(sportKindOf('Basketball'), SportKind.basketball);
      expect(sportKindOf('Volleyball'), SportKind.volleyball);
      expect(sportKindOf('Squash'), SportKind.squash);
      expect(sportKindOf('Kabaddi'), SportKind.other);
      expect(sportKindOf(null), SportKind.other);
    });

    test('venue type and the five amenities are read; the on ones are listed in order', () {
      final v = Venue.fromJson({'id': 'x', 'name': 'V', 'city': 'C', 'venueType': 'OUTDOOR', 'amenities': {'parking': true, 'toilets': true, 'cafeteria': false}, 'photos': ['a.jpg', 'b.jpg']});
      expect(v.venueType, VenueType.outdoor);
      expect(v.amenities.labels, ['Free Parking', 'Toilets / Rest Room']);
      expect(v.photos, ['a.jpg', 'b.jpg']);
      expect(Venue.fromJson({'id': 'y', 'name': 'V', 'city': 'C'}).venueType, isNull);
      expect(const Amenities().labels, isEmpty);
    });

    test('splits a picked location into city and state', () {
      expect(splitLocation('Bangalore, Karnataka').city, 'Bangalore');
      expect(splitLocation('Bangalore, Karnataka').state, 'Karnataka');
      expect(splitLocation('Pune').state, isNull);
      expect(cityOf('Delhi NCR, Delhi'), 'Delhi NCR');
    });

    test('rupees use Indian digit grouping', () {
      expect(rupees(250), '₹250');
      expect(rupees(1500), '₹1,500');
      expect(rupees(150000), '₹1,50,000');
      expect(rupees(12345678), '₹1,23,45,678');
    });
  });

  group('filter logic', () {
    const turfy = Venue(id: 't', name: 'Turf Town', city: 'Chennai', sports: ['Football', 'Cricket'], surfaces: ['turf'], venueType: VenueType.outdoor, amenities: Amenities(parking: true, cafeteria: true), minCourtPriceInr: 900, courtCount: 2);
    const noPrice = Venue(id: 'n', name: 'No Price', city: 'Chennai', sports: ['Squash']);
    final all = [smash, ace, turfy, noPrice];

    List<String> names(VenueFilters f, [Set<String> saved = const {}]) => applyVenueFilters(all, f, saved).map((v) => v.name).toList();

    test('no filters: every venue, A to Z', () {
      expect(names(const VenueFilters()), ['Ace Courts', 'No Price', 'Smash Arena', 'Turf Town']);
    });

    test('search looks at name, area, city and sport, every word must match', () {
      expect(names(const VenueFilters(query: 'adyar')), ['Smash Arena']);
      expect(names(const VenueFilters(query: 'CRICKET')), ['Ace Courts', 'Turf Town']);
      expect(names(const VenueFilters(query: 'smash tennis')), ['Smash Arena']);
      expect(names(const VenueFilters(query: 'smash football')), isEmpty);
    });

    test('a sport keeps only the venues that play it (case-insensitive)', () {
      expect(names(const VenueFilters(sport: 'cricket')), ['Ace Courts', 'Turf Town']);
      expect(names(const VenueFilters(sport: 'Squash')), ['No Price']);
    });

    test('venue types and saved', () {
      expect(names(const VenueFilters(indoor: true)), ['Smash Arena']);
      expect(names(const VenueFilters(outdoor: true)), ['Turf Town']);
      expect(names(const VenueFilters(indoor: true, outdoor: true)), hasLength(4), reason: 'both ticked means any');
      expect(names(const VenueFilters(parking: true)), ['Turf Town']);
      expect(names(const VenueFilters(parking: true, cafeteria: true)), ['Turf Town']);
      expect(names(const VenueFilters(parking: true, toilets: true)), isEmpty);
      expect(names(const VenueFilters(changingRooms: true)), ['Smash Arena']);
      expect(names(const VenueFilters(academy: true)), ['Ace Courts']);
      expect(names(const VenueFilters(memberships: true)), ['Smash Arena']);
      expect(names(const VenueFilters(savedOnly: true), {'v2', 'n'}), ['Ace Courts', 'No Price']);
    });

    test('a price cap leaves out dearer venues and venues with no price', () {
      expect(names(const VenueFilters(maxPrice: 400)), ['Ace Courts', 'Smash Arena']);
      expect(names(const VenueFilters(maxPrice: 200)), isEmpty);
    });

    test('price sorting puts venues without a price last either way', () {
      expect(names(const VenueFilters(sort: VenueSort.priceLow)), ['Ace Courts', 'Smash Arena', 'Turf Town', 'No Price']);
      expect(names(const VenueFilters(sort: VenueSort.priceHigh)), ['Turf Town', 'Smash Arena', 'Ace Courts', 'No Price']);
    });

    test('filters combine; Clear All keeps sort and view', () {
      const f = VenueFilters(sport: 'Cricket', maxPrice: 300, sort: VenueSort.priceHigh, view: VenueView.list);
      expect(names(f), ['Ace Courts']);
      expect(f.activeCount, 2);
      final cleared = f.cleared();
      expect(cleared.activeCount, 0);
      expect(cleared.sort, VenueSort.priceHigh);
      expect(cleared.view, VenueView.list);
      expect(f.copyWith(sport: null).sport, isNull);
    });

    test('sports under More, and the price ceiling', () {
      expect(otherSports(all), ['Squash']);
      expect(priceCeiling(all), 900);
      expect(priceCeiling([smash, ace]), 400);
      expect(priceCeiling([noPrice]), 0);
    });
  });

  group('Discover venues page', () {
    Future<(FakeVenues, ProviderContainer)> open(WidgetTester tester, {Size size = const Size(1600, 1000), String? city = inChennai}) =>
        pumpApp(tester, () => PlayerShell(initialTab: PlayerTab.explore, onNavigate: lastRoutes.add), city: city, size: size);

    setUp(() {
      lastRoutes.clear();
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('banner, city, search box, sports row and Filters panel (web)', (tester) async {
      await open(tester);
      expect(find.textContaining('Discover Sports'), findsOneWidget);
      expect(find.text('Book courts, join memberships or find coaching near you.'), findsOneWidget);
      expect(find.text('Chennai, Tamil Nadu'), findsWidgets);
      expect(find.byKey(const ValueKey('discover-search')), findsOneWidget);
      expect(find.byKey(const ValueKey('discover-search-button')), findsOneWidget);
      for (final s in ['All Sports', 'Badminton', 'Football', 'Cricket', 'Tennis', 'Basketball', 'Pickleball', 'Padel']) {
        expect(find.text(s), findsWidgets, reason: s);
      }
      expect(find.text('Filters'), findsOneWidget);
      expect(find.text('Clear All'), findsOneWidget);
      expect(find.text('Venue Type'), findsOneWidget);
      for (final t in ['Indoor', 'Outdoor', 'Facilities', 'Free Parking', 'Changing Rooms', 'Toilets / Rest Room', 'Cafeteria', 'Equipment Rental']) {
        expect(find.text(t), findsWidgets, reason: t);
      }
      expect(find.text('Sort By'), findsOneWidget);
      expect(find.text('2 Venues Found'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('cards show photo area, name, place, price, sport chips and the arrow; three across', (tester) async {
      await open(tester);
      expect(find.text('Smash Arena'), findsOneWidget);
      expect(find.text('Adyar, Chennai'), findsOneWidget);
      expect(find.text('₹400 / hr'), findsOneWidget);
      expect(find.text('₹250 / hr'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_forward_rounded), findsNWidgets(2));
      expect(tester.getTopLeft(find.text('Ace Courts')).dy, tester.getTopLeft(find.text('Smash Arena')).dy, reason: 'same row');
    });

    testWidgets('a card opens the venue page', (tester) async {
      await open(tester);
      await tester.tap(find.text('Smash Arena'));
      expect(lastRoutes, [AppRoutes.venuePath('v1')]);
    });

    testWidgets('choosing a sport narrows the list, All Sports brings it back', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('sport-Cricket')));
      await tester.pumpAndSettle();
      expect(find.text('1 Venue Found'), findsOneWidget);
      expect(find.text('Ace Courts'), findsOneWidget);
      expect(find.text('Smash Arena'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('sport-all')));
      await tester.pumpAndSettle();
      expect(find.text('2 Venues Found'), findsOneWidget);
    });

    testWidgets('typing in the search box filters as you type; a miss says so and Clear all filters recovers', (tester) async {
      await open(tester);
      await tester.enterText(find.byKey(const ValueKey('discover-search')), 'smash');
      await tester.pumpAndSettle();
      expect(find.text('1 Venue Found'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('discover-search')), 'zzzz');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('no-matches')), findsOneWidget);
      expect(find.text('0 Venues Found'), findsOneWidget);
      await tester.tap(find.text('Clear all filters'));
      await tester.pumpAndSettle();
      expect(find.text('2 Venues Found'), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const ValueKey('discover-search'))).controller!.text, isEmpty);
    });

    testWidgets('venue type checkboxes, price cap and Clear All', (tester) async {
      final (_, container) = await open(tester);
      await tapVisible(tester, find.byKey(const ValueKey('filter-academy')));
      await tester.pumpAndSettle();
      expect(find.text('1 Venue Found'), findsOneWidget);
      expect(find.text('Ace Courts'), findsOneWidget);
      await tapVisible(tester, find.byKey(const ValueKey('clear-filters')));
      await tester.pumpAndSettle();
      expect(find.text('2 Venues Found'), findsOneWidget);

      await tapVisible(tester, find.byKey(const ValueKey('filter-outdoor')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('no-matches')), findsOneWidget, reason: 'neither test venue is outdoor');
      await tapVisible(tester, find.byKey(const ValueKey('filter-outdoor')));
      await tapVisible(tester, find.byKey(const ValueKey('filter-indoor')));
      await tester.pumpAndSettle();
      expect(find.text('1 Venue Found'), findsOneWidget);
      expect(find.text('Smash Arena'), findsOneWidget);
      await tapVisible(tester, find.byKey(const ValueKey('filter-indoor')));
      await tapVisible(tester, find.byKey(const ValueKey('filter-parking')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('no-matches')), findsOneWidget, reason: 'neither has free parking');
      await tapVisible(tester, find.byKey(const ValueKey('clear-filters')));
      await tester.pumpAndSettle();

      container.read(venueFiltersProvider.notifier).update((f) => f.copyWith(maxPrice: 300));
      await tester.pumpAndSettle();
      expect(find.text('Up to ₹300'), findsOneWidget);
      expect(find.text('1 Venue Found'), findsOneWidget);
    });

    testWidgets('Sort By changes the order', (tester) async {
      await open(tester);
      double x(String name) => tester.getTopLeft(find.text(name)).dx;
      expect(x('Ace Courts'), lessThan(x('Smash Arena')));
      await tapVisible(tester, find.byKey(const ValueKey('sort-by')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Price: High to Low').last);
      await tester.pumpAndSettle();
      expect(x('Smash Arena'), lessThan(x('Ace Courts')));
    });

    testWidgets('list view puts each venue on its own row', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('view-list')));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('Smash Arena')).dy, isNot(tester.getTopLeft(find.text('Ace Courts')).dy));
      await tester.tap(find.byKey(const ValueKey('view-grid')));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('Smash Arena')).dy, tester.getTopLeft(find.text('Ace Courts')).dy);
    });

    testWidgets('the heart saves a venue (kept on the device) and Saved venues only shows it', (tester) async {
      final (_, container) = await open(tester);
      await tester.tap(find.byKey(const ValueKey('heart-v1')));
      await tester.pumpAndSettle();
      expect(container.read(savedVenuesProvider), {'v1'});
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
      expect(lastRoutes, isEmpty, reason: 'the heart does not open the venue');
      await tapVisible(tester, find.byKey(const ValueKey('filter-saved')));
      await tester.pumpAndSettle();
      expect(find.text('1 Venue Found'), findsOneWidget);
      expect(find.text('Smash Arena'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('heart-v1')));
      await tester.pumpAndSettle();
      expect(container.read(savedVenuesProvider), isEmpty);
      expect(find.byKey(const ValueKey('no-matches')), findsOneWidget);
    });

    testWidgets('a saved venue is still saved after the page is reopened', (tester) async {
      SharedPreferences.setMockInitialValues({'saved_venue_ids': ['v2']});
      final (_, container) = await open(tester);
      expect(container.read(savedVenuesProvider), {'v2'});
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    });

    testWidgets('a sport that only appears in the data sits under More', (tester) async {
      await pumpApp(
        tester,
        () => PlayerShell(initialTab: PlayerTab.explore, onNavigate: (_) {}),
        city: inChennai,
        size: const Size(1600, 1000),
        venues: {inChennai: {VenueKind.venues: [smash, const Venue(id: 'q', name: 'Squash Hub', city: 'Chennai', sports: ['Squash'])]}},
      );
      expect(find.byKey(const ValueKey('sport-more')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('sport-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Squash').last);
      await tester.pumpAndSettle();
      expect(find.text('1 Venue Found'), findsOneWidget);
      expect(find.text('Squash Hub'), findsOneWidget);
    });

    testWidgets('a city with no venues keeps the banner and search, and shows the message', (tester) async {
      await open(tester, city: null);
      expect(find.textContaining('Discover Sports'), findsOneWidget);
      expect(find.byKey(const ValueKey('no-venues')), findsOneWidget);
      expect(find.text('No venues in Bangalore yet'), findsOneWidget);
      expect(find.text('Filters'), findsNothing, reason: 'nothing to filter');
    });

    testWidgets('the city box opens the city popup on the web', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('discover-city')));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
    });

    testWidgets('phone: stacked search, a Filters button with a sheet, one card per row, no overflow', (tester) async {
      await open(tester, size: const Size(390, 844));
      expect(find.byKey(const ValueKey('discover-search-button')), findsNothing);
      expect(find.text('Clear All'), findsNothing, reason: 'the panel is in a sheet on a phone');
      await tester.ensureVisible(find.byKey(const ValueKey('open-filters')));
      await tester.tap(find.byKey(const ValueKey('open-filters')));
      await tester.pumpAndSettle();
      expect(find.text('Clear All'), findsOneWidget);
      expect(find.text('Venue Type'), findsOneWidget);
      await tapVisible(tester, find.byKey(const ValueKey('filter-academy')));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10)); // close the sheet
      await tester.pumpAndSettle();
      expect(find.text('Filters (1)'), findsOneWidget);
      expect(find.text('1 Venue Found'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('phone with large text does not overflow', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.4;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await open(tester, size: const Size(320, 640));
      expect(tester.takeException(), isNull);
    });
  });

  group('Memberships and Coaching pages', () {
    testWidgets('Memberships lists only venues that created a plan, with plan chips and the lowest price', (tester) async {
      await pumpApp(tester, () => playerPageForRoute(AppRoutes.memberships, embedded: true), city: inChennai, size: const Size(1600, 900));
      expect(find.text('1 Venues With Memberships In Chennai'), findsOneWidget);
      expect(find.textContaining('Smash Arena'), findsOneWidget);
      expect(find.textContaining('Ace Courts'), findsNothing);
      expect(find.text('Gold'), findsOneWidget);
      expect(find.text('Silver'), findsOneWidget);
      expect(find.text('+1'), findsOneWidget);
      expect(find.text('from ₹1,500'), findsOneWidget);
    });

    testWidgets('Coaching lists only venues that created a programme', (tester) async {
      await pumpApp(tester, () => playerPageForRoute(AppRoutes.coaching, embedded: true), city: inChennai, size: const Size(1600, 900));
      expect(find.text('1 Venues With Coaching In Chennai'), findsOneWidget);
      expect(find.textContaining('Ace Courts'), findsOneWidget);
      expect(find.textContaining('Smash Arena'), findsNothing);
      expect(find.text('Juniors'), findsOneWidget);
      expect(find.text('from ₹1,200'), findsOneWidget);
    });

    testWidgets('a city with venues but none with plans says so', (tester) async {
      await pumpApp(
        tester,
        () => playerPageForRoute(AppRoutes.memberships, embedded: true),
        city: inChennai,
        venues: {inChennai: {VenueKind.venues: [smash]}},
      );
      expect(find.byKey(const ValueKey('no-venues')), findsOneWidget);
      expect(find.text('No memberships in Chennai yet'), findsOneWidget);
      expect(find.textContaining('membership plan'), findsOneWidget);
    });

    testWidgets('Coaching with none says so', (tester) async {
      await pumpApp(tester, () => playerPageForRoute(AppRoutes.coaching, embedded: true));
      expect(find.text('No coaching in Bangalore yet'), findsOneWidget);
    });

    testWidgets('on a phone the page opens on its own with a back button', (tester) async {
      await pumpApp(tester, () => playerPageForRoute(AppRoutes.memberships), city: inChennai);
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.textContaining('Smash Arena'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('brand bar pages on the web', () {
    testWidgets('Memberships is not in the brand bar', (tester) async {
      await pumpApp(tester, () => const PlayerShell(), size: const Size(1600, 800));
      expect(find.descendant(of: find.byType(Pressable), matching: find.text('Memberships')), findsNothing);
      expect(find.descendant(of: find.byType(Pressable), matching: find.text('Venues')), findsWidgets);
      expect(find.descendant(of: find.byType(Pressable), matching: find.text('Coaching')), findsWidgets);
    });

    for (final label in ['Venues', 'Coaching']) {
      testWidgets('$label opens inside the page (no back button), title top left, message centred when empty', (tester) async {
        await pumpApp(tester, () => const PlayerShell(), size: const Size(1600, 800));
        await tester.tap(find.descendant(of: find.byType(Pressable), matching: find.text(label)).first);
        await tester.pumpAndSettle();
        expect(find.byType(AppBar), findsNothing);
        expect(find.byType(BackButton), findsNothing);
        expect(find.byKey(const ValueKey('no-venues')), findsOneWidget);
        final message = tester.getCenter(find.byKey(const ValueKey('no-venues')));
        expect((message.dx - 800).abs(), lessThan(2));
      });
    }

    testWidgets('Tournaments says none have been created yet (they live in a separate app)', (tester) async {
      await pumpApp(tester, () => const PlayerShell(), size: const Size(1600, 800));
      await tester.tap(find.descendant(of: find.byType(Pressable), matching: find.text('Tournaments')).first);
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsNothing);
      expect(find.textContaining('No tournaments have been created yet'), findsOneWidget);
      expect(find.byKey(const ValueKey('no-venues')), findsNothing);
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
  });

  group('pages that depend on the picked city', () {
    for (final route in [AppRoutes.guestBooking, AppRoutes.search]) {
      testWidgets('$route shows the no-venues message when the city has none', (tester) async {
        await pumpApp(tester, () => ComingSoonPage.forRoute(route));
        expect(find.byKey(const ValueKey('no-venues')), findsOneWidget);
        expect(find.text('No venues in Bangalore yet'), findsOneWidget);
      });

      testWidgets('$route shows its own content when the city has venues', (tester) async {
        await pumpApp(tester, () => ComingSoonPage.forRoute(route), city: inChennai);
        expect(find.byKey(const ValueKey('no-venues')), findsNothing);
        expect(find.text('2 venues in Chennai'), findsOneWidget);
      });
    }

    for (final route in [AppRoutes.login, AppRoutes.notifications, AppRoutes.howItWorks, AppRoutes.myMembership, AppRoutes.myCoaching, AppRoutes.tournaments]) {
      testWidgets('$route does not depend on the city', (tester) async {
        await pumpApp(tester, () => ComingSoonPage.forRoute(route));
        expect(find.byKey(const ValueKey('no-venues')), findsNothing);
      });
    }
  });
}
