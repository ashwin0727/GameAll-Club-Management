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
import 'package:gameall_player/features/venues/application/membership_filters.dart';
import 'package:gameall_player/features/venues/application/venue_filters.dart';
import 'package:gameall_player/features/venues/application/venues_providers.dart';
import 'package:gameall_player/features/venues/data/venue_repository.dart';
import 'package:gameall_player/features/venues/application/coaching_filters.dart';
import 'package:gameall_player/features/venues/domain/coaching_listing.dart';
import 'package:gameall_player/features/venues/domain/venue.dart';
import 'package:gameall_player/features/venues/domain/venue_detail.dart';
import 'package:gameall_player/features/venues/presentation/coaching_enroll_page.dart';
import 'package:gameall_player/features/venues/presentation/discover_venues_page.dart';
import 'package:gameall_player/features/venues/presentation/enroll_membership_page.dart';

/// Venue lists by city and kind: `'Chennai, Tamil Nadu'` -> { venues: [...], memberships: [...], coaching: [...] }.
class FakeVenues extends VenueRepository {
  FakeVenues(
    this.data, {
    this.details = const {},
    this.slots = const [],
    this.coaching = const {},
  });
  final Map<String, List<CoachingListing>> coaching;
  final Map<String, Map<VenueKind, List<Venue>>> data;
  final Map<String, VenueDetail> details;
  final List<CourtSlots> slots;
  final asked = <String>[];

  @override
  Future<VenueDetail?> getVenue(String venueId) async => details[venueId];

  @override
  Future<List<CoachingListing>> listCoaching(String location) async =>
      coaching[location] ?? await super.listCoaching(location);

  @override
  Future<List<CourtSlots>> availability(AvailabilityQuery query) async => slots;

  @override
  Future<List<Venue>> listForLocation(
    String location, {
    VenueKind kind = VenueKind.venues,
  }) async {
    asked.add('$location|${kind.wire}');
    return data[location]?[kind] ?? const [];
  }
}

class _Home implements PlayerHomeRepository {
  @override
  Future<PlayerHomeData> load() async => const PlayerHomeData.guest();
}

