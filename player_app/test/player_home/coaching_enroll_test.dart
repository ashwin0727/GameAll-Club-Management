import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_payment_receipts.dart';

import 'package:gameall_player/features/payments/application/payment_flow.dart';
import 'package:gameall_player/core/routing/app_routes.dart';
import 'package:gameall_player/core/theme/app_theme.dart';
import 'package:gameall_player/core/utils/external_links.dart';
import 'package:gameall_player/features/auth/application/auth_providers.dart';
import 'package:gameall_player/features/auth/domain/player_profile.dart';
import 'package:gameall_player/features/venues/application/venues_providers.dart';
import 'package:gameall_player/features/venues/data/coaching_enroll_repository.dart';
import 'package:gameall_player/features/venues/data/venue_repository.dart';
import 'package:gameall_player/features/venues/domain/coaching_enroll.dart';
import 'package:gameall_player/features/venues/domain/venue.dart';
import 'package:gameall_player/features/venues/domain/venue_detail.dart';
import 'package:gameall_player/features/venues/presentation/coaching_enroll_page.dart';

Map<String, dynamic> _coach(
  String name, {
  double? rating = 4.9,
  int sessions = 128,
  String? cert = 'BWF Level 1 Certified',
}) => {
  'id': 'c-$name',
  'name': name,
  'rating': rating,
  'sessions': sessions,
  'certifications': cert,
};

Map<String, dynamic> _batch(
  String id,
  String start,
  String end,
  Map<String, dynamic>? coach, {
  int cap = 8,
  int enrolled = 0,
  List<int> days = const [1, 3, 5],
}) => {
  'id': id,
  'name': id,
  'daysOfWeek': days,
  'startTime': start,
  'endTime': end,
  'capacity': cap,
  'enrolled': enrolled,
  'coach': coach,
};

Map<String, dynamic> _program(
  String id,
  String name,
  String level,
  int chargeMinor,
  List<Map<String, dynamic>> batches, {
  String feeType = 'MONTHLY',
  int cycles = 1,
  bool online = true,
  bool open = true,
  int discount = 0,
  int base = 0,
  String sport = 's1',
  double tax = 0,
}) => {
  'id': id,
  'name': name,
  'level': level,
  'description': 'Build a strong foundation',
  'facilitySportId': sport,
  'sportName': sport == 's1' ? 'Badminton' : 'Turf',
  'programType': 'GROUP',
  'feeType': feeType,
  'durationMinutes': 60,
  'baseMinor': base == 0 ? chargeMinor : base,
  'discountMinor': discount,
  'taxPercent': tax,
  'chargeMinor': chargeMinor,
  'cycles': cycles,
  'startDate': '2026-08-24',
  'endDate': '2026-09-23',
  'membershipIncluded': false,
  'enrollmentOpen': open,
  'onlinePayable': online,
  'structure': ['Footwork', 'Smash'],
  'batches': batches,
};

CoachingInfo _info({
  bool accepting = true,
  bool autopay = true,
  List<Map<String, dynamic>>? programs,
}) => CoachingInfo.fromJson({
  'facilityId': 'v1',
  'facilityName': 'Champz Turf',
  'accepting': accepting,
  'autopayAvailable': autopay,
  'sports': [
    {'id': 's1', 'name': 'Badminton'},
    {'id': 's2', 'name': 'Turf'},
  ],
  'programs':
      programs ??
      [
        _program('p1', 'Beginner Programs', 'Beginner', 299900, [
          _batch(
            'b1',
            '18:00:00',
            '19:00:00',
            _coach('Coach Arjun'),
            enrolled: 5,
          ),
        ]),
        _program('p2', 'Intermediate Program', 'Intermediate', 399900, [
          _batch(
            'b2',
            '18:00:00',
            '19:00:00',
            _coach('Coach Divya', rating: 4.8, sessions: 96),
            cap: 6,
          ),
        ], cycles: 3),
        _program('p3', 'Advanced Program', 'Advanced', 499900, [
          _batch('b3', '19:00:00', '20:00:00', _coach('Coach Vignesh'), cap: 4),
        ], feeType: 'ONE_TIME'),
        _program(
          'p4',
          'Turf Football',
          'All Levels',
          100000,
          [_batch('b4', '17:00:00', '18:00:00', null)],
          feeType: 'ONE_TIME',
          sport: 's2',
        ),
      ],
});

