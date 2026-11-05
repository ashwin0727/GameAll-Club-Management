import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gameall_player/core/routing/app_routes.dart';
import 'package:gameall_player/core/theme/app_theme.dart';
import 'package:gameall_player/core/widgets/pressable.dart';
import 'package:gameall_player/core/utils/external_links.dart';
import 'package:gameall_player/features/player_home/application/player_home_controller.dart';
import 'package:gameall_player/features/player_home/data/player_home_repository.dart';
import 'package:gameall_player/features/player_home/domain/player_home_models.dart';
import 'package:gameall_player/features/player_home/presentation/widgets/player_bottom_nav.dart';
import 'package:gameall_player/features/shell/player_shell.dart';
import 'package:gameall_player/features/venues/application/venue_filters.dart';
import 'package:gameall_player/features/venues/application/venues_providers.dart';
import 'package:gameall_player/features/venues/data/venue_repository.dart';
import 'package:gameall_player/features/venues/domain/venue.dart';
import 'package:gameall_player/features/venues/domain/venue_detail.dart';
import 'package:gameall_player/features/venues/presentation/guest_booking_page.dart';
import 'package:gameall_player/features/venues/presentation/venue_detail_page.dart';

Map<String, dynamic> _json([Map<String, dynamic> extra = const {}]) => {
      'id': 'v1',
      'name': 'Champz Turf',
      'city': 'Chennai',
      'area': 'Iyyapanthangal',
      'address': '12 Main Road, Iyyapanthangal, Chennai',
      'phone': '9876500000',
      'description': 'Premium courts with coaching and flexible membership plans.',
      'photos': <String>[],
      'venueType': 'INDOOR',
      'amenities': {'parking': true, 'changingRooms': true, 'toilets': false, 'cafeteria': true, 'equipmentRental': false},
      'locationVerified': true,
      'locationUrl': 'https://maps.app.goo.gl/x',
      'courtCount': 3,
      'minCourtPriceInr': 350,
      'sports': [
        {'facilitySportId': 's1', 'name': 'Badminton'},
        {'facilitySportId': 's2', 'name': 'Football'},
      ],
      'courts': [
        {'id': 'c1', 'name': 'Court 1', 'facilitySportId': 's1'},
      ],
      'hours': {'opens': '06:00', 'closes': '23:00', 'open24h': false},
      'memberships': {
        'plans': [
          {'name': 'Gold', 'priceInr': 2999, 'durationDays': 30},
          {'name': 'Silver', 'priceInr': 3999, 'durationDays': 90},
        ],
      },
      'coaching': {
        'programs': [
          {'name': 'Juniors', 'level': 'Beginner', 'priceInr': 1500},
        ],
      },
      ...extra,
    };

VenueDetail _detail([Map<String, dynamic> extra = const {}]) => VenueDetail.fromJson(_json(extra));

class _Repo extends VenueRepository {
  _Repo({this.detail, this.slots = const [], this.list = const []});
  final VenueDetail? detail;
  final List<CourtSlots> slots;
  final List<Venue> list;
  final queries = <AvailabilityQuery>[];

  @override
  Future<List<Venue>> listForLocation(String location, {VenueKind kind = VenueKind.venues}) async => list;

  @override
  Future<VenueDetail?> getVenue(String venueId) async => venueId == detail?.id ? detail : null;

  @override
  Future<List<CourtSlots>> availability(AvailabilityQuery query) async {
    queries.add(query);
    return slots;
  }
}

class _FlakyRepo extends _Repo {
  _FlakyRepo({super.detail, super.slots});
  bool failing = true;

  @override
  Future<List<CourtSlots>> availability(AvailabilityQuery query) async {
    if (failing) throw Exception('boom');
    return super.availability(query);
  }
}

class _Home implements PlayerHomeRepository {
  @override
  Future<PlayerHomeData> load() async => const PlayerHomeData.guest();
}

List<CourtSlots> _slots() => [
      CourtSlots(courtId: 'c1', courtName: 'Court 1', slots: [for (final h in [18, 19, 20, 21]) CourtSlot(start: DateTime(2030, 1, 1, h), end: DateTime(2030, 1, 1, h + 1), available: h != 19, priceMinor: 40000)]),
      CourtSlots(courtId: 'c2', courtName: 'Court 2', slots: [CourtSlot(start: DateTime(2030, 1, 1, 9), end: DateTime(2030, 1, 1, 10), available: true)]),
    ];