const smash = Venue(
  id: 'v1',
  name: 'Smash Arena',
  city: 'Chennai',
  state: 'Tamil Nadu',
  area: 'Adyar',
  sports: ['Badminton', 'Tennis'],
  courtCount: 3,
  minCourtPriceInr: 400,
  venueType: VenueType.indoor,
  amenities: Amenities(changingRooms: true),
  planNames: ['Gold', 'Silver', 'Bronze'],
  planCount: 3,
  minPlanPriceInr: 1500,
  planPrices: [
    PlanPrice(30, 1800),
    PlanPrice(30, 1500),
    PlanPrice(90, 4000),
    PlanPrice(365, 12000),
    PlanPrice(10, 300),
  ],
  membershipDays: {1, 2, 3, 4, 5},
  opens: '06:00',
  closes: '22:00',
);
const ace = Venue(
  id: 'v2',
  name: 'Ace Courts',
  city: 'Chennai',
  sports: ['Cricket'],
  courtCount: 1,
  minCourtPriceInr: 250,
  programNames: ['Juniors'],
  programCount: 1,
  minProgramPriceInr: 1200,
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
  Map<String, List<CoachingListing>> coaching = const {},
  Size size = const Size(390, 844),
  String? city,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final fake = FakeVenues(venues ?? chennai, coaching: coaching);
  final container = ProviderContainer(
    overrides: [
      venueRepositoryProvider.overrideWithValue(fake),
      playerHomeRepositoryProvider.overrideWithValue(_Home()),
    ],
  );
  addTearDown(container.dispose);
  if (city != null) container.read(selectedCityProvider.notifier).select(city);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.dark(), home: home()),
    ),
  );
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
        'id': 'x',
        'name': 'Smash Arena',
        'city': 'Chennai',
        'state': 'Tamil Nadu',
        'area': ' ',
        'logoUrl': null,
        'heroImageUrl': 'https://img/x.jpg',
        'sports': ['Badminton', null],
        'courtCount': 2,
        'minCourtPriceInr': 250,
        'memberships': {
          'count': 2,
          'names': ['Gold', 'Silver'],
          'minPriceInr': 1500,
        },
        'coaching': {
          'count': 1,
          'names': ['Juniors'],
          'minPriceInr': 1200,
        },
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
      final v = Venue.fromJson({
        'id': 'x',
        'name': 'Old',
        'city': 'Pune',
        'sports': [],
        'courtCount': 1,
      });
      expect(v.heroImageUrl, isNull);
      expect(v.priceFor(VenueKind.venues), isNull);
      expect(v.chipsFor(VenueKind.memberships), isEmpty);
    });

    test('a court rate of 0 is not shown as a price; a repeated city is not repeated', () {
      final v = Venue.fromJson({
        'id': 'x',
        'name': 'Uma',
        'city': 'Chennai',
        'area': 'chennai',
        'sports': ['Badminton'],
        'minCourtPriceInr': 0,
        'memberships': {'minPriceInr': 0},
      });
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
      final v = Venue.fromJson({
        'id': 'x',
        'name': 'V',
        'city': 'C',
        'venueType': 'OUTDOOR',
        'amenities': {'parking': true, 'toilets': true, 'cafeteria': false},
        'photos': ['a.jpg', 'b.jpg'],
      });
      expect(v.venueType, VenueType.outdoor);
      expect(v.amenities.labels, ['Free Parking', 'Toilets / Rest Room']);
      expect(v.photos, ['a.jpg', 'b.jpg']);
      expect(
        Venue.fromJson({'id': 'y', 'name': 'V', 'city': 'C'}).venueType,
        isNull,
      );
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
    const turfy = Venue(
      id: 't',
      name: 'Turf Town',
      city: 'Chennai',
      sports: ['Football', 'Cricket'],
      surfaces: ['turf'],
      venueType: VenueType.outdoor,
      amenities: Amenities(parking: true, cafeteria: true),
      minCourtPriceInr: 900,
      courtCount: 2,
    );
    const noPrice = Venue(
      id: 'n',
      name: 'No Price',
      city: 'Chennai',
      sports: ['Squash'],
    );
    final all = [smash, ace, turfy, noPrice];

    // most checks are about which venues stay, so they read in A to Z unless a test picks another order
    List<String> names(VenueFilters f, [Set<String> saved = const {}]) =>
        applyVenueFilters(
          all,
          f.sort == VenueSort.recommended
              ? f.copyWith(sort: VenueSort.name)
              : f,
          saved,
        ).map((v) => v.name).toList();

    test('no filters: every venue, A to Z', () {
      expect(names(const VenueFilters()), [
        'Ace Courts',
        'No Price',
        'Smash Arena',
        'Turf Town',
      ]);
    });

    test(
      'search looks at name, area, city and sport, every word must match',
      () {
        expect(names(const VenueFilters(query: 'adyar')), ['Smash Arena']);
        expect(names(const VenueFilters(query: 'CRICKET')), [
          'Ace Courts',
          'Turf Town',
        ]);
        expect(names(const VenueFilters(query: 'smash tennis')), [
          'Smash Arena',
        ]);
        expect(names(const VenueFilters(query: 'smash football')), isEmpty);
      },
    );

    test('a sport keeps only the venues that play it (case-insensitive)', () {
      expect(names(const VenueFilters(sport: 'cricket')), [
        'Ace Courts',
        'Turf Town',
      ]);
      expect(names(const VenueFilters(sport: 'Squash')), ['No Price']);
    });

    test('venue types and saved', () {
      expect(names(const VenueFilters(indoor: true)), ['Smash Arena']);
      expect(names(const VenueFilters(outdoor: true)), ['Turf Town']);
      expect(
        names(const VenueFilters(indoor: true, outdoor: true)),
        hasLength(4),
        reason: 'both ticked means any',
      );
      expect(names(const VenueFilters(parking: true)), ['Turf Town']);
      expect(names(const VenueFilters(parking: true, cafeteria: true)), [
        'Turf Town',
      ]);
      expect(names(const VenueFilters(parking: true, toilets: true)), isEmpty);
      expect(names(const VenueFilters(changingRooms: true)), ['Smash Arena']);
      expect(names(const VenueFilters(academy: true)), ['Ace Courts']);
      expect(names(const VenueFilters(memberships: true)), ['Smash Arena']);
      expect(names(const VenueFilters(savedOnly: true), {'v2', 'n'}), [
        'Ace Courts',
        'No Price',
      ]);
    });

    test('a price cap leaves out dearer venues and venues with no price', () {
      expect(names(const VenueFilters(maxPrice: 400)), [
        'Ace Courts',
        'Smash Arena',
      ]);
      expect(names(const VenueFilters(maxPrice: 200)), isEmpty);
    });

    test('price sorting puts venues without a price last either way', () {
      expect(names(const VenueFilters(sort: VenueSort.priceLow)), [
        'Ace Courts',
        'Smash Arena',
        'Turf Town',
        'No Price',
      ]);
      expect(names(const VenueFilters(sort: VenueSort.priceHigh)), [
        'Turf Town',
        'Smash Arena',
        'Ace Courts',
        'No Price',
      ]);
    });

    test('filters combine; Clear All keeps sort and view', () {
      const f = VenueFilters(
        sport: 'Cricket',
        maxPrice: 300,
        sort: VenueSort.priceHigh,
        view: VenueView.list,
      );
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
      expect(priceFloor(all), 250);
      expect(priceFloor([turfy]), 900);
      expect(priceFloor([noPrice]), 0);
    });

    test('a price range keeps venues inside both ends', () {
      expect(names(const VenueFilters(minPrice: 300)), [
        'Smash Arena',
        'Turf Town',
      ]);
      expect(names(const VenueFilters(minPrice: 300, maxPrice: 500)), [
        'Smash Arena',
      ]);
      expect(names(const VenueFilters(minPrice: 1000)), isEmpty);
      expect(const VenueFilters(minPrice: 300).activeCount, 1);
      expect(
        const VenueFilters(minPrice: 300, maxPrice: 500).activeCount,
        1,
        reason: 'one price filter',
      );
    });

    test(
      'Recommended puts the better-presented venues first, ties by name',
      () {
        expect(recommendedScore(smash), greaterThan(recommendedScore(ace)));
        expect(
          applyVenueFilters(all, const VenueFilters(), const {}).first.name,
          'Smash Arena',
        );
        expect(
          applyVenueFilters(all, const VenueFilters(), const {}).last.name,
          'No Price',
        );
      },
    );

    test('counts of venues with each filter', () {
      final c = FilterCounts.of(all);
      expect(
        (
          c.indoor,
          c.outdoor,
          c.parking,
          c.changingRooms,
          c.cafeteria,
          c.academy,
          c.memberships,
        ),
        (1, 1, 1, 1, 1, 1, 1),
      );
    });
  });

  group('Discover venues page', () {
    Future<(FakeVenues, ProviderContainer)> open(
      WidgetTester tester, {
      Size size = const Size(1600, 1000),
      String? city = inChennai,
    }) => pumpApp(
      tester,
      () => PlayerShell(
        initialTab: PlayerTab.explore,
        onNavigate: lastRoutes.add,
      ),
      city: city,
      size: size,
    );

    setUp(() {
      lastRoutes.clear();
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets(
      'banner, city, search box, sports row and Filters panel (web)',
      (tester) async {
        await open(tester);
        expect(find.textContaining('Discover Sports'), findsOneWidget);
        expect(
          find.text('Book courts, join memberships or find coaching near you.'),
          findsOneWidget,
        );
        expect(find.text('Chennai, Tamil Nadu'), findsWidgets);
        expect(find.byKey(const ValueKey('discover-search')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('discover-search-button')),
          findsOneWidget,
        );
        // the sports are a dropdown left of the search box now (no chip row under it)
        expect(find.byKey(const ValueKey('sport-dropdown')), findsOneWidget);
        expect(find.text('All Sports'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('sport-all')),
          findsNothing,
          reason: 'the menu is closed',
        );
        final dropdown = tester.getRect(
          find.byKey(const ValueKey('sport-dropdown')),
        );
        final search = tester.getRect(
          find.byKey(const ValueKey('discover-search')),
        );
        final city = tester.getRect(
          find.byKey(const ValueKey('discover-city')),
        );
        final views = tester.getRect(find.byKey(const ValueKey('view-grid')));
        expect(city.right, lessThan(dropdown.left));
        expect(dropdown.right, lessThan(search.left));
        expect(
          views.left,
          greaterThan(search.right),
          reason: 'grid / list switch is right of the search bar',
        );
        await tester.tap(find.byKey(const ValueKey('sport-dropdown')));
        await tester.pumpAndSettle();
        for (final s in [
          'Badminton',
          'Football',
          'Cricket',
          'Tennis',
          'Basketball',
          'Pickleball',
          'Padel',
        ]) {
          expect(find.byKey(ValueKey('sport-$s')), findsOneWidget, reason: s);
        }
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();
        expect(find.text('Filters'), findsOneWidget);
        expect(find.text('Clear All'), findsOneWidget);
        expect(find.text('Venue Type'), findsOneWidget);
        for (final t in [
          'Indoor',
          'Outdoor',
          'Facilities',
          'Parking',
          'Locker Room',
          'Washroom',
          'Café / Snacks',
          'Equipment Rental',
        ]) {
          expect(find.text(t), findsWidgets, reason: t);
        }
        expect(
          find.byKey(const ValueKey('sort-by')),
          findsNothing,
          reason: 'no sort option',
        );
        expect(find.text('Apply Filters (2)'), findsOneWidget);
        expect(find.text('Price per hour'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('discover-highlights')),
          findsOneWidget,
        );
        for (final t in [
          'Instant Booking',
          'Check real-time availability',
          'Long-term playing plans',
          'Train with certified coaches',
        ]) {
          expect(find.text(t), findsOneWidget, reason: t);
        }
        expect(find.text('2 Venues Found'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'cards show photo area, name, place, price, sport chips and the arrow; three across',
      (tester) async {
        await open(tester);
        expect(find.text('Smash Arena'), findsOneWidget);
        expect(find.text('Adyar, Chennai'), findsOneWidget);
        expect(find.text('₹400 / hr'), findsOneWidget);
        expect(find.text('₹250 / hr'), findsOneWidget);
        expect(find.byIcon(Icons.arrow_forward_rounded), findsNWidgets(2));
        expect(
          tester.getTopLeft(find.text('Ace Courts')).dy,
          tester.getTopLeft(find.text('Smash Arena')).dy,
          reason: 'same row',
        );
      },
    );

    testWidgets('a card opens the venue page', (tester) async {
      await open(tester);
      await tester.tap(find.text('Smash Arena'));
      expect(lastRoutes, [AppRoutes.venuePath('v1')]);
    });

    testWidgets(
      'choosing a sport narrows the list, All Sports brings it back',
      (tester) async {
        await open(tester);
        await tester.tap(find.byKey(const ValueKey('sport-dropdown')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('sport-Cricket')));
        await tester.pumpAndSettle();
        expect(find.text('1 Venue Found'), findsOneWidget);
        expect(find.text('Ace Courts'), findsOneWidget);
        expect(find.text('Smash Arena'), findsNothing);
        expect(
          find.text('Cricket'),
          findsWidgets,
          reason: 'the dropdown shows the choice',
        );
        await tester.tap(find.byKey(const ValueKey('sport-dropdown')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('sport-all')));
        await tester.pumpAndSettle();
        expect(find.text('2 Venues Found'), findsOneWidget);
      },
    );

    testWidgets(
      'typing in the search box filters as you type; a miss says so and Clear all filters recovers',
      (tester) async {
        await open(tester);
        await tester.enterText(
          find.byKey(const ValueKey('discover-search')),
          'smash',
        );
        await tester.pumpAndSettle();
        expect(find.text('1 Venue Found'), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('discover-search')),
          'zzzz',
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('no-matches')), findsOneWidget);
        expect(find.text('0 Venues Found'), findsOneWidget);
        await tester.tap(find.text('Clear all filters'));
        await tester.pumpAndSettle();
        expect(find.text('2 Venues Found'), findsOneWidget);
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('discover-search')))
              .controller!
              .text,
          isEmpty,
        );
      },
    );

    testWidgets('venue type checkboxes, price cap and Clear All', (
      tester,
    ) async {
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
      expect(
        find.byKey(const ValueKey('no-matches')),
        findsOneWidget,
        reason: 'neither test venue is outdoor',
      );
      await tapVisible(tester, find.byKey(const ValueKey('filter-outdoor')));
      await tapVisible(tester, find.byKey(const ValueKey('filter-indoor')));
      await tester.pumpAndSettle();
      expect(find.text('1 Venue Found'), findsOneWidget);
      expect(find.text('Smash Arena'), findsOneWidget);
      await tapVisible(tester, find.byKey(const ValueKey('filter-indoor')));
      await tapVisible(tester, find.byKey(const ValueKey('filter-parking')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('no-matches')),
        findsOneWidget,
        reason: 'neither has free parking',
      );
      await tapVisible(tester, find.byKey(const ValueKey('clear-filters')));
      await tester.pumpAndSettle();

      container
          .read(venueFiltersProvider.notifier)
          .update((f) => f.copyWith(maxPrice: 300));
      await tester.pumpAndSettle();
      expect(find.text('₹250 – ₹300'), findsOneWidget);
      expect(find.text('1 Venue Found'), findsOneWidget);
    });

    testWidgets(
      'there is no sort option; venues come in the Recommended order',
      (tester) async {
        await open(tester);
        expect(find.byKey(const ValueKey('sort-by')), findsNothing);
        expect(find.textContaining('Sort by'), findsNothing);
        double x(String name) => tester.getTopLeft(find.text(name)).dx;
        // Recommended puts the better-presented venue (more courts, sports, plans) first
        expect(x('Smash Arena'), lessThan(x('Ace Courts')));
      },
    );

    testWidgets(
      'each filter shows how many venues have it, and Apply Filters shows the matching count',
      (tester) async {
        await open(tester);
        Text count(String label) =>
            tester.widget<Text>(find.byKey(ValueKey('count-$label')));
        expect(count('Indoor').data, '(1)');
        expect(count('Outdoor').data, '(0)');
        expect(count('Locker Room').data, '(1)');
        expect(count('Parking').data, '(0)');
        expect(count('Academy / Coaching').data, '(1)');
        expect(count('Memberships').data, '(1)');
        expect(find.text('Apply Filters (2)'), findsOneWidget);
        await tapVisible(tester, find.byKey(const ValueKey('filter-academy')));
        await tester.pumpAndSettle();
        expect(find.text('Apply Filters (1)'), findsOneWidget);
        await tapVisible(tester, find.byKey(const ValueKey('apply-filters')));
        await tester.pumpAndSettle();
        expect(
          find.text('1 Venue Found'),
          findsOneWidget,
          reason: 'Apply keeps the filters',
        );
      },
    );

    testWidgets('the price range has two handles and narrows both ends', (
      tester,
    ) async {
      final (_, container) = await open(tester);
      expect(find.byType(RangeSlider), findsOneWidget);
      expect(
        find.text('₹250 – ₹400'),
        findsOneWidget,
        reason: 'cheapest to dearest hourly price',
      );
      container
          .read(venueFiltersProvider.notifier)
          .update((f) => f.copyWith(minPrice: 300));
      await tester.pumpAndSettle();
      expect(find.text('₹300 – ₹400'), findsOneWidget);
      expect(find.text('1 Venue Found'), findsOneWidget);
      expect(find.text('Smash Arena'), findsOneWidget);
      expect(find.text('Filters'), findsOneWidget);
    });

    testWidgets(
      'a card has the type badge, outlined sport chips and a View & Book button',
      (tester) async {
        await open(tester);
        expect(find.byKey(const ValueKey('type-v1')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('type-v2')),
          findsNothing,
          reason: 'no indoor/outdoor set',
        );
        expect(find.byKey(const ValueKey('view-book-v1')), findsOneWidget);
        expect(find.text('View & Book'), findsNWidgets(2));
        expect(find.text('Tennis'), findsOneWidget, reason: 'on the card');
      },
    );

    testWidgets('list view puts each venue on its own row', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('view-list')));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Smash Arena')).dy,
        isNot(tester.getTopLeft(find.text('Ace Courts')).dy),
      );
      await tester.tap(find.byKey(const ValueKey('view-grid')));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Smash Arena')).dy,
        tester.getTopLeft(find.text('Ace Courts')).dy,
      );
    });

    testWidgets(
      'the heart saves a venue (kept on the device) and Saved venues only shows it',
      (tester) async {
        final (_, container) = await open(tester);
        await tester.tap(find.byKey(const ValueKey('heart-v1')));
        await tester.pumpAndSettle();
        expect(container.read(savedVenuesProvider), {'v1'});
        expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
        expect(
          lastRoutes,
          isEmpty,
          reason: 'the heart does not open the venue',
        );
        await tapVisible(tester, find.byKey(const ValueKey('filter-saved')));
        await tester.pumpAndSettle();
        expect(find.text('1 Venue Found'), findsOneWidget);
        expect(find.text('Smash Arena'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('heart-v1')));
        await tester.pumpAndSettle();
        expect(container.read(savedVenuesProvider), isEmpty);
        expect(find.byKey(const ValueKey('no-matches')), findsOneWidget);
      },
    );

    testWidgets('a saved venue is still saved after the page is reopened', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'saved_venue_ids': ['v2'],
      });
      final (_, container) = await open(tester);
      expect(container.read(savedVenuesProvider), {'v2'});
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    });

    testWidgets(
      'cards in a row are the same height even when one has more chips',
      (tester) async {
        await pumpApp(
          tester,
          () => PlayerShell(initialTab: PlayerTab.explore, onNavigate: (_) {}),
          city: inChennai,
          size: const Size(1600, 1000),
          venues: {
            inChennai: {
              VenueKind.venues: [
                smash,
                const Venue(
                  id: 'wide',
                  name: 'Many Sports',
                  city: 'Chennai',
                  sports: ['Badminton', 'Basketball', 'Cricket'],
                  minCourtPriceInr: 380,
                ),
                ace,
              ],
            },
          },
        );
        final heights = [
          for (final id in ['v1', 'wide', 'v2'])
            tester.getSize(find.byKey(ValueKey('card-$id'))).height,
        ];
        expect(heights[1], heights[0]);
        expect(heights[2], heights[0]);
        // the View & Book buttons line up along the bottom
        final bottoms = [
          for (final id in ['v1', 'wide', 'v2'])
            tester.getBottomLeft(find.byKey(ValueKey('view-book-$id'))).dy,
        ];
        expect(bottoms[1], bottoms[0]);
        expect(bottoms[2], bottoms[0]);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'filter rows keep each label on one line with the count at the right',
      (tester) async {
        await pumpApp(
          tester,
          () => PlayerShell(initialTab: PlayerTab.explore, onNavigate: (_) {}),
          city: inChennai,
          size: const Size(1600, 1000),
        );
        const rows = {
          'filter-rental': 'Equipment Rental',
          'filter-changing': 'Locker Room',
          'filter-cafeteria': 'Café / Snacks',
          'filter-memberships': 'Memberships',
          'filter-academy': 'Academy / Coaching',
          'filter-saved': 'Saved venues only',
        };
        rows.forEach((key, label) {
          final text = find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.text(label),
          );
          expect(
            tester.getSize(text).height,
            lessThan(24),
            reason: '$label is on one line',
          );
        });
        final rights = {
          for (final label in [
            'Parking',
            'Locker Room',
            'Washroom',
            'Equipment Rental',
            'Memberships',
          ])
            tester.getTopRight(find.byKey(ValueKey('count-$label'))).dx,
        };
        expect(rights, hasLength(1), reason: 'the counts line up');
      },
    );

    testWidgets('a sport that only appears in the data sits under More', (
      tester,
    ) async {
      await pumpApp(
        tester,
        () => PlayerShell(initialTab: PlayerTab.explore, onNavigate: (_) {}),
        city: inChennai,
        size: const Size(1600, 1000),
        venues: {
          inChennai: {
            VenueKind.venues: [
              smash,
              const Venue(
                id: 'q',
                name: 'Squash Hub',
                city: 'Chennai',
                sports: ['Squash'],
              ),
            ],
          },
        },
      );
      await tester.tap(find.byKey(const ValueKey('sport-dropdown')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sport-Squash')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('sport-Squash')));
      await tester.pumpAndSettle();
      expect(find.text('1 Venue Found'), findsOneWidget);
      expect(find.text('Squash Hub'), findsOneWidget);
    });

    testWidgets(
      'a city with no venues keeps the banner and search, and shows the message',
      (tester) async {
        await open(tester, city: null);
        expect(find.textContaining('Discover Sports'), findsOneWidget);
        expect(find.byKey(const ValueKey('no-venues')), findsOneWidget);
        expect(find.text('No venues in Bangalore yet'), findsOneWidget);
        expect(find.text('Filters'), findsNothing, reason: 'nothing to filter');
      },
    );

    testWidgets('the city box opens the city popup on the web', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('discover-city')));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
    });

    testWidgets(
      'phone: stacked search, a Filters button with a sheet, one card per row, no overflow',
      (tester) async {
        await open(tester, size: const Size(390, 844));
        expect(
          find.byKey(const ValueKey('discover-search-button')),
          findsNothing,
        );
        expect(
          find.text('Clear All'),
          findsNothing,
          reason: 'the panel is in a sheet on a phone',
        );
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
      },
    );

    testWidgets('phone with large text does not overflow', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.4;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await open(tester, size: const Size(320, 640));
      expect(tester.takeException(), isNull);
    });
  });

  group('Memberships and Coaching pages', () {
    Future<(FakeVenues, ProviderContainer)> openMemberships(
      WidgetTester tester, {
      Size size = const Size(1600, 1000),
    }) => pumpApp(
      tester,
      () => Scaffold(
        body: playerPageForRoute(
          AppRoutes.memberships,
          embedded: true,
          onNavigate: lastRoutes.add,
        ),
      ),
      city: inChennai,
      size: size,
    );

    testWidgets(
      'Memberships: banner, highlights, only venues with a plan, and the lowest price of each length',
      (tester) async {
        lastRoutes.clear();
        await openMemberships(tester);
        expect(find.textContaining('Explore'), findsOneWidget);
        expect(
          find.text(
            'Long-term play plans with dedicated court time, priority access and more.',
          ),
          findsOneWidget,
        );
        for (final t in [
          'Dedicated Court Time',
          'Priority Access',
          'Better Value',
          'Play at your preferred slot',
          'Get preferred court bookings',
          'Save more with long-term plans',
        ]) {
          expect(find.text(t), findsOneWidget, reason: t);
        }
        expect(find.text('1 Venue Found'), findsOneWidget);
        expect(find.text('Smash Arena'), findsOneWidget);
        expect(
          find.text('Ace Courts'),
          findsNothing,
          reason: 'no membership plan',
        );
        expect(find.text('Adyar, Chennai'), findsOneWidget);
        expect(find.text('Badminton, Tennis'), findsOneWidget);
        expect(find.text('3 Courts'), findsOneWidget);
        expect(find.text('6:00 AM - 10:00 PM'), findsOneWidget);
        expect(find.text('Available Memberships'), findsOneWidget);
        // the lowest price of each length: Monthly has ₹1,800 and ₹1,500 (₹1,500 wins), the 10-day pass is no length at all
        Finder tile(String key) => find.byKey(ValueKey('mem-tile-v1-$key'));
        expect(
          find.descendant(of: tile('monthly'), matching: find.text('₹1,500')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: tile('threeMonths'),
            matching: find.text('₹4,000'),
          ),
          findsOneWidget,
        );
        expect(tile('sixMonths'), findsNothing, reason: 'no 6-month plan');
        expect(
          find.descendant(of: tile('yearly'), matching: find.text('₹12,000')),
          findsOneWidget,
        );
        expect(find.text('₹1,800'), findsNothing);
        expect(find.text('₹300'), findsNothing);
        expect(find.byKey(const ValueKey('sort-by')), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'View Plans (and the card) open the venue\'s Enroll Membership page',
      (tester) async {
        lastRoutes.clear();
        await openMemberships(tester);
        await tester.tap(find.byKey(const ValueKey('view-plans-v1')));
        expect(lastRoutes, [AppRoutes.enrollPath('v1')]);
      },
    );

    testWidgets(
      'Memberships has the venue page\'s search card and the design\'s filters',
      (tester) async {
        await openMemberships(tester);
        final dropdown = tester.getRect(
          find.byKey(const ValueKey('sport-dropdown')),
        );
        final search = tester.getRect(
          find.byKey(const ValueKey('discover-search')),
        );
        final views = tester.getRect(find.byKey(const ValueKey('view-grid')));
        expect(find.byKey(const ValueKey('discover-city')), findsOneWidget);
        expect(dropdown.right, lessThan(search.left));
        expect(views.left, greaterThan(search.right));
        expect(find.text('Filters'), findsOneWidget);
        for (final t in [
          'Membership Duration',
          'Monthly',
          '3 Months',
          '6 Months',
          'Yearly',
          'Time Slot',
          'Days',
          'Mon – Fri',
          'Mon – Sat',
          'All Days',
        ]) {
          expect(find.text(t), findsWidgets, reason: t);
        }
        Text count(String label) =>
            tester.widget<Text>(find.byKey(ValueKey('count-$label')));
        expect(count('Monthly').data, '(1)');
        expect(count('3 Months').data, '(1)');
        expect(count('6 Months').data, '(0)');
        expect(count('Yearly').data, '(1)');
        expect(count('Mon – Fri').data, '(1)');
        expect(count('Mon – Sat').data, '(0)');
        expect(count('All Days').data, '(0)');
        expect(find.text('Any Time'), findsOneWidget);
        expect(find.text('Apply Filters (1)'), findsOneWidget);
      },
    );

    testWidgets(
      'Memberships filters narrow the list and Clear All brings it back',
      (tester) async {
        await openMemberships(tester);
        await tapVisible(
          tester,
          find.byKey(const ValueKey('filter-duration-sixMonths')),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('no-matches')), findsOneWidget);
        expect(find.text('Apply Filters (0)'), findsOneWidget);
        await tapVisible(tester, find.byKey(const ValueKey('clear-filters')));
        await tester.pumpAndSettle();
        expect(find.text('1 Venue Found'), findsOneWidget);
        await tapVisible(
          tester,
          find.byKey(const ValueKey('filter-duration-yearly')),
        );
        await tapVisible(
          tester,
          find.byKey(const ValueKey('filter-days-monFri')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Smash Arena'), findsOneWidget);
        await tapVisible(
          tester,
          find.byKey(const ValueKey('filter-days-allDays')),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Smash Arena'),
          findsOneWidget,
          reason: 'days are "any of"',
        );
        await tapVisible(
          tester,
          find.byKey(const ValueKey('filter-days-monFri')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('no-matches')),
          findsOneWidget,
          reason: 'only All Days is left, the venue does not run on weekends',
        );
        await tapVisible(tester, find.byKey(const ValueKey('clear-filters')));
        await tester.tap(find.byKey(const ValueKey('slot-dropdown')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Evening (5 – 10 PM)').last);
        await tester.pumpAndSettle();
        expect(
          find.text('Smash Arena'),
          findsOneWidget,
          reason: 'open until 10 PM',
        );
        await tester.enterText(
          find.byKey(const ValueKey('discover-search')),
          'zzzz',
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('no-matches')), findsOneWidget);
      },
    );

    testWidgets('Memberships: the grid switch stacks the cards', (
      tester,
    ) async {
      await openMemberships(tester);
      final rowCardHeight = tester
          .getSize(find.byKey(const ValueKey('card-v1')))
          .height;
      await tester.tap(find.byKey(const ValueKey('view-grid')));
      await tester.pumpAndSettle();
      expect(find.text('Smash Arena'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const ValueKey('card-v1'))).height,
        greaterThan(rowCardHeight),
        reason: 'photo on top, so taller',
      );
      expect(find.byKey(const ValueKey('view-plans-v1')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // a venue whose plans belong to two sports through their batches
    const multiSport = Venue(
      id: 'm1',
      name: 'Multi Sports',
      city: 'Chennai',
      sports: ['Badminton', 'Tennis'],
      courtCount: 4,
      planCount: 4,
      minPlanPriceInr: 1500,
      planPrices: [
        PlanPrice(30, 1500),
        PlanPrice(90, 4000),
        PlanPrice(30, 2500),
        PlanPrice(365, 20000),
      ],
      sportPlans: {
        'Badminton': [PlanPrice(30, 1500), PlanPrice(90, 4000)],
        'Tennis': [PlanPrice(30, 2500), PlanPrice(365, 20000)],
      },
    );

    testWidgets(
      'Memberships: a venue with plans in several sports has a chip per sport and the prices follow the sport',
      (tester) async {
        final (_, container) = await pumpApp(
          tester,
          () => Scaffold(
            body: playerPageForRoute(
              AppRoutes.memberships,
              embedded: true,
              onNavigate: lastRoutes.add,
            ),
          ),
          city: inChennai,
          size: const Size(1600, 1000),
          venues: {
            inChennai: {
              VenueKind.venues: [smash, multiSport],
              VenueKind.memberships: [smash, multiSport],
            },
          },
        );
        Finder tile(String venue, String key) =>
            find.byKey(ValueKey('mem-tile-$venue-$key'));
        // chips only on the venue whose plans differ by sport
        expect(
          find.byKey(const ValueKey('mem-sport-m1-Badminton')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('mem-sport-m1-Tennis')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('mem-sport-v1-Badminton')),
          findsNothing,
        );
        // Badminton to start with
        expect(
          find.descendant(
            of: tile('m1', 'monthly'),
            matching: find.text('₹1,500'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: tile('m1', 'threeMonths'),
            matching: find.text('₹4,000'),
          ),
          findsOneWidget,
        );
        expect(tile('m1', 'yearly'), findsNothing);
        // Tennis: its own prices
        await tester.tap(find.byKey(const ValueKey('mem-sport-m1-Tennis')));
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: tile('m1', 'monthly'),
            matching: find.text('₹2,500'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: tile('m1', 'yearly'),
            matching: find.text('₹20,000'),
          ),
          findsOneWidget,
        );
        expect(tile('m1', 'threeMonths'), findsNothing);
        // the other venue is untouched
        expect(
          find.descendant(
            of: tile('v1', 'monthly'),
            matching: find.text('₹1,500'),
          ),
          findsOneWidget,
        );
        // View Plans still opens the venue's enrolment page
        lastRoutes.clear();
        await tester.tap(find.byKey(const ValueKey('view-plans-m1')));
        expect(lastRoutes, [AppRoutes.enrollPath('m1')]);
        expect(
          container.read(preferredSportProvider),
          'Tennis',
          reason: 'the enrolment page starts on the sport shown on the card',
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Memberships: the sport picked in the search card selects the sport on the card',
      (tester) async {
        await pumpApp(
          tester,
          () => Scaffold(
            body: playerPageForRoute(AppRoutes.memberships, embedded: true),
          ),
          city: inChennai,
          size: const Size(1600, 1000),
          venues: {
            inChennai: {
              VenueKind.venues: [multiSport],
              VenueKind.memberships: [multiSport],
            },
          },
        );
        await tester.tap(find.byKey(const ValueKey('sport-dropdown')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('sport-Tennis')));
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('mem-tile-m1-monthly')),
            matching: find.text('₹2,500'),
          ),
          findsOneWidget,
        );
        // a duration filter looks at that sport's plans: Tennis has no 3-month plan, so the venue goes
        await tapVisible(
          tester,
          find.byKey(const ValueKey('filter-duration-threeMonths')),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('no-matches')), findsOneWidget);
      },
    );

    test('plans of a sport: plansFor, membershipSports and the fallback to every plan', () {
      expect(multiSport.membershipSports, ['Badminton', 'Tennis']);
      expect(multiSport.plansFor('tennis').map((p) => p.priceInr), [
        2500,
        20000,
      ]);
      expect(
        multiSport.plansFor('Cricket'),
        isEmpty,
        reason: 'no plans in that sport',
      );
      expect(multiSport.plansFor(null), hasLength(4));
      expect(smash.sportPlans, isEmpty);
      expect(smash.membershipSports, [
        'Badminton',
        'Tennis',
      ], reason: 'no sport split: its sports');
      expect(
        smash.plansFor('Tennis'),
        smash.planPrices,
        reason: 'no sport split: every plan',
      );
      expect(lowestPriceByDuration(multiSport, sport: 'Tennis'), {
        PlanDuration.monthly: 2500,
        PlanDuration.yearly: 20000,
      });
      expect(lowestPlanPrice(multiSport, sport: 'Tennis'), 2500);
      final read = Venue.fromJson({
        'id': 'x',
        'name': 'X',
        'city': 'Chennai',
        'memberships': {
          'count': 2,
          'plans': [
            {'durationDays': 30, 'priceInr': 1000},
          ],
          'bySport': [
            {
              'sport': 'Squash',
              'plans': [
                {'durationDays': 30, 'priceInr': 1000},
              ],
            },
          ],
        },
      });
      expect(read.sportPlans.keys, ['Squash']);
      final filled = smash.withPlans(
        const [PlanPrice(30, 900)],
        const {
          'Padel': [PlanPrice(30, 900)],
        },
      );
      expect(filled.name, 'Smash Arena');
      expect(filled.sportPlans.keys, ['Padel']);
      expect(filled.planPrices.single.priceInr, 900);
    });

    testWidgets(
      'Memberships on a phone: stacked card, a Filters button, no overflow',
      (tester) async {
        await openMemberships(tester, size: const Size(390, 844));
        expect(
          find.byKey(const ValueKey('discover-search-button')),
          findsNothing,
        );
        expect(find.text('Smash Arena'), findsOneWidget);
        await tester.ensureVisible(find.byKey(const ValueKey('view-plans-v1')));
        expect(
          find.byKey(const ValueKey('mem-tile-v1-monthly')),
          findsOneWidget,
        );
        await tester.ensureVisible(find.byKey(const ValueKey('open-filters')));
        await tester.tap(find.byKey(const ValueKey('open-filters')));
        await tester.pumpAndSettle();
        expect(find.text('Membership Duration'), findsOneWidget);
        await tapVisible(
          tester,
          find.byKey(const ValueKey('filter-duration-sixMonths')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('apply-filters')));
        await tester.pumpAndSettle();
        expect(find.text('Filters (1)'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Memberships on a small phone with large text does not overflow',
      (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 1.4;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await openMemberships(tester, size: const Size(320, 640));
        expect(tester.takeException(), isNull);
      },
    );

    test('plan lengths, lowest prices, time slots and days', () {
      expect(PlanDuration.ofDays(30), PlanDuration.monthly);
      expect(PlanDuration.ofDays(90), PlanDuration.threeMonths);
      expect(PlanDuration.ofDays(180), PlanDuration.sixMonths);
      expect(PlanDuration.ofDays(365), PlanDuration.yearly);
      expect(PlanDuration.ofDays(10), isNull);
      expect(lowestPriceByDuration(smash), {
        PlanDuration.monthly: 1500,
        PlanDuration.threeMonths: 4000,
        PlanDuration.yearly: 12000,
      });
      expect(lowestPlanPrice(smash), 1500);
      List<String> names(MembershipFilters f) =>
          applyMembershipFilters([smash, ace], f).map((v) => v.name).toList();
      expect(names(const MembershipFilters()), ['Smash Arena', 'Ace Courts']);
      expect(
        names(const MembershipFilters(durations: {PlanDuration.sixMonths})),
        isEmpty,
      );
      expect(
        names(
          const MembershipFilters(
            durations: {PlanDuration.monthly, PlanDuration.sixMonths},
          ),
        ),
        ['Smash Arena'],
      );
      expect(names(const MembershipFilters(slot: TimeSlot.morning)), [
        'Smash Arena',
      ], reason: 'Ace has no hours');
      expect(names(const MembershipFilters(days: {DayCover.monSat})), isEmpty);
      expect(names(const MembershipFilters(sport: 'badminton')), [
        'Smash Arena',
      ]);
      expect(names(const MembershipFilters(query: 'adyar')), ['Smash Arena']);
      const f = MembershipFilters(
        durations: {PlanDuration.monthly},
        days: {DayCover.monFri},
        slot: TimeSlot.evening,
        view: VenueView.grid,
      );
      expect(f.activeCount, 3);
      expect(f.cleared().activeCount, 0);
      expect(f.cleared().view, VenueView.grid);
    });

    const beginner = CoachingListing(
      programId: 'p1',
      name: 'Beginner Program',
      venueId: 'v2',
      venueName: 'Ace Courts',
      venueCity: 'Chennai',
      level: 'Beginner',
      description: 'Build a strong foundation with proper techniques.',
      sport: 'Badminton',
      feeType: 'MONTHLY',
      priceInr: 2999,
      maxCapacity: 8,
      batches: [
        ListedBatch(startHour: 6, days: {1, 2, 3, 4, 5}),
      ],
      coach: ListedCoach(
        name: 'Arjun',
        certifications: 'BWF Level 1 Certified',
        rating: 4.9,
        experienceYears: 5,
      ),
    );
    const advanced = CoachingListing(
      programId: 'p2',
      name: 'Advanced Program',
      venueId: 'v1',
      venueName: 'Smash Arena',
      venueArea: 'Adyar',
      venueCity: 'Chennai',
      level: 'Advanced',
      sport: 'Tennis',
      programType: 'ONE_ON_ONE',
      priceInr: 4999,
      maxCapacity: 4,
      batches: [
        ListedBatch(startHour: 18, days: {0, 6}),
      ],
      coach: ListedCoach(name: 'Coach Divya'),
    );
    const noCoach = CoachingListing(
      programId: 'p3',
      name: 'Juniors',
      venueId: 'v3',
      venueName: 'Zen Courts',
      venueCity: 'Chennai',
      priceInr: 1200,
    );
    const listings = {
      inChennai: [beginner, advanced, noCoach],
    };

    Future<(FakeVenues, ProviderContainer)> openCoaching(
      WidgetTester tester, {
      Size size = const Size(1600, 1000),
      Map<String, List<CoachingListing>> data = listings,
    }) => pumpApp(
      tester,
      () => Scaffold(
        body: playerPageForRoute(
          AppRoutes.coaching,
          embedded: true,
          onNavigate: lastRoutes.add,
        ),
      ),
      city: inChennai,
      size: size,
      coaching: data,
    );

    testWidgets(
      'Coaching: banner, highlights, and a card per programme with its coach',
      (tester) async {
        lastRoutes.clear();
        await openCoaching(tester);
        expect(find.textContaining('Explore'), findsOneWidget);
        expect(
          find.text(
            'Learn, improve and compete with certified coaches near you.',
          ),
          findsOneWidget,
        );
        for (final t in [
          'Certified Coaches',
          'All Skill Levels',
          'Flexible Batches',
          'Multiple Venues',
          'Train with verified experts',
          'Beginner to advanced',
          'Group or individual training',
          'Choose a venue near you',
        ]) {
          expect(find.text(t), findsOneWidget, reason: t);
        }
        expect(find.text('3 Coaching Programs Found'), findsOneWidget);
        // the venue on the photo
        expect(find.byKey(const ValueKey('venue-p1')), findsOneWidget);
        expect(find.text('Adyar, Chennai'), findsOneWidget);
        // the coach: "Coach" in front of a plain name, the certification, rating and years
        expect(find.text('Coach Arjun'), findsOneWidget);
        expect(find.text('BWF Level 1 Certified'), findsOneWidget);
        expect(find.text('4.9'), findsOneWidget);
        expect(find.text('5+ Years Experience'), findsOneWidget);
        expect(
          find.text('Coach Divya'),
          findsOneWidget,
          reason: 'a name that already says Coach is kept',
        );
        // the programme
        expect(find.text('Badminton – Beginner Program'), findsOneWidget);
        expect(
          find.text('Build a strong foundation with proper techniques.'),
          findsOneWidget,
        );
        expect(find.text('Group Batch'), findsWidgets);
        expect(find.text('Individual'), findsOneWidget);
        expect(find.text('Beginner'), findsWidgets);
        expect(find.text('Max 8'), findsOneWidget);
        // the fee
        expect(find.textContaining('₹2,999'), findsOneWidget);
        expect(find.textContaining('/ month'), findsOneWidget);
        expect(find.textContaining('₹4,999'), findsOneWidget);
        expect(
          find.textContaining('one-time'),
          findsNWidgets(2),
          reason: 'Advanced and Juniors are one-time fees',
        );
        // a programme with no coach says so instead of leaving a gap
        expect(find.text('Coach Details are not available'), findsOneWidget);
        expect(find.byKey(const ValueKey('sort-by')), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Coaching: View & Enroll, the card and the arrow open the right pages; the heart saves the venue',
      (tester) async {
        lastRoutes.clear();
        final (_, container) = await openCoaching(tester);
        await tester.tap(find.byKey(const ValueKey('enroll-p1')));
        expect(lastRoutes, [AppRoutes.coachingEnrollPath('v2')]);
        lastRoutes.clear();
        await tester.tap(find.byKey(const ValueKey('open-venue-p2')));
        expect(lastRoutes, [AppRoutes.venuePath('v1')]);
        await tester.tap(find.byKey(const ValueKey('heart-p2')));
        await tester.pumpAndSettle();
        expect(container.read(savedVenuesProvider), {'v1'});
      },
    );

    testWidgets(
      'Coaching has the venue page\'s search card and the design\'s filters',
      (tester) async {
        await openCoaching(tester);
        final dropdown = tester.getRect(
          find.byKey(const ValueKey('sport-dropdown')),
        );
        final search = tester.getRect(
          find.byKey(const ValueKey('discover-search')),
        );
        final views = tester.getRect(find.byKey(const ValueKey('view-grid')));
        expect(dropdown.right, lessThan(search.left));
        expect(views.left, greaterThan(search.right));
        for (final t in [
          'Coaching Level',
          'Beginner',
          'Intermediate',
          'Advanced',
          'Coaching Type',
          'Group Training',
          'Individual Training',
          'Preferred Time',
          'Days',
          'Any Time',
          'Any Days',
        ]) {
          expect(find.text(t), findsWidgets, reason: t);
        }
        Text count(String label) =>
            tester.widget<Text>(find.byKey(ValueKey('count-$label')));
        // "All Levels" programmes (Juniors) fit every level
        expect(count('Beginner').data, '(2)');
        expect(count('Intermediate').data, '(1)');
        expect(count('Advanced').data, '(2)');
        expect(count('Group Training').data, '(2)');
        expect(count('Individual Training').data, '(1)');
        expect(find.text('Apply Filters (3)'), findsOneWidget);
      },
    );

    testWidgets('Coaching filters narrow the list; Clear All brings it back', (
      tester,
    ) async {
      await openCoaching(tester);
      await tapVisible(
        tester,
        find.byKey(const ValueKey('filter-type-individual')),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 Coaching Program Found'), findsOneWidget);
      expect(find.text('Coach Divya'), findsOneWidget);
      await tapVisible(tester, find.byKey(const ValueKey('clear-filters')));
      await tester.pumpAndSettle();
      expect(find.text('3 Coaching Programs Found'), findsOneWidget);
      await tapVisible(
        tester,
        find.byKey(const ValueKey('filter-level-advanced')),
      );
      await tester.pumpAndSettle();
      expect(find.text('2 Coaching Programs Found'), findsOneWidget);
      await tapVisible(tester, find.byKey(const ValueKey('clear-filters')));
      await tapVisible(tester, find.byKey(const ValueKey('days-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Weekends (Sat – Sun)').last);
      await tester.pumpAndSettle();
      expect(find.text('1 Coaching Program Found'), findsOneWidget);
      expect(find.text('Coach Divya'), findsOneWidget);
      await tapVisible(tester, find.byKey(const ValueKey('time-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Morning (5 AM – 12 PM)').last);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('no-matches')),
        findsOneWidget,
        reason: 'the weekend batch is in the evening',
      );
      await tapVisible(tester, find.byKey(const ValueKey('clear-filters')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sport-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sport-Tennis')));
      await tester.pumpAndSettle();
      expect(find.text('1 Coaching Program Found'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('discover-search')),
        'arjun',
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('no-matches')),
        findsOneWidget,
        reason: 'Arjun teaches badminton, the sport is Tennis',
      );
    });

    testWidgets('Coaching: the list switch makes one wide row per programme', (
      tester,
    ) async {
      await openCoaching(tester);
      final gridWidth = tester
          .getSize(find.byKey(const ValueKey('card-v2')))
          .width;
      await tester.tap(find.byKey(const ValueKey('view-list')));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const ValueKey('card-v2'))).width,
        greaterThan(gridWidth),
      );
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('card-v2'))).dy,
        isNot(tester.getTopLeft(find.byKey(const ValueKey('card-v1'))).dy),
      );
      expect(find.text('Coach Arjun'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // a venue (v2) with a programme in each of two sports: one card, a chip per sport
    const tennisAtAce = CoachingListing(
      programId: 'p4',
      name: 'Starters',
      venueId: 'v2',
      venueName: 'Ace Courts',
      venueCity: 'Chennai',
      level: 'Intermediate',
      sport: 'Tennis',
      feeType: 'MONTHLY',
      priceInr: 3500,
      maxCapacity: 6,
      coach: ListedCoach(name: 'Meera', certifications: 'ITF Level 2'),
    );
    const twoSports = {
      inChennai: [beginner, tennisAtAce, advanced],
    };

    testWidgets(
      'Coaching: a venue with programmes in several sports is one card, without a row of sport chips',
      (tester) async {
        lastRoutes.clear();
        await openCoaching(tester, data: twoSports);
        expect(
          find.text('2 Coaching Programs Found'),
          findsOneWidget,
          reason: 'Ace Courts and Smash Arena',
        );
        expect(find.byKey(const ValueKey('card-v2')), findsOneWidget);
        // no sport chips on any card
        expect(
          find.byKey(const ValueKey('coach-sport-v2-Badminton')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('coach-sport-v2-Tennis')),
          findsNothing,
        );
        // Badminton first (the better presented), with its own coach and fee
        expect(find.text('Coach Arjun'), findsOneWidget);
        expect(find.text('Badminton – Beginner Program'), findsOneWidget);
        expect(find.textContaining('₹2,999'), findsOneWidget);
        // View & Enroll opens the venue's enrolment page (where the sport is chosen)
        await tester.tap(find.byKey(const ValueKey('enroll-p1')));
        expect(lastRoutes, [AppRoutes.coachingEnrollPath('v2')]);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Coaching: the sport picked in the search card selects the sport on the card',
      (tester) async {
        await openCoaching(tester, data: twoSports);
        await tester.tap(find.byKey(const ValueKey('sport-dropdown')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('sport-Tennis')));
        await tester.pumpAndSettle();
        // Tennis: Ace Courts (Starters) and Smash Arena (Advanced)
        expect(find.text('2 Coaching Programs Found'), findsOneWidget);
        expect(find.text('Coach Meera'), findsOneWidget);
        expect(find.text('Tennis – Starters'), findsOneWidget);
        expect(find.text('Coach Arjun'), findsNothing);
      },
    );

    testWidgets('Coaching cards in a row are the same height', (tester) async {
      await openCoaching(tester);
      final heights = [
        for (final id in ['v2', 'v1', 'v3'])
          tester.getSize(find.byKey(ValueKey('card-$id'))).height,
      ];
      expect(heights[1], heights[0]);
      expect(heights[2], heights[0]);
    });

    testWidgets(
      'Coaching on a phone: stacked card, Filters sheet, no overflow',
      (tester) async {
        await openCoaching(tester, size: const Size(390, 844));
        expect(
          find.byKey(const ValueKey('discover-search-button')),
          findsNothing,
        );
        expect(find.text('Coach Arjun'), findsOneWidget);
        await tester.ensureVisible(find.byKey(const ValueKey('open-filters')));
        await tester.tap(find.byKey(const ValueKey('open-filters')));
        await tester.pumpAndSettle();
        expect(find.text('Coaching Level'), findsOneWidget);
        await tapVisible(
          tester,
          find.byKey(const ValueKey('filter-type-individual')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('apply-filters')));
        await tester.pumpAndSettle();
        expect(find.text('Filters (1)'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('Coaching on a small phone with large text does not overflow', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.4;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await openCoaching(tester, size: const Size(320, 640));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'Coaching still lists the venues when only the older venue list is available',
      (tester) async {
        await openCoaching(tester, data: const {});
        // ace has the programme name "Juniors" and a lowest price of ₹1,200, no coach
        expect(find.text('1 Coaching Program Found'), findsOneWidget);
        expect(find.text('Cricket – Juniors'), findsOneWidget);
        expect(find.textContaining('₹1,200'), findsOneWidget);
        expect(find.text('Coach Details are not available'), findsOneWidget);
      },
    );

    test('coaching listings: coach labels, titles, places and filters', () {
      expect(beginner.coach!.experienceLabel, '5+ Years Experience');
      expect(beginner.coach!.ratingLabel, '4.9');
      expect(
        const ListedCoach(name: 'X', experienceYears: 0.5).experienceLabel,
        isNull,
      );
      expect(const ListedCoach(name: 'X', rating: 0).ratingLabel, isNull);
      expect(const ListedCoach(name: 'Coach Divya').initials, 'D');
      expect(const ListedCoach(name: 'Arjun Kumar').initials, 'AK');
      expect(beginner.title, 'Badminton – Beginner Program');
      expect(
        const CoachingListing(
          programId: 'a',
          name: 'Badminton Basics',
          venueId: 'v',
          venueName: 'V',
          sport: 'Badminton',
        ).title,
        'Badminton Basics',
      );
      expect(advanced.venuePlace, 'Adyar, Chennai');
      expect(beginner.venuePlace, 'Chennai');
      expect(advanced.typeLabel, 'Individual');
      final parsed = CoachingListing.fromJson({
        'programId': 'p9',
        'name': 'Adult',
        'level': 'Intermediate',
        'sport': 'Badminton',
        'programType': 'GROUP',
        'feeType': 'MONTHLY',
        'priceMinor': 250000,
        'maxCapacity': 6,
        'batches': [
          {
            'startTime': '06:30:00',
            'endTime': '07:30:00',
            'daysOfWeek': [1, 3],
          },
        ],
        'coach': {
          'name': 'Vignesh',
          'rating': 4.9,
          'experienceYears': 6.0,
          'certifications': 'National Level Player',
        },
        'venue': {
          'id': 'v3',
          'name': 'Smash Court',
          'area': 'Velachery',
          'city': 'Chennai',
          'verified': true,
        },
      });
      expect(parsed.priceInr, 2500);
      expect(parsed.isMonthly, isTrue);
      expect(parsed.batches.single.startHour, 6.5);
      expect(parsed.batches.single.days, {1, 3});
      expect(parsed.venueVerified, isTrue);
      expect(parsed.coach!.headline, 'National Level Player');

      List<String> ids(CoachingFilters f) => applyCoachingFilters([
        beginner,
        advanced,
        noCoach,
      ], f).map((p) => p.programId).toList();
      expect(ids(const CoachingFilters()), [
        'p1',
        'p2',
        'p3',
      ], reason: 'coach + rating + description first');
      expect(ids(const CoachingFilters(levels: {CoachingLevel.beginner})), [
        'p1',
        'p3',
      ]);
      expect(ids(const CoachingFilters(types: {CoachingType.individual})), [
        'p2',
      ]);
      expect(ids(const CoachingFilters(time: TimeSlot.evening)), ['p2']);
      expect(ids(const CoachingFilters(days: DaysPick.weekdays)), ['p1']);
      expect(ids(const CoachingFilters(days: DaysPick.weekends)), ['p2']);
      expect(ids(const CoachingFilters(query: 'divya')), ['p2']);
      expect(ids(const CoachingFilters(sport: 'badminton')), ['p1']);
      expect(
        const CoachingFilters(
          levels: {CoachingLevel.beginner},
          days: DaysPick.weekends,
          view: VenueView.list,
        ).activeCount,
        2,
      );
      expect(
        const CoachingFilters(
          levels: {CoachingLevel.beginner},
          view: VenueView.list,
        ).cleared().view,
        VenueView.list,
      );
      expect(coachingSports([beginner, advanced, noCoach]), [
        'Badminton',
        'Tennis',
      ]);
    });

    testWidgets('a city with venues but none with plans says so', (
      tester,
    ) async {
      await pumpApp(
        tester,
        () => Scaffold(
          body: playerPageForRoute(AppRoutes.memberships, embedded: true),
        ),
        city: inChennai,
        venues: {
          inChennai: {
            VenueKind.venues: [smash],
          },
        },
      );
      expect(find.byKey(const ValueKey('no-venues')), findsOneWidget);
      expect(find.text('No memberships in Chennai yet'), findsOneWidget);
      expect(find.textContaining('membership plan'), findsOneWidget);
    });

    testWidgets('Coaching with none says so', (tester) async {
      await pumpApp(
        tester,
        () => Scaffold(
          body: playerPageForRoute(AppRoutes.coaching, embedded: true),
        ),
      );
      expect(find.text('No coaching in Bangalore yet'), findsOneWidget);
    });

    testWidgets('on a phone the page opens on its own with a back button', (
      tester,
    ) async {
      await pumpApp(
        tester,
        () => playerPageForRoute(AppRoutes.memberships),
        city: inChennai,
      );
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.textContaining('Smash Arena'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('brand bar pages on the web', () {
    testWidgets('Memberships is in the brand bar', (tester) async {
      await pumpApp(
        tester,
        () => const PlayerShell(),
        size: const Size(1600, 800),
      );
      expect(
        find.descendant(
          of: find.byType(Pressable),
          matching: find.text('Memberships'),
        ),
        findsWidgets,
      );
      expect(
        find.descendant(
          of: find.byType(Pressable),
          matching: find.text('Venues'),
        ),
        findsWidgets,
      );
      expect(
        find.descendant(
          of: find.byType(Pressable),
          matching: find.text('Coaching'),
        ),
        findsWidgets,
      );
    });

    for (final label in ['Venues', 'Coaching']) {
      testWidgets(
        '$label opens inside the page (no back button), title top left, message centred when empty',
        (tester) async {
          await pumpApp(
            tester,
            () => const PlayerShell(),
            size: const Size(1600, 800),
          );
          await tester.tap(
            find
                .descendant(
                  of: find.byType(Pressable),
                  matching: find.text(label),
                )
                .first,
          );
          await tester.pumpAndSettle();
          expect(find.byType(AppBar), findsNothing);
          expect(find.byType(BackButton), findsNothing);
          expect(find.byKey(const ValueKey('no-venues')), findsOneWidget);
          final message = tester.getCenter(
            find.byKey(const ValueKey('no-venues')),
          );
          expect((message.dx - 800).abs(), lessThan(2));
        },
      );
    }

    testWidgets(
      'Tournaments says none have been created yet (they live in a separate app)',
      (tester) async {
        await pumpApp(
          tester,
          () => const PlayerShell(),
          size: const Size(1600, 800),
        );
        await tester.tap(
          find
              .descendant(
                of: find.byType(Pressable),
                matching: find.text('Tournaments'),
              )
              .first,
        );
        await tester.pumpAndSettle();
        expect(find.byType(AppBar), findsNothing);
        expect(
          find.textContaining('No tournaments have been created yet'),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('no-venues')), findsNothing);
      },
    );

    testWidgets(
      'Find a Court on the web home opens the Venues page inside the page, no back button',
      (tester) async {
        await pumpApp(
          tester,
          () => const PlayerShell(),
          size: const Size(1600, 800),
        );
        await tester.tap(find.text('Find a Court'));
        await tester.pumpAndSettle();
        expect(find.byType(AppBar), findsNothing);
        expect(find.byType(BackButton), findsNothing);
        // the same page as Venues, not a "coming soon" placeholder
        expect(find.textContaining('Discover Sports'), findsOneWidget);
        expect(find.text('Coming soon'), findsNothing);
        expect(find.text('Guest Court Booking'), findsNothing);
        expect(
          find.byKey(const ValueKey('no-venues')),
          findsOneWidget,
          reason: 'no venues in the default city',
        );
      },
    );

    testWidgets(
      'Guest Booking lists the city\'s venues like the Venues page, and a venue opens its page',
      (tester) async {
        await pumpApp(
          tester,
          () => const PlayerShell(),
          size: const Size(1600, 900),
          city: inChennai,
        );
        await tester.tap(find.text('Find a Court'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Discover Sports'), findsOneWidget);
        expect(find.byKey(const ValueKey('discover-search')), findsOneWidget);
        expect(find.byKey(const ValueKey('sport-dropdown')), findsOneWidget);
        expect(find.text('2 Venues Found'), findsOneWidget);
        expect(find.text('Smash Arena'), findsOneWidget);
        expect(find.text('Ace Courts'), findsOneWidget);
        expect(find.byKey(const ValueKey('view-book-v1')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('pages that depend on the picked city', () {
    for (final route in [AppRoutes.guestBooking, AppRoutes.search]) {
      testWidgets('$route shows the no-venues message when the city has none', (
        tester,
      ) async {
        await pumpApp(tester, () => ComingSoonPage.forRoute(route));
        expect(find.byKey(const ValueKey('no-venues')), findsOneWidget);
        expect(find.text('No venues in Bangalore yet'), findsOneWidget);
      });

      testWidgets('$route shows its own content when the city has venues', (
        tester,
      ) async {
        await pumpApp(
          tester,
          () => ComingSoonPage.forRoute(route),
          city: inChennai,
        );
        expect(find.byKey(const ValueKey('no-venues')), findsNothing);
        expect(find.text('2 venues in Chennai'), findsOneWidget);
      });
    }

    for (final route in [
      AppRoutes.login,
      AppRoutes.notifications,
      AppRoutes.howItWorks,
      AppRoutes.myMembership,
      AppRoutes.myCoaching,
      AppRoutes.tournaments,
    ]) {
      testWidgets('$route does not depend on the city', (tester) async {
        await pumpApp(tester, () => ComingSoonPage.forRoute(route));
        expect(find.byKey(const ValueKey('no-venues')), findsNothing);
      });
    }
  });

  group('a refreshed page stays on its page (the address picks it, Home is only the default)', () {
    testWidgets('web: /coaching reopens the Coaching page, not Home', (
      tester,
    ) async {
      await pumpApp(
        tester,
        () => const PlayerShell(initialRoute: AppRoutes.coaching),
        size: const Size(1600, 800),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('no-venues')), findsOneWidget);
    });

    testWidgets('web: /explore reopens the Venues tab', (tester) async {
      await pumpApp(
        tester,
        () => const PlayerShell(initialRoute: AppRoutes.explore),
        size: const Size(1600, 800),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DiscoverVenuesPage), findsOneWidget);
    });

    testWidgets(
      'web: /enroll/<venue> reopens that venue\'s enrolment page inside the shell',
      (tester) async {
        await pumpApp(
          tester,
          () => PlayerShell(initialRoute: AppRoutes.enrollPath('v1')),
          size: const Size(1600, 800),
        );
        await tester.pumpAndSettle();
        expect(find.byType(EnrollMembershipPage), findsOneWidget);
      },
    );

    testWidgets(
      'web: /coaching-enroll/<venue> reopens the coaching page inside the shell',
      (tester) async {
        await pumpApp(
          tester,
          () => PlayerShell(initialRoute: AppRoutes.coachingEnrollPath('v1')),
          size: const Size(1600, 800),
        );
        await tester.pumpAndSettle();
        expect(find.byType(CoachingEnrollPage), findsOneWidget);
      },
    );

    testWidgets(
      'phone: /coaching-enroll/<venue> opens the page over Home, so Back still goes Home',
      (tester) async {
        await pumpApp(
          tester,
          () => PlayerShell(initialRoute: AppRoutes.coachingEnrollPath('v1')),
        );
        await tester.pumpAndSettle();
        expect(find.byType(CoachingEnrollPage), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(CoachingEnrollPage), findsNothing);
      },
    );

    test('which addresses the shell owns', () {
      for (final r in [
        '/explore',
        '/my-coaching',
        '/bookings',
        '/profile',
        '/coaching',
        '/venue/v1',
        '/book/v1',
        '/enroll/v1',
        '/coaching-enroll/v1',
      ]) {
        expect(AppRoutes.isShellRoute(r), isTrue, reason: r);
      }
      for (final r in ['/', '/login', '/welcome', '/venue']) {
        expect(AppRoutes.isShellRoute(r), isFalse, reason: r);
      }
    });
  });
}