class _Venues extends VenueRepository {
  @override
  Future<List<Venue>> listForLocation(
    String location, {
    VenueKind kind = VenueKind.venues,
  }) async => const [];

  @override
  Future<VenueDetail?> getVenue(String venueId) async => VenueDetail.fromJson({
    'id': 'v1',
    'name': 'Champz Turf',
    'city': 'Chennai',
    'area': 'Iyyapanthangal',
    'photos': <String>[],
    'sports': <dynamic>[],
    'courts': <dynamic>[],
  });
}

class _Coaching implements CoachingEnrollRepository {
  _Coaching({this.data, this.mineList = const [], this.failWith});
  final CoachingInfo? data;
  final List<MyCoaching> mineList;
  final String? failWith;
  final started = <(String, String?)>[];
  final linked = <String>[];

  @override
  Future<CoachingInfo?> info(String venueId) async => data;

  @override
  Future<List<MyCoaching>> mine(String venueId) async => mineList;

  @override
  Future<CoachingStart> start({
    required String venueId,
    required String programId,
    String? batchId,
  }) async {
    if (failWith != null) throw CoachingException(failWith!);
    started.add((programId, batchId));
    return CoachingStart(
      enrollmentId: 'e-$programId',
      feeType: programId == 'p3' ? 'ONE_TIME' : 'MONTHLY',
      cycles: 1,
      chargeMinor: 299900,
      totalMinor: 299900,
    );
  }

  @override
  Future<Uri> paymentLink(String enrollmentId) async {
    linked.add(enrollmentId);
    return Uri.parse('https://rzp.io/i/$enrollmentId');
  }
}

