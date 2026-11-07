import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_player/core/routing/app_routes.dart';
import 'package:gameall_player/core/theme/app_theme.dart';
import 'package:gameall_player/core/utils/external_links.dart';
import 'package:gameall_player/features/auth/application/auth_providers.dart';
import 'package:gameall_player/features/auth/domain/player_profile.dart';
import 'package:gameall_player/features/my_bookings/application/guest_bookings_providers.dart';
import 'package:gameall_player/features/my_bookings/data/guest_bookings_repository.dart';
import 'package:gameall_player/features/my_bookings/domain/guest_booking.dart';
import 'package:gameall_player/features/my_bookings/presentation/my_bookings_page.dart';
import 'package:gameall_player/features/payments/application/payment_flow.dart';
import 'package:gameall_player/features/payments/data/receipt_pdf.dart';
import 'package:gameall_player/features/payments/domain/payment_receipt.dart';
import 'package:gameall_player/features/player_home/application/player_home_controller.dart';
import 'package:gameall_player/features/player_home/data/pending_payment_repository.dart';
import 'package:gameall_player/features/player_home/data/player_home_repository.dart';
import 'package:gameall_player/features/player_home/domain/player_dashboard_models.dart'
    show PendingPayment;
import 'package:gameall_player/features/player_home/domain/player_home_models.dart';

import '../support/fake_payment_receipts.dart';

class _Repo implements GuestBookingsRepository {
  _Repo(this.data, {this.fail = false});
  final GuestBookings data;
  final bool fail;

  @override
  Future<GuestBookings> mine() async {
    if (fail) throw Exception('boom');
    return data;
  }
}

