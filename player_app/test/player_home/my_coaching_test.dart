import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_payment_receipts.dart';

import 'package:gameall_player/core/routing/app_routes.dart';
import 'package:gameall_player/core/theme/app_theme.dart';
import 'package:gameall_player/core/utils/external_links.dart';
import 'package:gameall_player/features/my_coaching/application/coaching_detail_providers.dart';
import 'package:gameall_player/features/my_coaching/data/coaching_detail_repository.dart';
import 'package:gameall_player/features/my_coaching/domain/coaching_detail.dart';
import 'package:gameall_player/features/my_coaching/presentation/my_coaching_page.dart';
import 'package:gameall_player/features/payments/application/payment_flow.dart';
import 'package:gameall_player/features/payments/domain/payment_receipt.dart';
import 'package:gameall_player/features/player_home/application/player_home_controller.dart';
import 'package:gameall_player/features/player_home/data/pending_payment_repository.dart';
import 'package:gameall_player/features/player_home/data/player_home_repository.dart';
import 'package:gameall_player/features/player_home/domain/player_dashboard_models.dart'
    show PendingPayment;
import 'package:gameall_player/features/player_home/domain/player_home_models.dart';
import 'package:gameall_player/features/shell/player_pages.dart';

class _Repo implements CoachingDetailRepository {
  _Repo(this.data, {this.fail = false});
  final List<CoachingDetail> data;
  final bool fail;

  @override
  Future<List<CoachingDetail>> mine() async {
    if (fail) throw Exception('boom');
    return data;
  }
}

class _Pay implements PendingPaymentRepository {
  final asked = <PendingPayment>[];
  @override
  Future<Uri?> paymentLink(PendingPayment payment) async {
    asked.add(payment);
    return Uri.parse('https://rzp.io/i/c');
  }
}

class _Home implements PlayerHomeRepository {
  @override
  Future<PlayerHomeData> load() async => throw UnimplementedError();
}

DateTime _at(int days, int hour) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day, hour).add(Duration(days: days));
}

CoachingSession _s(
  int days,
  String status, {
  int hour = 18,
  String court = 'Court 2',
}) => CoachingSession(
  id: 's$days$hour',
  start: _at(days, hour),
  end: _at(days, hour + 1),
  status: status,
  court: court,
);

CoachingDetail arjun({
  String payState = 'PAID',
  String status = 'ACTIVE',
  CoachingCoach? coach = const CoachingCoach(
    name: 'Coach Arjun',
    certification: 'BWF Level 1 Certified',
    experienceYears: 5.5,
    rating: 4.9,
  ),
  List<CoachingSession>? upcoming,
  List<CoachingNote> notes = const [],
  String feeType = 'ONE_TIME',
  int total = 8999,
  int charge = 8999,
  int paid = 8999,
  List<CoachingPayment> payments = const [],
  String programName = 'Intermediate Program',
}) => CoachingDetail(
  id: 'e1',
  ref: 'CRS-CHA-1A2B3C',
  programName: programName,
  status: status,
  sport: 'Badminton',
  level: 'Intermediate',
  programType: 'GROUP',
  startDate: DateTime(2026, 9, 1),
  endDate: DateTime(2026, 11, 30),
  feeType: feeType,
  venue: const CoachingVenue(
    id: 'v1',
    name: 'Champz Turf',
    area: 'Iyyapanthangal',
    city: 'Chennai',
    phone: '9876500000',
  ),
  coach: coach,
  batch: const CoachingBatchInfo(
    name: 'Evening',
    days: [1, 3, 5],
    startTime: '18:00',
    endTime: '19:00',
    capacity: 8,
    court: 'Court 2',
  ),
  progress: const CoachingProgress(total: 24, attended: 10, percent: 42),
  totalInr: total,
  chargeInr: charge,
  paidInr: paid,
  payState: payState,
  upcoming:
      upcoming ??
      [
        _s(1, 'SCHEDULED'),
        _s(3, 'SCHEDULED'),
        _s(5, 'SCHEDULED'),
        _s(7, 'SCHEDULED'),
      ],
  past: [_s(-2, 'COMPLETED'), _s(-4, 'CANCELLED'), _s(-6, 'COMPLETED')],
  payments: payments,
  notes: notes,
);