Future<(_Repo, List<Uri>)> _pump(WidgetTester tester, Widget home, {_Repo? repo, Size size = const Size(1640, 1100)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final r = repo ?? _Repo(detail: _detail(), slots: _slots());
  final opened = <Uri>[];
  final c = ProviderContainer(overrides: [
    venueRepositoryProvider.overrideWithValue(r),
    playerHomeRepositoryProvider.overrideWithValue(_Home()),
    linkOpenerProvider.overrideWithValue((uri) async {
      opened.add(uri);
      return true;
    }),
  ]);
  addTearDown(c.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(container: c, child: MaterialApp(theme: AppTheme.dark(), home: home)));
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
  addTearDown(() async => tester.pumpWidget(const SizedBox()));
  return (r, opened);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('VenueDetail', () {
    test('reads the venue page answer', () {
      final d = _detail();
      expect(d.place, 'Iyyapanthangal, Chennai');
      expect(d.hoursLabel, '6:00 AM - 11:00 PM');
      expect(d.hoursShort, '6 AM - 11 PM');
      expect(d.cheapestPlan?.priceInr, 2999);
      expect(d.cheapestPlan?.period, 'month');
      expect(d.plans.last.period, '3 months');
      expect(d.cheapestProgramPrice, 1500);
      expect(d.amenities.labels, ['Free Parking', 'Changing Rooms', 'Cafeteria']);
      expect(d.venueType, VenueType.indoor);
      expect(d.courts.single.name, 'Court 1');
    });

    test('a venue with no approved photo falls back to its own picture, and a repeated city is shown once', () {
      expect(_detail({'heroImageUrl': 'https://img/h.jpg'}).photos, ['https://img/h.jpg']);
      expect(_detail({'photos': ['a', 'b'], 'heroImageUrl': 'https://img/h.jpg'}).photos, ['a', 'b']);
      expect(_detail({'area': 'Chennai'}).place, 'Chennai');
    });

    test('hours: 24 hours, none, and a zero price is not a price', () {
      expect(_detail({'hours': {'opens': null, 'closes': null, 'open24h': true}}).hoursLabel, 'Open 24 hours');
      expect(_detail({'hours': null}).hoursLabel, isNull);
      expect(_detail({'minCourtPriceInr': 0}).minCourtPriceInr, isNull);
      expect(_detail({'coaching': {'programs': [{'name': 'x', 'priceInr': null}]}}).cheapestProgramPrice, isNull);
    });

    test('players: 8 on a badminton / tennis / pickleball court, 15 on cricket / football, rounded down to ten, never under 10+', () {
      VenueDetail with_(Map<String, int> courtsBySport) {
        final names = courtsBySport.keys.toList();
        return _detail({
          'sports': [for (var i = 0; i < names.length; i++) {'facilitySportId': 's$i', 'name': names[i]}],
          'courts': [
            for (var i = 0; i < names.length; i++)
              for (var k = 0; k < courtsBySport[names[i]]!; k++) {'id': 'c$i-$k', 'name': 'Court $k', 'facilitySportId': 's$i'},
          ],
        });
      }

      expect(with_({'Badminton': 1}).playersLabel, '10+ Players', reason: '8 players still reads 10+');
      expect(with_({'Badminton': 2}).playersLabel, '10+ Players', reason: '16');
      expect(with_({'Badminton': 3}).playersLabel, '20+ Players', reason: '24');
      expect(with_({'Badminton': 2, 'Football': 1}).playersLabel, '30+ Players', reason: '16 + 15 = 31');
      expect(with_({'Cricket': 1, 'Tennis': 1}).playersLabel, '20+ Players', reason: '15 + 8 = 23');
      expect(with_({'Pickleball': 5}).playersLabel, '40+ Players', reason: '40');
      expect(with_({'Badminton': 1, 'Cricket': 2, 'Football': 1}).playersLabel, '50+ Players', reason: '8 + 30 + 15 = 53');
      expect(with_({'Cricket': 3}).playersLabel, '40+ Players', reason: '45');
      expect(with_({'Football': 2, 'Badminton': 1}).playersLabel, '30+ Players', reason: '38');
      expect(_detail({'courts': [], 'sports': []}).playersLabel, isNull);
    });

    test('the availability query compares by day, not by time of day', () {
      expect(AvailabilityQuery('v', 's', DateTime(2030, 1, 1, 9)), AvailabilityQuery('v', 's', DateTime(2030, 1, 1, 22)));
      expect(AvailabilityQuery('v', 's', DateTime(2030, 1, 1)), isNot(AvailabilityQuery('v', 's', DateTime(2030, 1, 2))));
      expect(AppRoutes.venueIdOf(AppRoutes.venuePath('abc')), 'abc');
      expect(AppRoutes.venueIdOf('/venue'), isNull);
      expect(AppRoutes.venueIdOf('/memberships'), isNull);
    });
  });

  group('venue page on the web', () {
    final routes = <String>[];
    setUp(routes.clear);
    Widget page() => VenueDetailPage(venueId: 'v1', onNavigate: routes.add, embedded: true);

    testWidgets('title, verified badge, place, chips, description and the three actions', (tester) async {
      await _pump(tester, Scaffold(body: page()));
      expect(find.text('Champz Turf'), findsWidgets);
      expect(find.byKey(const ValueKey('venue-verified')), findsOneWidget);
      expect(find.text('Iyyapanthangal, Chennai'), findsOneWidget);
      for (final chip in ['Badminton', 'Football', 'Indoor']) {
        expect(find.text(chip), findsWidgets, reason: chip);
      }
      expect(find.byKey(const ValueKey('venue-description')), findsOneWidget);
      for (final a in ['action-book', 'action-memberships', 'action-coaching']) {
        expect(find.byKey(ValueKey(a)), findsOneWidget, reason: a);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('the stats bar: courts, hours and the facilities that are on', (tester) async {
      await _pump(tester, Scaffold(body: page()));
      expect(find.text('3 Courts'), findsOneWidget);
      expect(find.text('6:00 AM - 11:00 PM'), findsOneWidget);
      // one badminton court (8 players) reads 10+
      expect(find.byKey(const ValueKey('stat-players')), findsOneWidget);
      expect(find.text('10+ Players'), findsOneWidget);
      for (final a in ['Free Parking', 'Changing Rooms', 'Cafeteria']) {
        expect(find.text(a), findsOneWidget, reason: a);
      }
      expect(find.text('Toilets / Rest Room'), findsNothing, reason: 'that amenity is off');
      await tester.ensureVisible(find.byKey(const ValueKey('view-all-facilities')));
      await tester.tap(find.byKey(const ValueKey('view-all-facilities')));
      await tester.pumpAndSettle();
      expect(find.text('Facilities'), findsOneWidget);
      expect(find.text('Equipment Rental'), findsOneWidget);
    });

    testWidgets('Explore at this venue: plans and programs with their prices, each opening its page', (tester) async {
      await _pump(tester, Scaffold(body: page()));
      expect(find.text('Explore at this venue'), findsOneWidget);
      expect(find.text('Plans from ₹2,999 / month'), findsOneWidget);
      expect(find.text('Programs from ₹1,500'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('explore-memberships')));
      await tester.tap(find.byKey(const ValueKey('explore-memberships')));
      await tester.tap(find.byKey(const ValueKey('explore-coaching')));
      expect(routes, [AppRoutes.enrollPath('v1'), AppRoutes.coaching]);
    });

    testWidgets('has no breadcrumb row above the title', (tester) async {
      await _pump(tester, Scaffold(body: page()));
      expect(find.byKey(const ValueKey('crumb-venues')), findsNothing);
      expect(find.byIcon(Icons.home_outlined), findsNothing);
    });

    testWidgets('a venue with no plans, no programs, no verification and no amenities shows only what it has', (tester) async {
      final bare = _detail({'memberships': {'plans': []}, 'coaching': {'programs': []}, 'locationVerified': false, 'locationUrl': null, 'amenities': {}});
      await _pump(tester, Scaffold(body: page()), repo: _Repo(detail: bare, slots: _slots()));
      expect(find.byKey(const ValueKey('venue-verified')), findsNothing);
      expect(find.text('Explore at this venue'), findsNothing);
      expect(find.byKey(const ValueKey('action-memberships')), findsNothing);
      expect(find.byKey(const ValueKey('action-coaching')), findsNothing);
      expect(find.byKey(const ValueKey('view-all-facilities')), findsNothing);
      expect(find.byKey(const ValueKey('action-book')), findsOneWidget);
    });

    testWidgets('photos: arrows and a thumbnail column when there are several', (tester) async {
      final photos = _detail({'photos': ['https://invalid.test/1.jpg', 'https://invalid.test/2.jpg', 'https://invalid.test/3.jpg']});
      await _pump(tester, Scaffold(body: page()), repo: _Repo(detail: photos, slots: _slots()));
      expect(find.byKey(const ValueKey('gallery-pages')), findsOneWidget);
      expect(find.byKey(const ValueKey('gallery-next')), findsOneWidget);
      expect(find.byKey(const ValueKey('gallery-thumb-2')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('gallery-next')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('the heart saves the venue', (tester) async {
      final (_, _) = await _pump(tester, Scaffold(body: page()));
      final container = ProviderScope.containerOf(tester.element(find.byType(VenueDetailPage)));
      await tester.tap(find.byKey(const ValueKey('gallery-heart')));
      await tester.pumpAndSettle();
      expect(container.read(savedVenuesProvider), {'v1'});
    });

    testWidgets('a venue that is not open says so, and offers the venues', (tester) async {
      await _pump(tester, Scaffold(body: VenueDetailPage(venueId: 'nope', onNavigate: routes.add, embedded: true)));
      expect(find.byKey(const ValueKey('venue-missing')), findsOneWidget);
      await tester.tap(find.text('See venues'));
      expect(routes, [AppRoutes.explore]);
    });
  });

  group('Guest Booking page', () {
    final routes = <String>[];
    setUp(routes.clear);
    // 1 January 2030, 9 am: the page's idea of "today"
    final now = DateTime(2030, 1, 1, 9);
    Widget page({bool embedded = true}) => GuestBookingPage(venueId: 'v1', onNavigate: routes.add, embedded: embedded, now: now);

    testWidgets('the venue, the four steps and the summary, laid out as in the design', (tester) async {
      await _pump(tester, Scaffold(body: page()));
      expect(find.text('Champz Turf'), findsWidgets);
      expect(find.text('Iyyapanthangal, Chennai'), findsOneWidget);
      expect(find.text('3 Courts'), findsOneWidget);
      expect(find.text('6:00 AM - 11:00 PM'), findsOneWidget);
      for (final t in ['Select Sport', 'Select Date', 'Select Court', 'Select Time Slot', 'Booking Summary', 'Amount']) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      for (final n in ['1', '2', '3', '4']) {
        expect(find.text(n), findsOneWidget, reason: 'step $n');
      }
      expect(find.byKey(const ValueKey('book-sport-Badminton')), findsOneWidget);
      expect(find.byKey(const ValueKey('book-sport-Football')), findsOneWidget);
      // five days from today, and a calendar for any other
      for (var d = 1; d <= 5; d++) {
        expect(find.byKey(ValueKey('book-date-2030-1-$d')), findsOneWidget, reason: 'day $d');
      }
      expect(find.byKey(const ValueKey('book-calendar')), findsOneWidget);
      expect(find.byKey(const ValueKey('book-court-Court 1')), findsOneWidget);
      expect(find.byKey(const ValueKey('book-court-Court 2')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('booked hours are shown but cannot be chosen; a free hour fills in the summary and the price', (tester) async {
      final (repo, opened) = await _pump(tester, Scaffold(body: page()));
      expect(repo.queries.single.sportId, 's1');
      expect(find.byKey(const ValueKey('book-slot-7:00 PM')), findsOneWidget, reason: 'shown, greyed out');
      expect(find.text('—'), findsWidgets);

      await tester.ensureVisible(find.byKey(const ValueKey('book-slot-7:00 PM')));
      await tester.tap(find.byKey(const ValueKey('book-slot-7:00 PM')));
      await tester.pump();
      expect(find.byKey(const ValueKey('summary-time')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const ValueKey('summary-time'))).data, '—', reason: 'a booked hour is not selectable');

      await tester.ensureVisible(find.byKey(const ValueKey('book-slot-8:00 PM')));
      await tester.tap(find.byKey(const ValueKey('book-slot-8:00 PM')));
      await tester.pump();
      expect(tester.widget<Text>(find.byKey(const ValueKey('summary-sport'))).data, 'Badminton');
      expect(tester.widget<Text>(find.byKey(const ValueKey('summary-court'))).data, 'Court 1');
      expect(tester.widget<Text>(find.byKey(const ValueKey('summary-date'))).data, 'Tue, 1 Jan 2030');
      expect(tester.widget<Text>(find.byKey(const ValueKey('summary-time'))).data, '8:00 PM – 9:00 PM (1 hr)');
      expect(tester.widget<Text>(find.byKey(const ValueKey('summary-amount'))).data, '₹400');

      await tester.ensureVisible(find.byKey(const ValueKey('book-now')));
      await tester.tap(find.byKey(const ValueKey('book-now')));
      await tester.pump();
      expect(opened.single.toString(), 'https://club.gameall.co/book/v1');
    });

    testWidgets('several hours can be chosen: hours in a row merge, separate ones are listed, the price adds up, and a second tap takes one off', (tester) async {
      await _pump(tester, Scaffold(body: page()));
      Future<void> tap(String hour) async {
        await tester.ensureVisible(find.byKey(ValueKey('book-slot-$hour')));
        await tester.tap(find.byKey(ValueKey('book-slot-$hour')));
        await tester.pump();
      }

      String text(String key) => tester.widget<Text>(find.byKey(ValueKey(key))).data!;
      await tap('8:00 PM');
      await tap('9:00 PM');
      expect(text('summary-time'), '8:00 PM – 10:00 PM (2 hr)');
      expect(text('summary-amount'), '₹800');
      expect(find.text('Tap more than one hour to book them together.'), findsOneWidget);

      await tap('6:00 PM');
      expect(text('summary-time'), '6:00 PM – 7:00 PM, 8:00 PM – 10:00 PM (3 hr)');
      expect(text('summary-amount'), '₹1,200');

      await tap('8:00 PM'); // take one off
      expect(text('summary-time'), '6:00 PM – 7:00 PM, 9:00 PM – 10:00 PM (2 hr)');
      await tap('7:00 PM'); // a booked hour is still not selectable
      expect(text('summary-time'), '6:00 PM – 7:00 PM, 9:00 PM – 10:00 PM (2 hr)');

      await tap('6:00 PM');
      await tap('9:00 PM');
      expect(text('summary-time'), '—', reason: 'with nothing chosen Book Now waits again');
    });

    testWidgets('switching court or day starts the choice again', (tester) async {
      await _pump(tester, Scaffold(body: page()));
      await tester.ensureVisible(find.byKey(const ValueKey('book-slot-8:00 PM')));
      await tester.tap(find.byKey(const ValueKey('book-slot-8:00 PM')));
      await tester.tap(find.byKey(const ValueKey('book-slot-9:00 PM')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('book-court-Court 2')));
      await tester.tap(find.byKey(const ValueKey('book-court-Court 2')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const ValueKey('summary-time'))).data, '—');
    });

    testWidgets('Book Now waits for a time slot', (tester) async {
      final (_, opened) = await _pump(tester, Scaffold(body: page()));
      await tester.ensureVisible(find.byKey(const ValueKey('book-now')));
      await tester.tap(find.byKey(const ValueKey('book-now')));
      await tester.pump();
      expect(opened, isEmpty);
    });

    testWidgets('another day asks for that day; another court shows its own hours; another sport asks again', (tester) async {
      final (repo, _) = await _pump(tester, Scaffold(body: page()));
      await tester.tap(find.byKey(const ValueKey('book-date-2030-1-3')));
      await tester.pumpAndSettle();
      expect(repo.queries.last.dayKey, '2030-01-03');

      await tester.ensureVisible(find.byKey(const ValueKey('book-court-Court 2')));
      await tester.tap(find.byKey(const ValueKey('book-court-Court 2')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('book-slot-9:00 AM')), findsOneWidget);
      expect(find.byKey(const ValueKey('book-slot-6:00 PM')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('book-sport-Football')));
      await tester.pumpAndSettle();
      expect(repo.queries.last.sportId, 's2');
    });

    testWidgets('changing the day clears the chosen hour', (tester) async {
      await _pump(tester, Scaffold(body: page()));
      await tester.ensureVisible(find.byKey(const ValueKey('book-slot-8:00 PM')));
      await tester.tap(find.byKey(const ValueKey('book-slot-8:00 PM')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('book-date-2030-1-2')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const ValueKey('summary-time'))).data, '—');
    });

    testWidgets('the breadcrumb goes back to Venues or to this venue', (tester) async {
      await _pump(tester, Scaffold(body: page()));
      expect(find.text('Book a Court'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('crumb-venues')));
      await tester.tap(find.byKey(const ValueKey('crumb-venue')));
      expect(routes, [AppRoutes.explore, AppRoutes.venuePath('v1')]);
    });

    testWidgets('a venue with a single sport skips the sport step; one with no courts says so', (tester) async {
      final one = _detail({'sports': [{'facilitySportId': 's1', 'name': 'Badminton'}]});
      await _pump(tester, Scaffold(body: page()), repo: _Repo(detail: one, slots: _slots()));
      expect(find.text('Select Sport'), findsNothing);
      expect(find.text('Select Date'), findsOneWidget);
    });

    testWidgets('a venue with no courts open for booking says so', (tester) async {
      final none = _detail({'sports': [], 'courts': [], 'courtCount': 0});
      await _pump(tester, Scaffold(body: page()), repo: _Repo(detail: none));
      expect(find.byKey(const ValueKey('book-none')), findsOneWidget);
    });

    testWidgets('a day with no slots says so', (tester) async {
      await _pump(tester, Scaffold(body: page()), repo: _Repo(detail: _detail(), slots: const []));
      expect(find.byKey(const ValueKey('book-no-slots')), findsOneWidget);
    });

    testWidgets('a venue that is not open says so', (tester) async {
      await _pump(tester, Scaffold(body: GuestBookingPage(venueId: 'nope', onNavigate: routes.add, embedded: true)));
      expect(find.byKey(const ValueKey('booking-missing')), findsOneWidget);
      await tester.tap(find.text('See venues'));
      expect(routes, [AppRoutes.explore]);
    });

    testWidgets('phone: four small cards (Sport, Date, Court, Time Slot) and Continue, then the Booking Summary with Book Now', (tester) async {
      final (_, opened) = await _pump(tester, page(embedded: false), size: const Size(390, 1800));
      expect(find.byKey(const ValueKey('booking-back')), findsOneWidget);
      for (final t in ['Sport', 'Date', 'Court', 'Time Slot', 'Available', 'Booked']) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      expect(find.text('3 Courts'), findsOneWidget);
      expect(find.text('6:00 AM - 11:00 PM'), findsOneWidget);
      // four day chips and the calendar (five on the web)
      for (var d = 1; d <= 4; d++) {
        expect(find.byKey(ValueKey('book-date-2030-1-$d')), findsOneWidget, reason: 'day $d');
      }
      expect(find.byKey(const ValueKey('book-date-2030-1-5')), findsNothing);
      expect(find.byKey(const ValueKey('book-calendar')), findsOneWidget);

      // Continue waits for an hour
      await tester.ensureVisible(find.byKey(const ValueKey('book-continue')));
      await tester.tap(find.byKey(const ValueKey('book-continue')));
      await tester.pump();
      expect(find.text('Booking Summary'), findsNothing);

      await tester.ensureVisible(find.byKey(const ValueKey('book-slot-8:00 PM')));
      await tester.tap(find.byKey(const ValueKey('book-slot-8:00 PM')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('book-slot-9:00 PM')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('book-continue')));
      await tester.tap(find.byKey(const ValueKey('book-continue')));
      await tester.pumpAndSettle();

      expect(find.text('Booking Summary'), findsWidgets);
      expect(find.text('Review your booking details'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const ValueKey('summary-sport'))).data, 'Badminton');
      expect(tester.widget<Text>(find.byKey(const ValueKey('summary-court'))).data, 'Court 1');
      expect(tester.widget<Text>(find.byKey(const ValueKey('summary-date'))).data, 'Tue, 1 Jan 2030');
      expect(tester.widget<Text>(find.byKey(const ValueKey('summary-time'))).data, '8:00 PM – 10:00 PM (2 hr)');
      expect(tester.widget<Text>(find.byKey(const ValueKey('summary-amount'))).data, '₹800');
      await tester.ensureVisible(find.byKey(const ValueKey('book-now')));
      await tester.tap(find.byKey(const ValueKey('book-now')));
      await tester.pump();
      expect(opened.single.toString(), 'https://club.gameall.co/book/v1');

      // Back from the summary returns to the steps, with the hour still chosen
      await tester.tap(find.byKey(const ValueKey('booking-back')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('booking-scroll')), findsOneWidget);
      expect(find.byKey(const ValueKey('booking-summary')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('phone: a small screen with large text does not overflow on either screen', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.4;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pump(tester, page(embedded: false), size: const Size(320, 700));
      await tester.dragUntilVisible(find.byKey(const ValueKey('book-slot-8:00 PM')), find.byKey(const ValueKey('booking-scroll')), const Offset(0, -300));
      await tester.tap(find.byKey(const ValueKey('book-slot-8:00 PM')));
      await tester.pump();
      await tester.dragUntilVisible(find.byKey(const ValueKey('book-continue')), find.byKey(const ValueKey('booking-scroll')), const Offset(0, -300));
      await tester.tap(find.byKey(const ValueKey('book-continue')));
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(find.byKey(const ValueKey('book-now')), find.byKey(const ValueKey('booking-summary-scroll')), const Offset(0, -300));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the venue page has no booking panel inside it any more: Book a Court opens this page', (tester) async {
      final r = <String>[];
      await _pump(tester, Scaffold(body: VenueDetailPage(venueId: 'v1', onNavigate: r.add, embedded: true)));
      expect(find.byKey(const ValueKey('book-panel')), findsNothing);
      expect(find.text('Select Time Slot'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('action-book')));
      expect(r, [AppRoutes.bookPath('v1')]);
      expect(AppRoutes.bookVenueIdOf(AppRoutes.bookPath('abc')), 'abc');
      expect(AppRoutes.bookVenueIdOf('/book'), isNull);
      expect(AppRoutes.bookVenueIdOf('/venue/abc'), isNull);
    });
  });

  group('Guest Booking page: hours that fail to load', () {
    testWidgets('shows the problem with a Try again button instead of spinning forever, and loads once it works', (tester) async {
      final repo = _FlakyRepo(detail: _detail(), slots: _slots());
      await _pump(tester, Scaffold(body: GuestBookingPage(venueId: 'v1', onNavigate: (_) {}, embedded: true, now: DateTime(2030, 1, 1, 9))), repo: repo);
      expect(find.byKey(const ValueKey('book-loading')), findsNothing);
      expect(find.byKey(const ValueKey('book-error')), findsOneWidget);
      expect(find.textContaining('boom'), findsOneWidget);
      repo.failing = false;
      await tester.ensureVisible(find.byKey(const ValueKey('book-retry')));
      await tester.tap(find.byKey(const ValueKey('book-retry')));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('book-error')), findsNothing);
      expect(find.byKey(const ValueKey('book-slot-8:00 PM')), findsOneWidget);
    });
  });

  group('venue to booking inside the page (web)', () {
    testWidgets('Book a Court opens the booking page under the brand bar, and the breadcrumb comes back', (tester) async {
      final smash = const Venue(id: 'v1', name: 'Champz Turf', city: 'Chennai', area: 'Iyyapanthangal', sports: ['Badminton'], courtCount: 3, minCourtPriceInr: 350);
      await _pump(tester, const PlayerShell(initialTab: PlayerTab.explore), repo: _Repo(detail: _detail(), slots: _slots(), list: [smash]));
      final container = ProviderScope.containerOf(tester.element(find.byType(PlayerShell)));
      container.read(selectedCityProvider.notifier).select('Chennai, Tamil Nadu');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Champz Turf'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('action-book')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('booking-scroll')), findsOneWidget);
      expect(find.text('Booking Summary'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('crumb-venue')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('venue-title')), findsOneWidget);
      expect(find.byKey(const ValueKey('booking-scroll')), findsNothing);
    });
  });

  group('venue page on a phone', () {
    const phone = Size(390, 1400);
    Widget page() => VenueDetailPage(venueId: 'v1', onNavigate: (_) {});

    testWidgets('verified photo badge, name, place, chips, the three tiles, At a Glance, Facilities and the address', (tester) async {
      await _pump(tester, page(), size: phone);
      expect(find.text('Verified Venue'), findsOneWidget);
      expect(find.text('Champz Turf'), findsOneWidget);
      expect(find.text('Iyyapanthangal, Chennai'), findsOneWidget);
      for (final t in ['tile-book', 'tile-memberships', 'tile-coaching']) {
        expect(find.byKey(ValueKey(t)), findsOneWidget, reason: t);
      }
      expect(find.text('At a Glance'), findsOneWidget);
      expect(find.text('3 Courts'), findsOneWidget);
      expect(find.text('6 AM - 11 PM'), findsOneWidget);
      expect(find.text('10+ Players'), findsOneWidget);
      expect(find.text('Facilities'), findsOneWidget);
      expect(find.text('Free Parking'), findsOneWidget);
      expect(find.byKey(const ValueKey('venue-location')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Open in Maps uses the verified link', (tester) async {
      final (_, opened) = await _pump(tester, page(), size: phone);
      await tester.ensureVisible(find.byKey(const ValueKey('open-maps')));
      await tester.tap(find.byKey(const ValueKey('open-maps')));
      expect(opened.single.toString(), 'https://maps.app.goo.gl/x');
    });

    testWidgets('an unverified venue shows the address but no Maps button and no badge', (tester) async {
      final unverified = _detail({'locationVerified': false, 'locationUrl': null});
      await _pump(tester, page(), repo: _Repo(detail: unverified, slots: _slots()), size: phone);
      expect(find.text('Verified Venue'), findsNothing);
      expect(find.byKey(const ValueKey('venue-location')), findsOneWidget);
      expect(find.byKey(const ValueKey('open-maps')), findsNothing);
    });

    testWidgets('Book Court opens its own page; Memberships and Coaching open as tabs', (tester) async {
      final r = <String>[];
      final (_, opened) = await _pump(tester, VenueDetailPage(venueId: 'v1', onNavigate: r.add), size: phone);
      await tester.ensureVisible(find.byKey(const ValueKey('tile-book')));
      await tester.tap(find.byKey(const ValueKey('tile-book')));
      expect(r, [AppRoutes.bookPath('v1')]);

      await tester.ensureVisible(find.byKey(const ValueKey('tile-memberships')));
      await tester.tap(find.byKey(const ValueKey('tile-memberships')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('plans-list')), findsOneWidget);
      expect(find.text('Gold'), findsOneWidget);
      expect(find.text('₹2,999 / month'), findsOneWidget);
      expect(find.text('₹3,999 / 3 months'), findsOneWidget);
      expect(find.byKey(const ValueKey('tab-Book')), findsNothing, reason: 'booking is a page of its own now');

      await tester.tap(find.byKey(const ValueKey('call-venue')));
      expect(opened.single.toString(), 'tel:9876500000');

      await tester.tap(find.byKey(const ValueKey('tab-Coaching')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('programs-list')), findsOneWidget);
      expect(find.text('Juniors'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a small phone with large text does not overflow', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.4;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pump(tester, page(), size: const Size(320, 700));
      await tester.dragUntilVisible(find.byKey(const ValueKey('venue-location')), find.byKey(const ValueKey('venue-scroll')), const Offset(0, -300));
      expect(tester.takeException(), isNull);
    });
  });

  group('from the venues list', () {
    final smash = const Venue(id: 'v1', name: 'Champz Turf', city: 'Chennai', area: 'Iyyapanthangal', sports: ['Badminton'], courtCount: 3, minCourtPriceInr: 350);

    testWidgets('on the web a card opens the venue inside the page, and the Venues link in the brand bar returns to the list', (tester) async {
      final repo = _Repo(detail: _detail(), slots: _slots(), list: [smash]);
      await _pump(tester, const PlayerShell(initialTab: PlayerTab.explore), repo: repo);
      final container = ProviderScope.containerOf(tester.element(find.byType(PlayerShell)));
      container.read(selectedCityProvider.notifier).select('Chennai, Tamil Nadu');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Champz Turf'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('venue-title')), findsOneWidget);
      expect(find.text('Explore at this venue'), findsOneWidget);
      // back to the list from the brand bar's Venues link
      await tester.tap(find.descendant(of: find.byType(Pressable), matching: find.text('Venues')).first);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('venue-title')), findsNothing);
      expect(find.text('1 Venue Found'), findsOneWidget);
    });

    testWidgets('on a phone a card pushes the venue page, and Back returns', (tester) async {
      final repo = _Repo(detail: _detail(), slots: _slots(), list: [smash]);
      await _pump(tester, const PlayerShell(initialTab: PlayerTab.explore), repo: repo, size: const Size(390, 1400));
      final container = ProviderScope.containerOf(tester.element(find.byType(PlayerShell)));
      container.read(selectedCityProvider.notifier).select('Chennai, Tamil Nadu');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Champz Turf'));
      await tester.pumpAndSettle();
      expect(find.text('At a Glance'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('venue-back')));
      await tester.pumpAndSettle();
      expect(find.text('At a Glance'), findsNothing);
      expect(find.text('1 Venue Found'), findsOneWidget);
    });
  });
}