class _Pay implements PendingPaymentRepository {
  final asked = <PendingPayment>[];
  @override
  Future<Uri?> paymentLink(PendingPayment payment) async {
    asked.add(payment);
    return Uri.parse('https://rzp.io/i/bal');
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

GuestBooking _b(
  String id,
  int days, {
  String status = 'confirmed',
  String venue = 'Champz Turf',
  String court = 'Court 1',
  int hour = 20,
  int hours = 1,
  int total = 500,
  int paid = 500,
  String pay = 'PAID',
}) => GuestBooking(
  id: id,
  ref: 'GBK-CHZ-${id.toUpperCase().padRight(5, '0')}',
  status: status,
  start: _at(days, hour),
  end: _at(days, hour + hours),
  sport: 'Badminton',
  court: court,
  totalInr: total,
  paidInr: paid,
  payState: pay,
  venue: BookingVenue(
    id: 'v-$venue',
    name: venue,
    area: 'Iyyapanthangal',
    city: 'Chennai',
    phone: '9876500000',
  ),
);

GuestBookings sample() => GuestBookings(
  upcoming: [
    _b('u1', 2),
    _b(
      'u2',
      4,
      venue: 'PlayZone Arena',
      court: 'Court 2',
      hour: 19,
      total: 1100,
      paid: 550,
      pay: 'PARTIAL',
    ),
  ],
  completed: [
    _b('c1', -3, status: 'completed', venue: 'Smash Court', court: 'Court 3'),
    _b('c2', -5, status: 'completed'),
    _b('c3', -9, status: 'completed'),
  ],
  cancelled: [_b('x1', -1, status: 'cancelled', paid: 0, pay: 'PENDING')],
  completedCount: 8,
  cancelledCount: 1,
);

Future<(List<String>, List<Uri>, _Pay, List<(Uint8List, String)>)> pumpPage(
  WidgetTester tester,
  GuestBookings data, {
  Size size = const Size(1600, 1200),
  bool fail = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final routes = <String>[];
  final opened = <Uri>[];
  final saved = <(Uint8List, String)>[];
  final pay = _Pay();
  final c = ProviderContainer(
    overrides: [
      guestBookingsRepositoryProvider.overrideWithValue(
        _Repo(data, fail: fail),
      ),
      pendingPaymentRepositoryProvider.overrideWithValue(pay),
      paymentReceiptRepositoryProvider.overrideWithValue(
        FakePaymentReceipts(kindOverride: PaymentKind.booking),
      ),
      receiptSaverProvider.overrideWithValue((b, n) async => saved.add((b, n))),
      receiptLogoProvider.overrideWithValue(() async => null),
      playerHomeRepositoryProvider.overrideWithValue(_Home()),
      currentPlayerProvider.overrideWithValue(
        const PlayerProfile(id: 'p', fullName: 'Arun', phone: '9000000001'),
      ),
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
        home: Scaffold(body: MyBookingsPage(onNavigate: routes.add)),
      ),
    ),
  );
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
  addTearDown(() async => tester.pumpWidget(const SizedBox()));
  return (routes, opened, pay, saved);
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
  group('GuestBooking model', () {
    test('reads the database function\'s answer', () {
      final g = GuestBookings.fromJson({
        'upcoming': [
          {
            'id': 'a',
            'ref': 'GBK-CHZ-1A2B3',
            'status': 'confirmed',
            'startTime': '2030-01-01T14:30:00Z',
            'endTime': '2030-01-01T16:00:00Z',
            'sport': 'Badminton',
            'court': 'Court 1',
            'players': 2,
            'totalInr': 750,
            'paidInr': 375,
            'payState': 'PARTIAL',
            'venue': {
              'id': 'v',
              'name': 'Champz',
              'area': 'Adyar',
              'city': 'Chennai',
            },
          },
        ],
        'completed': [],
        'cancelled': [],
        'completedCount': 8,
        'cancelledCount': 1,
      });
      final b = g.upcoming.single;
      expect(b.isUpcoming, isTrue);
      expect(b.durationLabel, '1.5 Hours');
      expect(b.balanceInr, 375);
      expect(b.venue.place, 'Adyar, Chennai');
      expect(g.completedCount, 8);
      expect(g.cancelledCount, 1);
      expect(g.isEmpty, isFalse);
    });

    test('durations read naturally', () {
      expect(_b('a', 1, hours: 1).durationLabel, '1 Hour');
      expect(_b('a', 1, hours: 2).durationLabel, '2 Hours');
    });

    test('the last past bookings are the two most recent completed ones', () {
      expect(sample().lastPast.map((b) => b.id), ['c1', 'c2']);
      expect(const GuestBookings().isEmpty, isTrue);
    });
  });

  group('Guest Booking page (web)', () {
    testWidgets(
      'title, the three tabs with their counts, and the upcoming bookings',
      (tester) async {
        await pumpPage(tester, sample());
        expect(find.byKey(const ValueKey('gb-title')), findsOneWidget);
        expect(find.text('Upcoming (2)'), findsOneWidget);
        expect(find.text('Completed (8)'), findsOneWidget);
        expect(find.text('Cancelled (1)'), findsOneWidget);
        expect(find.text('Upcoming Bookings'), findsOneWidget);
        expect(find.byKey(const ValueKey('gb-card-u1')), findsOneWidget);
        expect(find.byKey(const ValueKey('gb-card-u2')), findsOneWidget);
        expect(find.text('Confirmed'), findsWidgets);
        expect(find.byKey(const ValueKey('gb-book')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'the last two past bookings are listed under the upcoming ones',
      (tester) async {
        await pumpPage(tester, sample());
        expect(find.text('Past Bookings'), findsOneWidget);
        expect(find.byKey(const ValueKey('gb-past-c1')), findsOneWidget);
        expect(find.byKey(const ValueKey('gb-past-c2')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('gb-past-c3')),
          findsNothing,
          reason: 'only the last two',
        );
        expect(find.text('Completed'), findsWidgets);
      },
    );

    testWidgets('with no past bookings the Past Bookings section is left out', (
      tester,
    ) async {
      await pumpPage(tester, GuestBookings(upcoming: [_b('u1', 2)]));
      expect(find.text('Past Bookings'), findsNothing);
      expect(find.byKey(const ValueKey('gb-view-all')), findsNothing);
    });

    testWidgets('View All opens the Completed tab', (tester) async {
      await pumpPage(tester, sample());
      await tap(tester, 'gb-view-all');
      expect(find.text('Completed Bookings'), findsOneWidget);
      expect(find.byKey(const ValueKey('gb-card-c3')), findsOneWidget);
      expect(find.text('Past Bookings'), findsNothing);
    });

    testWidgets('the Cancelled tab lists cancelled bookings, with no actions', (
      tester,
    ) async {
      await pumpPage(tester, sample());
      await tap(tester, 'gb-tab-cancelled');
      expect(find.byKey(const ValueKey('gb-card-x1')), findsOneWidget);
      expect(find.text('Cancelled'), findsWidgets);
      expect(find.byKey(const ValueKey('gb-reschedule')), findsNothing);
      expect(find.byKey(const ValueKey('gb-cancel')), findsNothing);
    });

    testWidgets(
      'the first booking\'s details are shown, and picking another changes them',
      (tester) async {
        await pumpPage(tester, sample());
        expect(text(tester, 'gb-d-ref'), 'GBK-CHZ-U1000');
        expect(text(tester, 'gb-d-venue'), 'Champz Turf');
        expect(text(tester, 'gb-d-sport'), 'Badminton');
        expect(text(tester, 'gb-d-court'), 'Court 1');
        expect(text(tester, 'gb-d-time'), '8:00 PM – 9:00 PM (1 Hour)');
        expect(text(tester, 'gb-d-amount'), '₹500');
        expect(find.text('Paid'), findsOneWidget);
        await tap(tester, 'gb-card-u2');
        expect(text(tester, 'gb-d-venue'), 'PlayZone Arena');
        expect(text(tester, 'gb-d-court'), 'Court 2');
        expect(text(tester, 'gb-d-amount'), '₹1,100');
        expect(find.text('Advance paid'), findsOneWidget);
      },
    );

    testWidgets(
      'an advance-paid booking offers to pay the balance, through the payment pages',
      (tester) async {
        final (_, opened, pay, _) = await pumpPage(tester, sample());
        expect(
          find.byKey(const ValueKey('gb-pay')),
          findsNothing,
          reason: 'u1 is paid in full',
        );
        await tap(tester, 'gb-card-u2');
        expect(find.text('Pay balance · ₹550'), findsOneWidget);
        await tap(tester, 'gb-pay');
        expect(pay.asked.single.id, 'u2');
        expect(opened.single.toString(), 'https://rzp.io/i/bal');
      },
    );

    testWidgets('Download Receipt saves a PDF named for the receipt', (
      tester,
    ) async {
      final (_, _, _, saved) = await pumpPage(tester, sample());
      await tap(tester, 'gb-receipt');
      expect(saved, hasLength(1));
      expect(String.fromCharCodes(saved.single.$1.take(4)), '%PDF');
      expect(saved.single.$2, startsWith('GameAll-Receipt-'));
    });

    testWidgets('a booking with nothing paid has no receipt to download', (
      tester,
    ) async {
      await pumpPage(
        tester,
        GuestBookings(
          upcoming: [_b('u9', 3, paid: 0, pay: 'PENDING', status: 'pending')],
        ),
      );
      expect(find.byKey(const ValueKey('gb-receipt')), findsNothing);
      expect(find.text('Awaiting payment'), findsWidgets);
      expect(find.text('Complete payment · ₹500'), findsOneWidget);
    });

    testWidgets('Reschedule and Cancel Booking point the player to the club', (
      tester,
    ) async {
      await pumpPage(tester, sample());
      await tap(tester, 'gb-cancel');
      expect(find.text('Ask Champz Turf'), findsOneWidget);
      expect(find.textContaining('cancel your booking'), findsOneWidget);
    });

    testWidgets('Book a Court opens the booking flow', (tester) async {
      final (routes, _, _, _) = await pumpPage(tester, sample());
      await tap(tester, 'gb-book');
      expect(routes.last, AppRoutes.guestBooking);
    });

    testWidgets('a player with no bookings sees the empty state', (
      tester,
    ) async {
      final (routes, _, _, _) = await pumpPage(tester, const GuestBookings());
      expect(find.byKey(const ValueKey('gb-empty')), findsOneWidget);
      await tester.tap(find.text('Book a Court').last);
      expect(routes.last, AppRoutes.guestBooking);
    });

    testWidgets('an empty tab says so', (tester) async {
      await pumpPage(
        tester,
        GuestBookings(
          completed: [_b('c1', -3, status: 'completed')],
          completedCount: 1,
        ),
      );
      expect(find.byKey(const ValueKey('gb-tab-empty')), findsOneWidget);
    });

    testWidgets('a failed load offers Try again', (tester) async {
      await pumpPage(tester, const GuestBookings(), fail: true);
      expect(find.byKey(const ValueKey('gb-error')), findsOneWidget);
    });
  });

  group('Guest Booking page (phone)', () {
    testWidgets('tapping a booking opens its Booking Details page', (
      tester,
    ) async {
      await pumpPage(tester, sample(), size: const Size(390, 1800));
      expect(
        find.byKey(const ValueKey('gb-details')),
        findsNothing,
        reason: 'no side panel on a phone',
      );
      await tap(tester, 'gb-card-u1');
      expect(find.byKey(const ValueKey('gb-details-page')), findsOneWidget);
      expect(find.text('Booking Details'), findsWidgets);
      expect(text(tester, 'gb-d-ref'), 'GBK-CHZ-U1000');
      expect(tester.takeException(), isNull);
    });

    for (final w in [390.0, 320.0]) {
      testWidgets('no overflow at ${w.toInt()} px, in every tab', (
        tester,
      ) async {
        await pumpPage(tester, sample(), size: Size(w, 2000));
        for (final t in ['completed', 'cancelled', 'upcoming']) {
          await tap(tester, 'gb-tab-$t');
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('large text on a small phone does not overflow', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.4;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpPage(tester, sample(), size: const Size(320, 2400));
      await tap(tester, 'gb-card-u2');
      expect(tester.takeException(), isNull);
    });
  });
}