Future<(List<String>, List<Uri>, _Pay)> pumpPage(
  WidgetTester tester,
  List<CoachingDetail> data, {
  Size size = const Size(1600, 1100),
  bool fail = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final routes = <String>[];
  final opened = <Uri>[];
  final pay = _Pay();
  final c = ProviderContainer(
    overrides: [
      coachingDetailRepositoryProvider.overrideWithValue(
        _Repo(data, fail: fail),
      ),
      pendingPaymentRepositoryProvider.overrideWithValue(pay),
      paymentReceiptRepositoryProvider.overrideWithValue(
        FakePaymentReceipts(kindOverride: PaymentKind.coaching),
      ),
      playerHomeRepositoryProvider.overrideWithValue(_Home()),
      linkOpenerProvider.overrideWithValue((u) async {
        opened.add(u);
        return true;
      }),
    ],
  );
  addTearDown(c.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(body: MyCoachingPage(onNavigate: routes.add)),
      ),
    ),
  );
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
  addTearDown(() async => tester.pumpWidget(const SizedBox()));
  return (routes, opened, pay);
}

String text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data!;

Future<void> tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(ValueKey(key)));
  await tester.pump();
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
}

void main() {
  group('CoachingDetail model', () {
    test('reads the database function\'s answer', () {
      final d = CoachingDetail.fromJson({
        'id': 'e1',
        'enrollmentRef': 'CRS-CHA-000001',
        'status': 'ACTIVE',
        'programName': 'Beginner',
        'level': 'Beginner',
        'sport': 'Badminton',
        'programType': 'ONE_ON_ONE',
        'startDate': '2026-09-01',
        'endDate': '2026-11-30',
        'feeType': 'MONTHLY',
        'venue': {
          'id': 'v',
          'name': 'Champz',
          'area': 'Adyar',
          'city': 'Chennai',
        },
        'coach': {
          'name': 'Arjun',
          'rating': 4.9,
          'experienceYears': 8,
          'certification': 'BWF',
        },
        'batch': {
          'name': 'Eve',
          'daysOfWeek': [1, 3],
          'startTime': '18:00',
          'endTime': '19:00',
          'capacity': 1,
        },
        'progress': {
          'sessionsTotal': 24,
          'sessionsAttended': 10,
          'percent': 42,
        },
        'totalInr': 8999,
        'chargeInr': 2999,
        'paidInr': 2999,
        'payState': 'PAID',
        'upcoming': [
          {
            'id': 's',
            'startTime': '2030-01-01T12:30:00Z',
            'endTime': '2030-01-01T13:30:00Z',
            'status': 'SCHEDULED',
            'court': 'C1',
          },
        ],
        'past': [],
        'payments': [
          {
            'id': 'p',
            'amountInr': 2999,
            'status': 'paid',
            'method': 'UPI',
            'paidAt': '2026-09-01T10:00:00Z',
          },
        ],
        'notes': [
          {
            'id': 'n',
            'note': 'Good',
            'skill': 'Footwork',
            'progress': 'EXCELLING',
            'createdAt': '2026-09-02T10:00:00Z',
          },
        ],
      });
      expect(d.typeLabel, 'Individual Coaching');
      expect(d.durationLabel, '3 Months');
      expect(d.subtitle, 'Individual Coaching • 3 Months');
      expect(d.venue.place, 'Adyar, Chennai');
      expect(d.coach!.experienceLabel, '8 Years Experience');
      expect(d.isMonthly, isTrue);
      expect(d.chargeInr, 2999);
      expect(d.upcoming.single.court, 'C1');
      expect(d.notes.single.progressLabel, 'Excelling');
    });

    test('a coach with no rating or years shows none of it', () {
      final d = CoachingDetail.fromJson({
        'id': 'e',
        'programName': 'P',
        'venue': {'id': 'v', 'name': 'V'},
        'coach': {'name': 'Bare'},
      });
      expect(d.coach!.rating, isNull);
      expect(d.coach!.experienceLabel, isNull);
      expect(d.durationLabel, isNull);
      expect(d.batch, isNull);
    });

    test('experience reads naturally', () {
      expect(
        const CoachingCoach(name: 'a', experienceYears: 0.4).experienceLabel,
        'Under a year of experience',
      );
      expect(
        const CoachingCoach(name: 'a', experienceYears: 1).experienceLabel,
        '1 Year Experience',
      );
      expect(
        const CoachingCoach(name: 'a', experienceYears: 5.5).experienceLabel,
        '5+ Years Experience',
      );
    });
  });

  group('My Coaching page (web)', () {
    testWidgets(
      'the summary shows the programme, the coach and the venue as designed',
      (tester) async {
        await pumpPage(tester, [arjun()]);
        expect(text(tester, 'mc-title'), 'My Coaching');
        expect(
          text(tester, 'mc-program-name'),
          'Badminton – Intermediate Program',
        );
        expect(text(tester, 'mc-subtitle'), 'Group Coaching • 3 Months');
        expect(find.text('Enrolled'), findsOneWidget);
        expect(text(tester, 'mc-coach-name'), 'Coach Arjun');
        expect(find.text('BWF Level 1 Certified'), findsOneWidget);
        expect(text(tester, 'mc-coach-rating'), '4.9');
        expect(text(tester, 'mc-coach-experience'), '5+ Years Experience');
        expect(text(tester, 'mc-venue-name'), 'Champz Turf');
        expect(find.text('Iyyapanthangal, Chennai'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('programme progress comes from the sessions', (tester) async {
      await pumpPage(tester, [arjun()]);
      expect(text(tester, 'mc-progress-percent'), '42%');
      expect(text(tester, 'mc-started'), '01 Sep 2026');
      expect(text(tester, 'mc-ends'), '30 Nov 2026');
      expect(text(tester, 'mc-total-sessions'), '24');
      expect(text(tester, 'mc-attended'), '10');
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byKey(const ValueKey('mc-progress-bar')),
            )
            .value,
        closeTo(0.42, 0.001),
      );
    });

    testWidgets('Overview lists the programme details and the next sessions', (
      tester,
    ) async {
      await pumpPage(tester, [arjun()]);
      expect(text(tester, 'mc-d-sport'), 'Badminton');
      expect(text(tester, 'mc-d-level'), 'Intermediate');
      expect(text(tester, 'mc-d-type'), 'Group Batch');
      expect(text(tester, 'mc-d-size'), 'Max 8 Players');
      expect(
        text(tester, 'mc-d-schedule'),
        'Mon, Wed, Fri  |  6:00 PM – 7:00 PM',
      );
      expect(
        text(tester, 'mc-d-duration'),
        '3 Months (01 Sep 2026 – 30 Nov 2026)',
      );
      expect(text(tester, 'mc-fee'), '₹8,999');
      expect(find.text('Paid'), findsWidgets);
      // the first three of four sessions, with View All
      expect(find.byKey(const ValueKey('mc-session-up-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('mc-session-up-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('mc-session-up-3')), findsNothing);
      expect(find.byKey(const ValueKey('mc-view-all')), findsOneWidget);
      expect(find.text('Upcoming'), findsNWidgets(3));
    });

    testWidgets(
      'View All opens every session; the Sessions tab also lists the past ones',
      (tester) async {
        await pumpPage(tester, [arjun()]);
        await tap(tester, 'mc-view-all');
        expect(find.byKey(const ValueKey('mc-sessions-tab')), findsOneWidget);
        expect(find.byKey(const ValueKey('mc-session-up-3')), findsOneWidget);
        expect(find.byKey(const ValueKey('mc-session-past-2')), findsOneWidget);
        expect(find.text('Attended'), findsWidgets);
        expect(find.text('Cancelled'), findsOneWidget);
      },
    );

    testWidgets(
      'Attendance counts the sessions held and those the club cancelled',
      (tester) async {
        await pumpPage(tester, [arjun()]);
        await tap(tester, 'mc-tab-attendance');
        expect(text(tester, 'mc-att-attended'), '10');
        expect(text(tester, 'mc-att-total'), '24');
        expect(text(tester, 'mc-att-cancelled'), '1');
      },
    );

    testWidgets('Payments shows the fee, what was paid and the history', (
      tester,
    ) async {
      await pumpPage(tester, [
        arjun(
          payments: [
            CoachingPayment(
              id: 'p',
              amountInr: 8999,
              status: 'paid',
              method: 'UPI',
              paidAt: DateTime(2026, 9, 1),
              reference: 'pay_X',
            ),
          ],
        ),
      ]);
      await tap(tester, 'mc-tab-payments');
      expect(text(tester, 'mc-pay-total'), '₹8,999');
      expect(text(tester, 'mc-pay-paid'), '₹8,999');
      expect(find.byKey(const ValueKey('mc-payment-0')), findsOneWidget);
      expect(find.text('₹8,999'), findsWidgets);
      expect(find.byKey(const ValueKey('mc-pay-banner')), findsNothing);
    });

    testWidgets(
      'a monthly programme shows one charge, not the whole fee, as the fee',
      (tester) async {
        await pumpPage(tester, [
          arjun(feeType: 'MONTHLY', total: 8999, charge: 2999, paid: 2999),
        ]);
        expect(text(tester, 'mc-fee'), '₹2,999 / month');
        await tap(tester, 'mc-tab-payments');
        expect(text(tester, 'mc-pay-charge'), '₹2,999');
        expect(text(tester, 'mc-pay-total'), '₹8,999');
        expect(
          find.byKey(const ValueKey('mc-pay-balance')),
          findsNothing,
          reason: 'the rest is taken month by month',
        );
      },
    );

    testWidgets(
      'Coach Notes lists the coach\'s notes, or says there are none',
      (tester) async {
        await pumpPage(tester, [
          arjun(
            notes: [
              CoachingNote(
                id: 'n',
                note: 'Good split-step timing.',
                progress: 'ON_TRACK',
                skill: 'Footwork',
                coach: 'Coach Arjun',
                createdAt: DateTime(2026, 9, 2),
              ),
            ],
          ),
        ]);
        await tap(tester, 'mc-tab-notes');
        expect(find.text('Footwork'), findsOneWidget);
        expect(find.text('Good split-step timing.'), findsOneWidget);
        expect(find.text('On track'), findsOneWidget);
      },
    );

    testWidgets('with no notes yet it says so', (tester) async {
      await pumpPage(tester, [arjun()]);
      await tap(tester, 'mc-tab-notes');
      expect(find.byKey(const ValueKey('mc-no-notes')), findsOneWidget);
    });

    testWidgets('a coach the club has not rated shows no rating or years', (
      tester,
    ) async {
      await pumpPage(tester, [
        arjun(coach: const CoachingCoach(name: 'Bare Bones')),
      ]);
      expect(text(tester, 'mc-coach-name'), 'Bare Bones');
      expect(find.byKey(const ValueKey('mc-coach-rating')), findsNothing);
      expect(find.byKey(const ValueKey('mc-coach-experience')), findsNothing);
    });

    testWidgets('a programme with no coach says the club will assign one', (
      tester,
    ) async {
      await pumpPage(tester, [arjun(coach: null)]);
      expect(find.byKey(const ValueKey('mc-no-coach')), findsOneWidget);
    });

    testWidgets('no upcoming sessions says so', (tester) async {
      await pumpPage(tester, [arjun(upcoming: const [])]);
      expect(find.byKey(const ValueKey('mc-no-upcoming')), findsOneWidget);
    });

    testWidgets(
      'an unpaid programme shows Payment Incomplete and a Pay button that opens the payment page',
      (tester) async {
        final (_, opened, pay) = await pumpPage(tester, [
          arjun(payState: 'PENDING', paid: 0),
        ]);
        expect(find.text('Payment Incomplete'), findsOneWidget);
        expect(
          find.text('Enrolled'),
          findsNothing,
          reason: 'unpaid is never shown as enrolled',
        );
        expect(find.text('Payment pending'), findsOneWidget);
        await tap(tester, 'mc-pay');
        expect(pay.asked.single.id, 'e1');
        expect(opened.single.toString(), 'https://rzp.io/i/c');
        expect(
          find.byKey(const ValueKey('pay-success')),
          findsOneWidget,
          reason: 'the progress page then the success page',
        );
      },
    );

    testWidgets('a paused programme says so', (tester) async {
      await pumpPage(tester, [arjun(status: 'PAUSED', upcoming: const [])]);
      expect(find.text('Paused'), findsOneWidget);
      expect(find.byKey(const ValueKey('mc-paused-banner')), findsOneWidget);
    });

    testWidgets('Renew, View Venue and Contact Coach go where they say', (
      tester,
    ) async {
      final (routes, opened, _) = await pumpPage(tester, [arjun()]);
      await tap(tester, 'mc-view-venue');
      expect(routes.last, AppRoutes.venuePath('v1'));
      await tap(tester, 'mc-action-renew');
      expect(routes.last, AppRoutes.coachingEnrollPath('v1'));
      await tap(tester, 'mc-action-contact');
      expect(opened.single.toString(), 'tel:9876500000');
    });

    testWidgets('Reschedule and Pause are the club\'s to decide', (
      tester,
    ) async {
      await pumpPage(tester, [arjun()]);
      await tap(tester, 'mc-action-reschedule');
      expect(find.text('Ask Champz Turf'), findsOneWidget);
      expect(find.textContaining('reschedule a session'), findsOneWidget);
    });

    testWidgets('several programmes can be switched between', (tester) async {
      await pumpPage(tester, [arjun(), arjun(programName: 'Advanced Program')]);
      expect(
        text(tester, 'mc-program-name'),
        'Badminton – Intermediate Program',
      );
      await tap(tester, 'mc-switch-1');
      expect(text(tester, 'mc-program-name'), 'Badminton – Advanced Program');
    });

    testWidgets('no coaching shows the empty state with a way to explore', (
      tester,
    ) async {
      final (routes, _, _) = await pumpPage(tester, const []);
      expect(find.byKey(const ValueKey('mc-empty')), findsOneWidget);
      await tap(tester, 'mc-browse');
      expect(routes.last, AppRoutes.coaching);
    });

    testWidgets('a failed load offers Try again', (tester) async {
      await pumpPage(tester, const [], fail: true);
      expect(find.byKey(const ValueKey('mc-error')), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  group('My Coaching page (phone)', () {
    for (final w in [390.0, 320.0]) {
      testWidgets(
        'stacked layout at ${w.toInt()} px: no overflow, everything reachable',
        (tester) async {
          await pumpPage(tester, [arjun()], size: Size(w, 1800));
          expect(
            text(tester, 'mc-program-name'),
            'Badminton – Intermediate Program',
          );
          for (final t in [
            'sessions',
            'attendance',
            'payments',
            'notes',
            'overview',
          ]) {
            await tap(tester, 'mc-tab-$t');
          }
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('a small phone with large text does not overflow', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.4;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpPage(tester, [
        arjun(payState: 'PENDING', paid: 0),
      ], size: const Size(320, 2000));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('the My Coaching route opens this page inside the shell', (
    tester,
  ) async {
    final page = playerPageForRoute(AppRoutes.myCoaching, embedded: true);
    expect(page, isA<Builder>());
  });
}
