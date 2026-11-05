import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_player/core/routing/app_routes.dart';
import 'package:gameall_player/core/theme/app_theme.dart';
import 'package:gameall_player/core/utils/external_links.dart';
import 'package:gameall_player/features/auth/application/auth_providers.dart';
import 'package:gameall_player/features/auth/domain/player_profile.dart';
import 'package:gameall_player/features/venues/application/venues_providers.dart';
import 'package:gameall_player/features/venues/data/membership_enroll_repository.dart';
import 'package:gameall_player/features/venues/data/venue_repository.dart';
import 'package:gameall_player/features/venues/domain/membership_enroll.dart';
import 'package:gameall_player/features/venues/domain/venue.dart';
import 'package:gameall_player/features/venues/domain/venue_detail.dart';
import 'package:gameall_player/features/venues/presentation/enroll_membership_page.dart';

Map<String, dynamic> _batch(String plan, {int enrolled = 0, int spare = 6}) =>
    {'batchId': 'b-$plan-$enrolled', 'planId': plan, 'courtName': 'Court 1', 'daysOfWeek': [1, 2, 3], 'capacity': enrolled + spare, 'enrolled': enrolled, 'spare': spare};

Map<String, dynamic> _slot(String start, String end, int now, int spare, List<Map<String, dynamic>> batches) =>
    {'facilitySportId': 's1', 'sportName': 'Badminton', 'startTime': start, 'endTime': end, 'capacity': now + spare, 'membersNow': now, 'spare': spare, 'batches': batches};

EnrollInfo _info({bool accepting = true, bool autopay = true, bool slots = true}) => EnrollInfo.fromJson({
      'facilityId': 'v1',
      'facilityName': 'Champz Turf',
      'accepting': accepting,
      'autopayAvailable': autopay,
      'sports': [
        {'id': 's1', 'name': 'Badminton'},
        {'id': 's2', 'name': 'Turf'},
      ],
      'slots': slots
          ? [
              _slot('18:00:00', '19:00:00', 4, 16, [_batch('monthly', enrolled: 4), _batch('quarterly', spare: 10)]),
              _slot('19:00:00', '20:00:00', 0, 5, [_batch('monthly', spare: 5)]),
              _slot('20:00:00', '21:00:00', 8, 0, [_batch('monthly', enrolled: 8, spare: 0)]),
            ]
          : [],
      'plans': [
        {'id': 'monthly', 'name': 'Monthly', 'priceInr': 2999, 'durationDays': 30, 'features': ['Dedicated court time', 'Priority court access'], 'description': 'Play all month', 'joiningFeeInr': 0},
        {'id': 'quarterly', 'name': 'Quarterly', 'priceInr': 7999, 'durationDays': 90, 'badgeText': 'Save 11%', 'features': <String>[], 'joiningFeeInr': 500},
      ],
    });

class _Venues extends VenueRepository {
  @override
  Future<List<Venue>> listForLocation(String location, {VenueKind kind = VenueKind.venues}) async => const [];

  @override
  Future<VenueDetail?> getVenue(String venueId) async => VenueDetail.fromJson({'id': 'v1', 'name': 'Champz Turf', 'city': 'Chennai', 'area': 'Iyyapanthangal', 'photos': <String>[], 'sports': <dynamic>[], 'courts': <dynamic>[]});
}

class _Enroll implements MembershipEnrollRepository {
  _Enroll({this.data, this.mine = const [], this.failWith, this.failInfo});
  final String? failInfo;
  final EnrollInfo? data;
  final List<ExistingMembership> mine;
  final String? failWith;
  final started = <(String, String?)>[];

  @override
  Future<EnrollInfo?> info(String venueId) async {
    if (failInfo != null) throw EnrollException(failInfo!);
    return data;
  }

  @override
  Future<List<ExistingMembership>> myMemberships(String venueId) async => mine;

  @override
  Future<EnrollStart> start({required String venueId, required String planId, String? batchId}) async {
    if (failWith != null) throw EnrollException(failWith!);
    started.add((planId, batchId));
    return const EnrollStart(membershipId: 'm1', amountInr: 2999);
  }

  @override
  Future<Uri> autopayLink(String membershipId) async => Uri.parse('https://rzp.io/i/abc');
}

Future<(_Enroll, List<Uri>, List<String>)> _pump(WidgetTester tester, {_Enroll? repo, bool signedIn = true, Size size = const Size(1640, 1100)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final r = repo ?? _Enroll(data: _info());
  final opened = <Uri>[];
  final routes = <String>[];
  final c = ProviderContainer(overrides: [
    venueRepositoryProvider.overrideWithValue(_Venues()),
    membershipEnrollRepositoryProvider.overrideWithValue(r),
    currentPlayerProvider.overrideWithValue(signedIn ? const PlayerProfile(id: 'p1', fullName: 'Arun', phone: '9000000001') : null),
    linkOpenerProvider.overrideWithValue((uri) async {
      opened.add(uri);
      return true;
    }),
  ]);
  addTearDown(c.dispose);
  final wide = size.width >= 840;
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(theme: AppTheme.dark(), home: Scaffold(body: EnrollMembershipPage(venueId: 'v1', onNavigate: routes.add, embedded: wide, now: DateTime(2026, 8, 24)))),
  ));
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
  addTearDown(() async => tester.pumpWidget(const SizedBox()));
  return (r, opened, routes);
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(ValueKey(key)));
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
}