Future<(_Coaching, List<Uri>, List<String>)> _pump(
  WidgetTester tester, {
  _Coaching? repo,
  bool signedIn = true,
  Size size = const Size(1640, 1300),
  // A player picks a time slot before any programme shows (like Memberships); null leaves the page as it opens.
  String? slot = '6:00 PM – 7:00 PM',
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final r = repo ?? _Coaching(data: _info());
  final opened = <Uri>[];
  final routes = <String>[];
  final c = ProviderContainer(
    overrides: [
      venueRepositoryProvider.overrideWithValue(_Venues()),
      coachingEnrollRepositoryProvider.overrideWithValue(r),
      currentPlayerProvider.overrideWithValue(
        signedIn
            ? const PlayerProfile(
                id: 'p1',
                fullName: 'Arun',
                phone: '9000000001',
              )
            : null,
      ),
      paymentReceiptRepositoryProvider.overrideWithValue(FakePaymentReceipts()),
      linkOpenerProvider.overrideWithValue((uri) async {
        opened.add(uri);
        return true;
      }),
    ],
  );
  addTearDown(c.dispose);
  final wide = size.width >= 840;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: CoachingEnrollPage(
            venueId: 'v1',
            onNavigate: routes.add,
            embedded: wide,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
  if (slot != null &&
      find.byKey(ValueKey('coaching-slot-$slot')).evaluate().isNotEmpty) {
    await tester.ensureVisible(find.byKey(ValueKey('coaching-slot-$slot')));
    await tester.tap(find.byKey(ValueKey('coaching-slot-$slot')));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
  }
  addTearDown(() async => tester.pumpWidget(const SizedBox()));
  return (r, opened, routes);
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.tap(f);
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
}

Future<void> _tapKey(WidgetTester tester, String key) =>
    _tap(tester, find.byKey(ValueKey(key)));

/// A text inside the programme cards (the summary repeats the names, so it is not counted).
Finder _card(String text) => find.descendant(
  of: find.byKey(const ValueKey('coaching-programs')),
  matching: find.text(text),
);

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data!;

Finder _enroll(String program) => find.descendant(
  of: find.byKey(
    ValueKey(
      'coaching-offer-$program-b${program == 'Beginner Programs'
          ? 1
          : program == 'Intermediate Program'
          ? 2
          : 3}',
    ),
  ),
  matching: find.byKey(const ValueKey('offer-select')),
);

const _s6 = 'coaching-slot-6:00 PM – 7:00 PM';
const _s7 = 'coaching-slot-7:00 PM – 8:00 PM';
const _s5 = 'coaching-slot-5:00 PM – 6:00 PM';

void main() {
  group('Coaching page', () {
    testWidgets(
      'shows the design: title, filters, a card per coach, summary and policy',
      (tester) async {
        await _pump(tester);
        expect(find.text('Coaching at Champz Turf'), findsOneWidget);
        expect(
          find.text('Learn, improve and play better with certified coaches.'),
          findsOneWidget,
        );
        for (final t in [
          'Sport',
          'Coaching Type',
          'Preferred Time Slot',
          'Coaching Programs',
          'Enrollment Summary',
          'Cancellation Policy',
          'Pay & Enroll',
        ]) {
          expect(find.textContaining(t), findsWidgets, reason: t);
        }
        // the badminton programmes, with their coaches
        expect(_card('Coach Arjun'), findsOneWidget);
        expect(_card('Coach Divya'), findsOneWidget);
        expect(_card('Coach Vignesh'), findsNothing); // trains in the 7 PM slot
        expect(_card('Turf Football'), findsNothing); // another sport
        expect(find.text('BWF Level 1 Certified'), findsWidgets);
        expect(find.text('(128 sessions)'), findsWidgets);
        // the time slots the club made for badminton
        expect(find.text('6:00 PM – 7:00 PM'), findsWidgets);
        expect(find.text('7:00 PM – 8:00 PM'), findsWidgets);
        expect(find.text('5:00 PM – 6:00 PM'), findsNothing); // turf only
      },
    );

    testWidgets(
      'marks the most-joined batch Recommended and shows it in the summary',
      (tester) async {
        await _pump(tester);
        expect(find.byKey(const ValueKey('offer-recommended')), findsOneWidget);
        expect(_text(tester, 'summary-program'), 'Beginner Programs');
        expect(_text(tester, 'summary-coach'), 'Coach Arjun');
        expect(_text(tester, 'summary-slot'), '6:00 PM – 7:00 PM');
        expect(_text(tester, 'summary-sport'), 'Badminton');
        expect(_text(tester, 'summary-start'), 'Mon, 24 Aug 2026');
        expect(_text(tester, 'summary-end'), 'Wed, 23 Sep 2026');
        expect(_text(tester, 'summary-total'), '₹2,999');
      },
    );

    testWidgets('says plainly which fees recur and which are one time', (
      tester,
    ) async {
      await _pump(tester);
      // monthly programme: "/ month", Monthly chip, AutoPay card, recurring wording
      expect(find.text('Monthly'), findsWidgets);
      expect(find.text('/ month'), findsWidgets);
      expect(find.byKey(const ValueKey('coaching-autopay')), findsOneWidget);
      expect(find.byKey(const ValueKey('coaching-one-time')), findsNothing);
      expect(_text(tester, 'summary-duration'), 'Monthly (1 month)');
      // the one-time programme (in the 7 PM slot)
      await _tapKey(tester, _s7);
      await _tap(tester, _enroll('Advanced Program'));
      expect(find.text('one-time fee'), findsWidgets);
      expect(find.byKey(const ValueKey('coaching-one-time')), findsOneWidget);
      expect(find.byKey(const ValueKey('coaching-autopay')), findsNothing);
      expect(_text(tester, 'summary-duration'), 'One-time fee');
      expect(_text(tester, 'summary-total'), '₹4,999');
    });

    testWidgets('a multi-month fee shows today\'s payment and the total', (
      tester,
    ) async {
      await _pump(tester);
      await _tap(tester, _enroll('Intermediate Program'));
      expect(_text(tester, 'summary-duration'), 'Monthly (3 months)');
      expect(_text(tester, 'summary-total'), '₹3,999');
      expect(
        _text(tester, 'summary-total-all'),
        '₹3,999 a month for 3 months · ₹11,997 in total',
      );
      expect(find.text('Total Payable Today'), findsOneWidget);
    });

    testWidgets(
      'like Memberships: no programmes show until a time slot is picked',
      (tester) async {
        await _pump(tester, slot: null);
        expect(
          find.text('Pick a time slot to see its programs'),
          findsOneWidget,
        );
        expect(find.text('No programs to show yet.'), findsOneWidget);
        expect(find.byKey(const ValueKey('offer-select')), findsNothing);
        // the summary is empty and Pay & Enroll cannot be pressed
        expect(_text(tester, 'summary-program'), '—');
        expect(_text(tester, 'summary-total'), '—');
        await _tapKey(tester, 'coaching-pay');
        expect(find.byKey(const ValueKey('coaching-note')), findsOneWidget);
        expect(_text(tester, 'coaching-note'), 'Pick a program to enroll.');
      },
    );

    testWidgets('a time slot shows only the programmes made for it', (
      tester,
    ) async {
      await _pump(tester, slot: null);
      await _tapKey(tester, _s7);
      expect(_card('Coach Vignesh'), findsOneWidget);
      expect(_card('Coach Arjun'), findsNothing);
      expect(
        find.text('Programs available for Badminton at 7:00 PM – 8:00 PM'),
        findsOneWidget,
      );
      await _tapKey(tester, _s6);
      expect(_card('Coach Arjun'), findsOneWidget);
      expect(_card('Coach Divya'), findsOneWidget);
      expect(_card('Coach Vignesh'), findsNothing);
    });

    testWidgets('a coaching type narrows the programmes', (tester) async {
      await _pump(tester);
      await _tapKey(tester, 'coaching-level-Beginner');
      expect(_card('Coach Arjun'), findsOneWidget);
      expect(_card('Coach Divya'), findsNothing);
      await _tapKey(tester, 'coaching-level-All');
      expect(_card('Coach Divya'), findsOneWidget);
    });

    testWidgets('another sport shows that sport\'s programmes and slots', (
      tester,
    ) async {
      await _pump(tester);
      await _tapKey(tester, 'coaching-sport-Turf');
      // the slot is cleared with the sport: nothing shows until one of the turf slots is picked
      expect(_card('Turf Football'), findsNothing);
      await _tapKey(tester, _s5);
      expect(_card('Turf Football'), findsOneWidget);
      expect(_card('Coach Arjun'), findsNothing);
      expect(find.text('Coach to be announced'), findsOneWidget);
      expect(find.text('5:00 PM – 6:00 PM'), findsWidgets);
    });

    testWidgets(
      'Pay & Enroll makes the enrolment for the chosen batch and opens the payment page',
      (tester) async {
        final (repo, opened, _) = await _pump(tester);
        await _tapKey(tester, 'coaching-pay');
        expect(repo.started, [('p1', 'b1')]);
        expect(repo.linked, ['e-p1']);
        expect(opened.single.toString(), 'https://rzp.io/i/e-p1');
        expect(find.byKey(const ValueKey('pay-success')), findsOneWidget);
      },
    );

    testWidgets('a one-time programme is paid through the same flow', (
      tester,
    ) async {
      final (repo, opened, _) = await _pump(tester, slot: '7:00 PM – 8:00 PM');
      await _tap(tester, _enroll('Advanced Program'));
      await _tapKey(tester, 'coaching-pay');
      expect(repo.started, [('p3', 'b3')]);
      expect(opened, hasLength(1));
    });

    testWidgets(
      'a player who is signed out is sent to sign in, nothing is made',
      (tester) async {
        final (repo, opened, routes) = await _pump(tester, signedIn: false);
        await _tapKey(tester, 'coaching-pay');
        expect(routes, [AppRoutes.login]);
        expect(repo.started, isEmpty);
        expect(opened, isEmpty);
      },
    );

    testWidgets('a failed start shows the reason and opens nothing', (
      tester,
    ) async {
      final (_, opened, _) = await _pump(
        tester,
        repo: _Coaching(
          data: _info(),
          failWith: 'That batch is full. Pick another time slot.',
        ),
      );
      await _tapKey(tester, 'coaching-pay');
      expect(
        find.text('That batch is full. Pick another time slot.'),
        findsOneWidget,
      );
      expect(opened, isEmpty);
    });

    testWidgets(
      'a club-paid programme and a closed one cannot be enrolled, but a batch at capacity can',
      (tester) async {
        final data = _info(
          programs: [
            _program('p1', 'Beginner Programs', 'Beginner', 299900, [
              _batch(
                'b1',
                '18:00:00',
                '19:00:00',
                _coach('Coach Arjun'),
                cap: 4,
                enrolled: 4,
              ),
            ]),
            _program('p2', 'Intermediate Program', 'Intermediate', 399900, [
              _batch('b2', '18:00:00', '19:00:00', _coach('Coach Divya')),
            ], online: false),
            _program('p3', 'Advanced Program', 'Advanced', 499900, [
              _batch('b3', '18:00:00', '19:00:00', _coach('Coach Vignesh')),
            ], open: false),
          ],
        );
        await _pump(tester, repo: _Coaching(data: data));
        // a batch at its capacity is never turned away: no "Full" label, and it is the one most players joined
        expect(find.text('Full'), findsNothing);
        expect(find.text('Pay at club'), findsOneWidget);
        expect(find.text('Closed'), findsOneWidget);
        expect(find.byKey(const ValueKey('offer-blocked')), findsNWidgets(2));
        expect(find.byKey(const ValueKey('offer-recommended')), findsOneWidget);
      },
    );

    testWidgets(
      'a monthly programme is not payable online when the club has no AutoPay',
      (tester) async {
        final (repo, _, _) = await _pump(
          tester,
          repo: _Coaching(data: _info(autopay: false)),
        );
        expect(
          find.text('Pay at club'),
          findsNWidgets(2),
        ); // the two monthly ones
        await _tapKey(tester, _s7);
        await _tap(
          tester,
          _enroll('Advanced Program'),
        ); // the one-time one still works
        await _tapKey(tester, 'coaching-pay');
        expect(repo.started, [('p3', 'b3')]);
      },
    );

    testWidgets(
      'an early-bird discount and tax are shown, and the total is what is charged',
      (tester) async {
        final data = _info(
          programs: [
            _program(
              'p1',
              'Beginner Programs',
              'Beginner',
              294900,
              [_batch('b1', '18:00:00', '19:00:00', _coach('Coach Arjun'))],
              base: 299900,
              discount: 50000,
              tax: 18,
            ),
          ],
        );
        await _pump(tester, repo: _Coaching(data: data));
        expect(_text(tester, 'summary-fee'), '₹2,999');
        expect(_text(tester, 'summary-discount'), '-₹500');
        expect(_text(tester, 'summary-tax'), '₹450');
        expect(_text(tester, 'summary-total'), '₹2,949');
      },
    );

    testWidgets(
      'an unpaid enrolment can be completed from the page; a paid one blocks a second',
      (tester) async {
        final repo = _Coaching(
          data: _info(),
          mineList: const [
            MyCoaching(
              enrollmentId: 'e-old',
              programId: 'p2',
              programName: 'Intermediate Program',
              feeType: 'MONTHLY',
              billingStatus: 'CREATED',
            ),
            MyCoaching(
              enrollmentId: 'e-paid',
              programId: 'p3',
              programName: 'Advanced Program',
              feeType: 'ONE_TIME',
              paidMinor: 499900,
            ),
          ],
        );
        final (_, opened, _) = await _pump(tester, repo: repo);
        expect(find.byKey(const ValueKey('coaching-mine')), findsOneWidget);
        await _tapKey(tester, _s7);
        expect(find.text('Enrolled'), findsOneWidget); // the paid one's card
        await _tapKey(tester, 'mine-resume-Intermediate Program');
        expect(repo.linked, ['e-old']);
        expect(opened, hasLength(1));
      },
    );

    testWidgets('View Program Details opens the programme sheet', (
      tester,
    ) async {
      await _pump(tester);
      await _tapKey(tester, 'coaching-view-details');
      expect(find.byKey(const ValueKey('coaching-details')), findsOneWidget);
      expect(find.text('Footwork'), findsOneWidget);
      expect(find.text('₹2,999 every month (recurring)'), findsOneWidget);
    });

    testWidgets('a club that is not taking online enrolments says so', (
      tester,
    ) async {
      await _pump(tester, repo: _Coaching(data: _info(accepting: false)));
      expect(find.byKey(const ValueKey('coaching-closed')), findsOneWidget);
    });
    testWidgets('a venue with no programmes says so', (tester) async {
      await _pump(
        tester,
        repo: _Coaching(data: _info(programs: const [])),
      );
      expect(find.byKey(const ValueKey('coaching-none')), findsOneWidget);
    });
    testWidgets('an unknown venue says so', (tester) async {
      await _pump(tester, repo: _Coaching(data: null));
      expect(find.byKey(const ValueKey('coaching-missing')), findsOneWidget);
    });

    testWidgets(
      'works on a phone: stacked cards, choose with the radio button',
      (tester) async {
        final (repo, _, _) = await _pump(tester, size: const Size(390, 844));
        expect(tester.takeException(), isNull);
        expect(_card('Coach Arjun'), findsOneWidget);
        await _tapKey(tester, _s7);
        await _tap(tester, _enroll('Advanced Program'));
        expect(_text(tester, 'summary-program'), 'Advanced Program');
        await _tapKey(tester, 'coaching-pay');
        expect(repo.started, [('p3', 'b3')]);
        expect(tester.takeException(), isNull);
      },
    );

    for (final w in [900.0, 1100.0, 1280.0, 1920.0]) {
      testWidgets(
        'the card keeps the design\'s one-row layout without overflow at ${w.toInt()}px',
        (tester) async {
          await _pump(tester, size: Size(w, 1300));
          expect(tester.takeException(), isNull);
          // coach details, programme and price are all on the card
          expect(find.text('BWF Level 1 Certified'), findsWidgets);
          expect(find.byKey(const ValueKey('offer-price')), findsWidgets);
          // the coach block is to the left of the programme text, on the same row
          final coach = tester.getTopLeft(
            find.descendant(
              of: find.byKey(const ValueKey('coaching-programs')),
              matching: find.text('Coach Arjun'),
            ),
          );
          final program = tester.getTopLeft(
            find.descendant(
              of: find.byKey(const ValueKey('coaching-programs')),
              matching: find.text('Beginner Programs'),
            ),
          );
          // a wide column shows the single row; a narrower one puts the coach on top
          if (w >= 1920) expect(program.dx, greaterThan(coach.dx));
        },
      );
    }

    testWidgets(
      'a round Back button leads the title and returns to the venue; no breadcrumb row or picture band',
      (tester) async {
        final (_, _, routes) = await _pump(tester);
        expect(find.byKey(const ValueKey('crumb-venues')), findsNothing);
        expect(find.byKey(const ValueKey('crumb-venue')), findsNothing);
        await _tapKey(tester, 'coaching-back-button');
        expect(routes, [AppRoutes.venuePath('v1')]);
      },
    );

    testWidgets('the four coaching types are a 2 by 2 grid', (tester) async {
      await _pump(tester);
      Offset at(String l) =>
          tester.getTopLeft(find.byKey(ValueKey('coaching-level-$l')));
      expect(at('All').dy, at('Beginner').dy);
      expect(at('Intermediate').dy, at('Advanced').dy);
      expect(at('Intermediate').dy, greaterThan(at('All').dy));
      expect(at('Beginner').dx, greaterThan(at('All').dx));
      expect(at('Intermediate').dx, at('All').dx);
    });

    testWidgets(
      'several programmes are a slider: arrows, a counter, and a radio button chooses',
      (tester) async {
        await _pump(tester); // the 6 PM slot has two programmes
        expect(
          find.byKey(const ValueKey('coaching-slide-count')),
          findsOneWidget,
        );
        expect(_text(tester, 'coaching-slide-count'), '1 / 2');
        expect(find.text('Enroll Now'), findsNothing);
        // the first card is the one the summary follows
        expect(_text(tester, 'summary-program'), 'Beginner Programs');
        await _tapKey(tester, 'coaching-next');
        expect(_text(tester, 'coaching-slide-count'), '2 / 2');
        // sliding does not choose: the radio button does
        expect(_text(tester, 'summary-program'), 'Beginner Programs');
        await _tap(tester, _enroll('Intermediate Program'));
        expect(_text(tester, 'summary-program'), 'Intermediate Program');
        await _tapKey(tester, 'coaching-prev');
        expect(_text(tester, 'coaching-slide-count'), '1 / 2');
        expect(_text(tester, 'summary-program'), 'Intermediate Program');
      },
    );

    testWidgets(
      'one programme is shown on its own, with no arrows or counter',
      (tester) async {
        await _pump(tester, slot: '7:00 PM – 8:00 PM');
        expect(find.byKey(const ValueKey('coaching-next')), findsNothing);
        expect(find.byKey(const ValueKey('coaching-prev')), findsNothing);
        expect(
          find.byKey(const ValueKey('coaching-slide-count')),
          findsNothing,
        );
        expect(find.byKey(const ValueKey('offer-select')), findsOneWidget);
      },
    );

    testWidgets(
      'picking another time slot starts the slider again at the first programme',
      (tester) async {
        await _pump(tester);
        await _tapKey(tester, 'coaching-next');
        expect(_text(tester, 'coaching-slide-count'), '2 / 2');
        await _tapKey(tester, _s7);
        await _tapKey(tester, _s6);
        expect(_text(tester, 'coaching-slide-count'), '1 / 2');
      },
    );

    testWidgets(
      'tapping anywhere on a card chooses it, not only the radio button',
      (tester) async {
        await _pump(tester);
        await _tapKey(tester, 'coaching-next');
        expect(_text(tester, 'summary-program'), 'Beginner Programs');
        // the programme's name, nowhere near the radio button
        await _tap(
          tester,
          find.descendant(
            of: find.byKey(const ValueKey('coaching-programs')),
            matching: find.text('Intermediate Program'),
          ),
        );
        expect(_text(tester, 'summary-program'), 'Intermediate Program');
        expect(_text(tester, 'summary-coach'), 'Coach Divya');
      },
    );

    testWidgets('a card that cannot be joined is not chosen by tapping it', (
      tester,
    ) async {
      final data = _info(
        programs: [
          _program('p1', 'Beginner Programs', 'Beginner', 299900, [
            _batch('b1', '18:00:00', '19:00:00', _coach('Coach Arjun')),
          ]),
          _program('p2', 'Intermediate Program', 'Intermediate', 399900, [
            _batch('b2', '18:00:00', '19:00:00', _coach('Coach Divya')),
          ], online: false),
        ],
      );
      await _pump(tester, repo: _Coaching(data: data));
      await _tapKey(tester, 'coaching-next');
      await _tap(
        tester,
        find.descendant(
          of: find.byKey(const ValueKey('coaching-programs')),
          matching: find.text('Intermediate Program'),
        ),
      );
      expect(_text(tester, 'summary-program'), 'Beginner Programs');
    });
  });
}