String _text(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(ValueKey(key))).data!;

void main() {
  group('Enroll Membership page', () {
    testWidgets('asks for a time slot first; a slot shows only the plans made for it', (tester) async {
      await _pump(tester);
      expect(find.text('Enroll Membership'), findsWidgets);
      expect(find.byKey(const ValueKey('plans-empty')), findsOneWidget);
      expect(find.byKey(const ValueKey('enroll-plan-Monthly')), findsNothing);

      await _tap(tester, 'enroll-slot-6:00 PM – 7:00 PM');
      expect(find.byKey(const ValueKey('enroll-plan-Monthly')), findsOneWidget);
      expect(find.byKey(const ValueKey('enroll-plan-Quarterly')), findsOneWidget);
      expect(find.text('Save 11%'), findsOneWidget);

      await _tap(tester, 'enroll-slot-7:00 PM – 8:00 PM');
      expect(find.byKey(const ValueKey('enroll-plan-Monthly')), findsOneWidget);
      expect(find.byKey(const ValueKey('enroll-plan-Quarterly')), findsNothing, reason: 'that slot has no quarterly batch');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a plan fills the summary, dates and total, and the benefits say how many already play there', (tester) async {
      await _pump(tester);
      await _tap(tester, 'enroll-slot-6:00 PM – 7:00 PM');
      expect(find.byKey(const ValueKey('benefits-empty')), findsOneWidget);
      await _tap(tester, 'enroll-plan-Monthly');
      expect(_text(tester, 'summary-slot'), '6:00 PM – 7:00 PM');
      expect(_text(tester, 'summary-plan'), 'Monthly (1 month)');
      expect(_text(tester, 'summary-start'), 'Mon, 24 Aug 2026');
      expect(_text(tester, 'summary-end'), 'Wed, 23 Sep 2026');
      expect(_text(tester, 'summary-total'), '₹2,999');
      // the amounts end on the same right edge as the rows above them
      final edge = tester.getTopRight(find.byKey(const ValueKey('summary-plan'))).dx;
      expect(tester.getTopRight(find.byKey(const ValueKey('summary-plan-amount'))).dx, closeTo(edge, 0.5));
      expect(tester.getTopRight(find.byKey(const ValueKey('summary-total'))).dx, closeTo(edge, 0.5));
      expect(find.text('Dedicated court time'), findsOneWidget);
      expect(find.text('Play all month'), findsOneWidget);
      expect(find.textContaining('4 members play in 6:00 PM – 7:00 PM right now'), findsOneWidget);
      expect(find.textContaining('Auto Pay'), findsWidgets);

      await _tap(tester, 'enroll-plan-Quarterly');
      expect(_text(tester, 'summary-fee'), '₹500');
      expect(_text(tester, 'summary-total'), '₹8,499');
    });

    testWidgets('an empty slot says the player would be the first, and a busy one can still be joined', (tester) async {
      final (repo, _, _) = await _pump(tester);
      await _tap(tester, 'enroll-slot-7:00 PM – 8:00 PM'); // one plan only: chosen for the player
      expect(find.textContaining("You'd be the first member"), findsOneWidget);
      expect(_text(tester, 'summary-plan'), 'Monthly (1 month)');

      await _tap(tester, 'enroll-slot-8:00 PM – 9:00 PM');
      expect(find.text('Full'), findsNothing, reason: 'clubs set no limit on members per slot');
      expect(find.textContaining('8 members play in 8:00 PM – 9:00 PM'), findsOneWidget);
      await _tap(tester, 'enroll-plan-Monthly');
      await _tap(tester, 'enroll-pay');
      expect(repo.started.single.$2, 'b-monthly-8');
    });

    testWidgets('Pay & Enroll makes the membership in the chosen batch and opens the AutoPay page', (tester) async {
      final (repo, opened, _) = await _pump(tester);
      await _tap(tester, 'enroll-slot-6:00 PM – 7:00 PM');
      await _tap(tester, 'enroll-plan-Monthly');
      await _tap(tester, 'enroll-pay');
      expect(repo.started.single, ('monthly', 'b-monthly-4'));
      expect(opened.single.toString(), 'https://rzp.io/i/abc');
    });

    testWidgets('Pay & Enroll waits for a plan, and a signed-out player is sent to log in', (tester) async {
      final (repo, opened, routes) = await _pump(tester, signedIn: false);
      await _tap(tester, 'enroll-pay');
      expect(repo.started, isEmpty);
      expect(routes, isEmpty);
      await _tap(tester, 'enroll-slot-6:00 PM – 7:00 PM');
      await _tap(tester, 'enroll-plan-Monthly');
      await _tap(tester, 'enroll-pay');
      expect(routes, [AppRoutes.login]);
      expect(opened, isEmpty);
    });

    testWidgets('an error from joining is shown and nothing opens', (tester) async {
      final (_, opened, _) = await _pump(tester, repo: _Enroll(data: _info(), failWith: 'That time slot is full. Pick another.'));
      await _tap(tester, 'enroll-slot-6:00 PM – 7:00 PM');
      await _tap(tester, 'enroll-plan-Monthly');
      await _tap(tester, 'enroll-pay');
      expect(find.text('That time slot is full. Pick another.'), findsOneWidget);
      expect(opened, isEmpty);
    });

    testWidgets('memberships the number already has are shown, and another can still be joined', (tester) async {
      final (repo, _, _) = await _pump(
        tester,
        repo: _Enroll(data: _info(), mine: [ExistingMembership(id: 'x', planName: 'Quarterly', endDate: DateTime(2026, 11, 20), autoRenew: true, slots: const ['6:00 AM – 7:00 AM'])]),
      );
      expect(find.byKey(const ValueKey('enroll-existing')), findsOneWidget);
      expect(find.textContaining('Quarterly  ·  6:00 AM – 7:00 AM  ·  active till 20 Nov 2026  ·  AutoPay on'), findsOneWidget);
      await _tap(tester, 'enroll-slot-6:00 PM – 7:00 PM');
      await _tap(tester, 'enroll-plan-Monthly');
      await _tap(tester, 'enroll-pay');
      expect(repo.started, isNotEmpty);
    });

    testWidgets('a club without AutoPay cannot be paid online, and says so', (tester) async {
      final (repo, _, _) = await _pump(tester, repo: _Enroll(data: _info(autopay: false)));
      await _tap(tester, 'enroll-slot-6:00 PM – 7:00 PM');
      await _tap(tester, 'enroll-plan-Monthly');
      await _tap(tester, 'enroll-pay');
      expect(repo.started, isEmpty);
      expect(find.textContaining("hasn't turned on online payments"), findsOneWidget);
    });

    testWidgets('a club with no time slots offers its plans straight away', (tester) async {
      await _pump(tester, repo: _Enroll(data: _info(slots: false)));
      expect(find.text('Select Membership Time Slot'), findsNothing);
      expect(find.byKey(const ValueKey('enroll-plan-Monthly')), findsOneWidget);
    });

    testWidgets('a club that is not taking online memberships says so', (tester) async {
      final (_, _, routes) = await _pump(tester, repo: _Enroll(data: _info(accepting: false)));
      expect(find.byKey(const ValueKey('enroll-closed')), findsOneWidget);
      await tester.tap(find.text('Back to venue'));
      expect(routes, [AppRoutes.venuePath('v1')]);
    });

    testWidgets('a failed load shows the problem with Try again, not "venue not available"', (tester) async {
      await _pump(tester, repo: _Enroll(data: _info(), failInfo: 'database said no'));
      expect(find.byKey(const ValueKey('enroll-error')), findsOneWidget);
      expect(find.byKey(const ValueKey('enroll-missing')), findsNothing);
      expect(find.textContaining('database said no'), findsOneWidget);
      expect(find.byKey(const ValueKey('book-retry')), findsOneWidget);
    });

    testWidgets('a venue that is not open says so', (tester) async {
      await _pump(tester, repo: _Enroll());
      expect(find.byKey(const ValueKey('enroll-missing')), findsOneWidget);
    });

    testWidgets('on a phone the cards stack and nothing overflows, even with large text', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.4;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pump(tester, size: const Size(320, 700));
      await _tap(tester, 'enroll-slot-6:00 PM – 7:00 PM');
      await _tap(tester, 'enroll-plan-Quarterly');
      await tester.dragUntilVisible(find.byKey(const ValueKey('enroll-pay')), find.byKey(const ValueKey('enroll-scroll')), const Offset(0, -300));
      expect(tester.takeException(), isNull);
    });
  });

  group('plan and slot maths', () {
    test('plans end a day before the same date next period', () {
      EnrollPlan plan(int days) => EnrollPlan(id: 'p', name: 'P', priceInr: 1, durationDays: days);
      expect(plan(30).endFrom(DateTime(2026, 8, 24)), DateTime(2026, 9, 23));
      expect(plan(90).endFrom(DateTime(2026, 8, 31)), DateTime(2026, 11, 29));
      expect(plan(365).endFrom(DateTime(2026, 8, 24)), DateTime(2027, 8, 23));
      expect(plan(7).endFrom(DateTime(2026, 8, 24)), DateTime(2026, 8, 30));
      expect(plan(30).validFor, 'Valid for 1 month');
      expect(plan(180).validFor, 'Valid for 6 months');
      expect(plan(365).validFor, 'Valid for 1 year');
      expect(plan(7).validFor, 'Valid for 7 days');
    });

    test('clock labels', () {
      expect(clockLabel(0), '12:00 AM');
      expect(clockLabel(18 * 60 + 30), '6:30 PM');
      expect(clockLabel(12 * 60), '12:00 PM');
    });
  });
}
