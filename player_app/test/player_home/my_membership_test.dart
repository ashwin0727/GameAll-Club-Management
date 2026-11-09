import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_payment_receipts.dart';

import 'package:gameall_player/features/payments/application/payment_flow.dart';
import 'package:gameall_player/core/routing/app_routes.dart';
import 'package:gameall_player/core/theme/app_theme.dart';
import 'package:gameall_player/core/utils/external_links.dart';
import 'package:gameall_player/features/my_membership/application/membership_detail_providers.dart';
import 'package:gameall_player/features/my_membership/data/membership_detail_repository.dart';
import 'package:gameall_player/features/my_membership/domain/membership_detail.dart';
import 'package:gameall_player/features/my_membership/presentation/my_membership_page.dart';
import 'package:gameall_player/features/player_home/application/player_home_controller.dart';
import 'package:gameall_player/features/player_home/data/pending_payment_repository.dart';
import 'package:gameall_player/features/player_home/data/player_home_repository.dart';
import 'package:gameall_player/features/player_home/domain/player_dashboard_models.dart'
    show PendingPayment, PendingPaymentKind;
import 'package:gameall_player/features/player_home/domain/player_home_models.dart';
import 'package:gameall_player/features/shell/player_pages.dart';
import 'package:gameall_player/features/shell/player_shell.dart';
import 'package:gameall_player/features/venues/application/venues_providers.dart';

class _Repo implements MembershipDetailRepository {
  _Repo(this.data, {this.fail = false});
  final List<MembershipDetail> data;
  final bool fail;
  int calls = 0;

  @override
  Future<List<MembershipDetail>> mine() async {
    calls++;
    if (fail) throw Exception('boom');
    return data;
  }
}

class FakePay implements PendingPaymentRepository {
  FakePay({this.link, this.error});
  final Uri? link;
  final String? error;
  final asked = <PendingPayment>[];

  @override
  Future<Uri?> paymentLink(PendingPayment payment) async {
    asked.add(payment);
    if (error != null) throw PaymentLinkException(error!);
    return link;
  }
}

class _Home implements PlayerHomeRepository {
  _Home(this.data);
  final PlayerHomeData data;
  @override
  Future<PlayerHomeData> load() async => data;
}

MembershipDetail champz({
  String payState = 'PAID',
  List<MembershipPayment>? payments,
  List<MembershipBooking>? bookings,
  MembershipSlot? slot,
  MembershipUsage usage = const MembershipUsage(total: 20, used: 12),
  String? autopay,
  String? phone = '9876500000',
  int? totalInr = 3000,
  int paidInr = 3000,
}) => MembershipDetail(
  id: 'ms1',
  ref: 'MBR-CHZ-000458',
  planName: 'Court Time Membership',
  description: 'Dedicated court time every weekday',
  durationDays: 30,
  priceInr: 3000,
  totalInr: totalInr,
  paidInr: paidInr,
  features: const ['Dedicated court time', 'Priority court access'],
  startDate: DateTime(2026, 9, 1),
  endDate: DateTime(2026, 9, 30),
  memberSince: DateTime(2026, 9, 1),
  autopayStatus: autopay,
  paymentMethod: 'UPI',
  payState: payState,
  venue: MembershipVenue(
    id: 'v1',
    name: 'Champz Turf',
    area: 'Iyyapanthangal',
    city: 'Chennai',
    phone: phone,
  ),
  slot:
      slot ??
      const MembershipSlot(
        batchName: 'Evening',
        sport: 'Badminton',
        court: 'Court 2',
        days: [1, 2, 3, 4, 5],
        start: '18:00',
        end: '19:00',
      ),
  usage: usage,
  payments:
      payments ??
      [
        MembershipPayment(
          id: 'p1',
          amountInr: 3000,
          status: 'paid',
          method: 'UPI',
          when: DateTime(2026, 9, 1),
          reference: 'pay_ABC123',
        ),
      ],
  bookings:
      bookings ??
      [
        MembershipBooking(
          id: 'b1',
          status: 'completed',
          start: DateTime(2026, 9, 2, 18),
          end: DateTime(2026, 9, 2, 19),
          court: 'Court 2',
          sport: 'Badminton',
        ),
        MembershipBooking(
          id: 'b2',
          status: 'confirmed',
          start: DateTime.now().add(const Duration(days: 2)),
          end: DateTime.now().add(const Duration(days: 2, hours: 1)),
          court: 'Court 2',
          sport: 'Badminton',
        ),
      ],
);

Future<(List<String>, List<Uri>, FakePay, ProviderContainer)> pumpPage(
  WidgetTester tester,
  List<MembershipDetail> data, {
  Size size = const Size(1600, 1000),
  bool fail = false,
  FakePay? pay,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final routes = <String>[];
  final opened = <Uri>[];
  final payRepo = pay ?? FakePay(link: Uri.parse('https://rzp.io/i/pay'));
  final c = ProviderContainer(
    overrides: [
      membershipDetailRepositoryProvider.overrideWithValue(
        _Repo(data, fail: fail),
      ),
      pendingPaymentRepositoryProvider.overrideWithValue(payRepo),
      paymentReceiptRepositoryProvider.overrideWithValue(FakePaymentReceipts()),
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
        home: Scaffold(body: MyMembershipPage(onNavigate: routes.add)),
      ),
    ),
  );
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
  addTearDown(() async => tester.pumpWidget(const SizedBox()));
  return (routes, opened, payRepo, c);
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
  group('Membership Details page (web)', () {
    testWidgets(
      'the summary card, usage and Overview show the membership as designed',
      (tester) async {
        await pumpPage(tester, [champz()]);
        expect(find.text('Membership Details'), findsOneWidget);
        // hero
        expect(find.text('Active Membership'), findsOneWidget);
        expect(text(tester, 'mm-plan-name'), 'Court Time Membership');
        expect(text(tester, 'mm-subtitle'), 'Badminton • Monthly');
        expect(text(tester, 'mm-venue-name'), 'Champz Turf');
        expect(find.text('Iyyapanthangal, Chennai'), findsOneWidget);
        expect(find.byKey(const ValueKey('mm-view-venue')), findsOneWidget);
        expect(text(tester, 'mm-member-since'), '01 Sep 2026');
        expect(text(tester, 'mm-valid-till'), '30 Sep 2026');
        expect(text(tester, 'mm-ref'), 'MBR-CHZ-000458');
        // usage
        expect(find.text("This Month's Usage"), findsOneWidget);
        expect(text(tester, 'mm-usage-count'), '12 / 20 Sessions');
        expect(text(tester, 'mm-usage-text'), '12 Used  ·  8 Remaining');
        expect(find.byKey(const ValueKey('mm-book-slot')), findsOneWidget);
        // tabs
        for (final t in ['Overview', 'Bookings', 'Payments', 'Benefits']) {
          expect(find.text(t), findsOneWidget, reason: t);
        }
        // plan card
        expect(find.text('Membership Plan'), findsOneWidget);
        expect(text(tester, 'mm-period'), 'Monthly');
        expect(
          text(tester, 'mm-description'),
          'Dedicated court time every weekday',
        );
        expect(find.text('Plan Price'), findsOneWidget);
        expect(find.byKey(const ValueKey('mm-price')), findsOneWidget);
        expect(find.textContaining('₹3,000'), findsWidgets);
        expect(find.textContaining('/ month'), findsOneWidget);
        expect(text(tester, 'mm-row-sport'), 'Badminton');
        expect(text(tester, 'mm-row-court'), 'Court 2');
        expect(text(tester, 'mm-row-slot'), 'Mon – Fri, 6:00 PM – 7:00 PM');
        expect(text(tester, 'mm-row-limit'), '20 Sessions / Month');
        expect(text(tester, 'mm-row-payment'), 'Online (UPI)');
        // status
        expect(find.text('Membership Status'), findsOneWidget);
        expect(text(tester, 'mm-status-short'), 'Active');
        for (final t in ['Activated', 'Expires', 'Now']) {
          expect(find.text(t), findsWidgets, reason: t);
        }
        expect(find.text('01 Sep 2026'), findsWidgets);
        // quick actions
        expect(find.text('Quick Actions'), findsOneWidget);
        for (final k in [
          'mm-action-book',
          'mm-action-renew',
          'mm-action-pause',
          'mm-action-cancel',
        ]) {
          expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
        }
        expect(find.text('Renew Membership'), findsOneWidget);
        expect(find.text('Pause (Temporary)'), findsOneWidget);
        expect(find.text('Cancel Membership'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('mm-pay-banner')),
          findsNothing,
          reason: 'paid: no payment banner',
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('Book a Slot, View Venue and Renew open the right pages', (
      tester,
    ) async {
      final (routes, _, _, c) = await pumpPage(tester, [champz()]);
      await tap(tester, 'mm-book-slot');
      expect(routes.last, AppRoutes.bookPath('v1'));
      await tap(tester, 'mm-action-book');
      expect(routes.last, AppRoutes.bookPath('v1'));
      await tap(tester, 'mm-view-venue');
      expect(routes.last, AppRoutes.venuePath('v1'));
      await tap(tester, 'mm-action-renew');
      expect(routes.last, AppRoutes.enrollPath('v1'));
      expect(
        c.read(preferredSportProvider),
        'Badminton',
        reason: 'renewing starts the enrol page on this membership\'s sport',
      );
      await tap(tester, 'mm-browse');
      expect(routes.last, AppRoutes.memberships);
    });

    testWidgets(
      'Pause and Cancel point the player to the club, with a call button',
      (tester) async {
        final (_, opened, _, _) = await pumpPage(tester, [champz()]);
        await tap(tester, 'mm-action-pause');
        expect(find.byKey(const ValueKey('mm-ask-pause')), findsOneWidget);
        expect(find.textContaining('please ask the club'), findsOneWidget);
        await tester.tap(find.text('Call Champz Turf'));
        await tester.pumpAndSettle();
        expect(opened.single.scheme, 'tel');
        expect(opened.single.path, '9876500000');
        await tap(tester, 'mm-action-cancel');
        expect(find.byKey(const ValueKey('mm-ask-cancel')), findsOneWidget);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('mm-ask-cancel')), findsNothing);
      },
    );

    testWidgets('Pause without a venue phone says to ask at the desk', (
      tester,
    ) async {
      await pumpPage(tester, [champz(phone: null)]);
      await tap(tester, 'mm-action-pause');
      expect(find.textContaining('front desk'), findsOneWidget);
      expect(find.textContaining('Call '), findsNothing);
    });

    testWidgets(
      'Bookings tab: upcoming first, then past; each with its status',
      (tester) async {
        await pumpPage(tester, [champz()]);
        await tap(tester, 'mm-tab-bookings');
        expect(find.byKey(const ValueKey('mm-bookings')), findsOneWidget);
        expect(find.text('Upcoming'), findsOneWidget);
        expect(find.text('Past'), findsOneWidget);
        expect(find.text('Confirmed'), findsOneWidget);
        expect(find.text('Completed'), findsOneWidget);
        expect(find.textContaining('02 Sep 2026'), findsOneWidget);
        expect(find.text('Court 2 · Badminton'), findsNWidgets(2));
      },
    );

    testWidgets('Bookings tab with none says so and offers Book a Slot', (
      tester,
    ) async {
      final (routes, _, _, _) = await pumpPage(tester, [
        champz(bookings: const []),
      ]);
      await tap(tester, 'mm-tab-bookings');
      expect(find.byKey(const ValueKey('mm-no-bookings')), findsOneWidget);
      await tester.tap(find.text('Book a Slot').last);
      expect(routes.last, AppRoutes.bookPath('v1'));
    });

    testWidgets('Payments tab: totals and each payment', (tester) async {
      await pumpPage(tester, [champz()]);
      await tap(tester, 'mm-tab-payments');
      expect(text(tester, 'mm-pay-total'), '₹3,000');
      expect(text(tester, 'mm-pay-paid'), '₹3,000');
      expect(text(tester, 'mm-pay-balance'), '₹0');
      expect(find.text('Paid'), findsWidgets);
      expect(find.text('UPI · pay_ABC123'), findsOneWidget);
      expect(find.byKey(const ValueKey('mm-pay-tab')), findsNothing);
    });

    testWidgets(
      'Benefits tab: the plan\'s features, the session limit and AutoPay',
      (tester) async {
        await pumpPage(tester, [champz(autopay: 'active')]);
        await tap(tester, 'mm-tab-benefits');
        expect(find.text('Dedicated court time'), findsOneWidget);
        expect(find.text('Priority court access'), findsOneWidget);
        expect(find.text('20 Sessions / Month'), findsOneWidget);
        expect(
          find.text('Renews automatically with UPI AutoPay'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'an unpaid membership shows "Payment Incomplete", the balance and a Pay button that opens the payment page',
      (tester) async {
        final (_, opened, pay, _) = await pumpPage(tester, [
          champz(payState: 'PENDING', paidInr: 1000, payments: const []),
        ]);
        expect(find.text('Payment Incomplete'), findsWidgets);
        expect(
          find.text('Active Membership'),
          findsNothing,
          reason: 'unpaid is never shown as Active',
        );
        expect(text(tester, 'mm-status-short'), 'Payment Incomplete');
        expect(find.textContaining('₹2,000 to pay'), findsOneWidget);
        await tap(tester, 'mm-pay');
        expect(pay.asked.single.kind, PendingPaymentKind.membership);
        expect(pay.asked.single.id, 'ms1');
        expect(opened.single.toString(), 'https://rzp.io/i/pay');
        expect(find.byKey(const ValueKey('pay-success')), findsOneWidget);
        Navigator.of(tester.element(find.byKey(const ValueKey('pay-success'))))
            .pop();
        await tester.pumpAndSettle();
        await tap(tester, 'mm-tab-payments');
        expect(text(tester, 'mm-pay-balance'), '₹2,000');
        expect(find.byKey(const ValueKey('mm-no-payments')), findsOneWidget);
        expect(find.byKey(const ValueKey('mm-pay-tab')), findsOneWidget);
      },
    );

    testWidgets('a failed payment is shown as failed with Retry', (
      tester,
    ) async {
      await pumpPage(tester, [
        champz(
          payState: 'FAILED',
          paidInr: 0,
          payments: [
            MembershipPayment(
              id: 'f1',
              amountInr: 3000,
              status: 'failed',
              method: 'UPI',
              when: DateTime(2026, 9, 1),
            ),
          ],
        ),
      ]);
      expect(find.text('Payment Failed'), findsWidgets);
      expect(find.text('Retry payment'), findsWidgets);
      await tap(tester, 'mm-tab-payments');
      expect(find.text('Failed'), findsOneWidget);
    });

    testWidgets(
      'a payment page that cannot open says so; an already-paid answer refreshes',
      (tester) async {
        final (_, _, _, _) = await pumpPage(tester, [
          champz(payState: 'PENDING'),
        ], pay: FakePay(error: 'The club has not set up payments.'));
        await tap(tester, 'mm-pay');
        expect(find.text('The club has not set up payments.'), findsOneWidget);
      },
    );

    testWidgets('with several memberships a chip row switches between them', (
      tester,
    ) async {
      final second = MembershipDetail(
        id: 'ms2',
        ref: 'MBR-SMA-000007',
        planName: 'Football Weekend',
        priceInr: 2800,
        durationDays: 90,
        endDate: DateTime(2026, 12, 1),
        venue: const MembershipVenue(
          id: 'v2',
          name: 'Smash Arena',
          city: 'Chennai',
        ),
      );
      await pumpPage(tester, [champz(), second]);
      expect(find.byKey(const ValueKey('mm-switch-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('mm-switch-1')), findsOneWidget);
      expect(text(tester, 'mm-plan-name'), 'Court Time Membership');
      await tap(tester, 'mm-switch-1');
      expect(text(tester, 'mm-plan-name'), 'Football Weekend');
      expect(text(tester, 'mm-ref'), 'MBR-SMA-000007');
      expect(text(tester, 'mm-period'), 'Quarterly');
      expect(
        find.byKey(const ValueKey('mm-no-slot')),
        findsOneWidget,
        reason: 'no allocated slot yet',
      );
      expect(find.byKey(const ValueKey('mm-usage-none')), findsOneWidget);
    });

    testWidgets('no membership: an empty state with Explore memberships', (
      tester,
    ) async {
      final (routes, _, _, _) = await pumpPage(tester, const []);
      expect(find.byKey(const ValueKey('mm-empty')), findsOneWidget);
      await tester.tap(find.text('Explore memberships'));
      expect(routes.last, AppRoutes.memberships);
    });

    testWidgets('a load error offers Try again', (tester) async {
      await pumpPage(tester, const [], fail: true);
      expect(find.byKey(const ValueKey('mm-error')), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets(
      'built from Home\'s short summary (database update not installed): shows what it has, no crash',
      (tester) async {
        final limited = fromDashboard({
          'id': 'ms9',
          'planName': 'Weekend Pro',
          'venueName': 'Smash Arena',
          'endDate': '2030-01-31',
          'batchName': 'Sat',
          'daysOfWeek': [6, 0],
          'startTime': '07:00',
          'endTime': '08:00',
          'courtName': 'Court 1',
          'paymentIncomplete': false,
        });
        await pumpPage(tester, [limited]);
        expect(text(tester, 'mm-plan-name'), 'Weekend Pro');
        expect(text(tester, 'mm-venue-name'), 'Smash Arena');
        expect(
          text(tester, 'mm-row-slot'),
          'Sun, Sat, 7:00 AM – 8:00 AM'.replaceFirst('Sun, Sat', 'Sat – Sun'),
        );
        expect(find.byKey(const ValueKey('mm-ref')), findsNothing);
        await tap(tester, 'mm-tab-bookings');
        expect(find.textContaining('after the latest update'), findsOneWidget);
        await tap(tester, 'mm-tab-payments');
        expect(find.textContaining('after the latest update'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('Membership Details page (phone)', () {
    testWidgets('stacked layout at 390 px: no overflow, everything reachable', (
      tester,
    ) async {
      await pumpPage(tester, [
        champz(payState: 'PENDING'),
      ], size: const Size(390, 844));
      expect(find.byKey(const ValueKey('mm-hero')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('mm-usage')));
      await tester.ensureVisible(find.byKey(const ValueKey('mm-actions-card')));
      for (final t in ['bookings', 'payments', 'benefits', 'overview']) {
        await tap(tester, 'mm-tab-$t');
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('a small phone with large text does not overflow', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.4;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpPage(tester, [
        champz(payState: 'FAILED'),
      ], size: const Size(320, 640));
      expect(tester.takeException(), isNull);
      for (final t in ['bookings', 'payments', 'benefits']) {
        await tap(tester, 'mm-tab-$t');
        expect(tester.takeException(), isNull, reason: t);
      }
    });
  });

  group('labels', () {
    test('days: runs, every day, gaps', () {
      expect(daysLabel([1, 2, 3, 4, 5]), 'Mon – Fri');
      expect(daysLabel([1, 2, 3, 4, 5, 6]), 'Mon – Sat');
      expect(daysLabel([0, 1, 2, 3, 4, 5, 6]), 'Every day');
      expect(daysLabel([1, 3, 5]), 'Mon, Wed, Fri');
      expect(daysLabel([6, 0]), 'Sat – Sun');
      expect(daysLabel([2, 4, 6]), 'Tue, Thu, Sat');
      expect(daysLabel([1]), 'Mon');
      expect(daysLabel(const []), '');
    });

    test('times and dates', () {
      expect(clock12('18:00'), '6:00 PM');
      expect(clock12('06:30:00'), '6:30 AM');
      expect(clock12('00:00'), '12:00 AM');
      expect(clock12('12:15'), '12:15 PM');
      expect(fmtDate(DateTime(2026, 9, 1)), '01 Sep 2026');
      expect(fmtDate(DateTime(2027, 1, 31)), '31 Jan 2027');
    });

    test('plan lengths, price periods and status words', () {
      MembershipDetail m(int? days, [String pay = 'PAID']) => MembershipDetail(
        id: 'x',
        ref: '',
        planName: 'P',
        venue: const MembershipVenue(id: 'v', name: 'V'),
        durationDays: days,
        payState: pay,
      );
      expect(m(30).periodLabel, 'Monthly');
      expect(m(30).pricePeriod, 'month');
      expect(m(90).periodLabel, 'Quarterly');
      expect(m(180).periodLabel, 'Half-yearly');
      expect(m(365).periodLabel, 'Yearly');
      expect(m(365).pricePeriod, 'year');
      expect(m(10).periodLabel, '10 days');
      expect(m(null).periodLabel, 'Membership');
      expect(m(30).statusPill, 'Active Membership');
      expect(m(30, 'PENDING').statusPill, 'Payment Incomplete');
      expect(m(30, 'FAILED').statusShort, 'Payment Failed');
    });

    test('payment mode', () {
      MembershipDetail m({
        String? method,
        String? autopay,
        String pay = 'PAID',
      }) => MembershipDetail(
        id: 'x',
        ref: '',
        planName: 'P',
        venue: const MembershipVenue(id: 'v', name: 'V'),
        paymentMethod: method,
        autopayStatus: autopay,
        payState: pay,
      );
      expect(m(method: 'UPI').paymentMode, 'Online (UPI)');
      expect(m(method: 'Cash').paymentMode, 'Cash at the club');
      expect(m(method: 'Card').paymentMode, 'Online (Card)');
      expect(m(autopay: 'active').paymentMode, 'UPI AutoPay');
      expect(m().paymentMode, 'Paid at the club');
      expect(m(pay: 'PENDING').paymentMode, 'Not paid yet');
      expect(m(method: 'Bank Transfer').paymentMode, 'Bank Transfer');
    });

    test(
      'usage: remaining never negative, fraction in 0..1, none without a slot',
      () {
        expect(const MembershipUsage(total: 20, used: 12).remaining, 8);
        expect(const MembershipUsage(total: 20, used: 25).remaining, 0);
        expect(const MembershipUsage(total: 20, used: 25).fraction, 1.0);
        expect(const MembershipUsage(total: 20, used: 5).fraction, 0.25);
        expect(const MembershipUsage().fraction, 0);
        expect(const MembershipUsage().remaining, 0);
        final m = MembershipDetail(
          id: 'x',
          ref: '',
          planName: 'P',
          venue: const MembershipVenue(id: 'v', name: 'V'),
          usage: const MembershipUsage(total: 1, used: 0),
        );
        expect(m.sessionLimitLabel, '1 Session / Month');
      },
    );

    test('balance', () {
      final m = MembershipDetail(
        id: 'x',
        ref: '',
        planName: 'P',
        venue: const MembershipVenue(id: 'v', name: 'V'),
        totalInr: 2000,
        paidInr: 1000,
      );
      expect(m.balanceInr, 1000);
      expect(
        MembershipDetail(
          id: 'x',
          ref: '',
          planName: 'P',
          venue: const MembershipVenue(id: 'v', name: 'V'),
          totalInr: 2000,
          paidInr: 2500,
        ).balanceInr,
        0,
      );
    });

    test('reads the database answer', () {
      final m = MembershipDetail.fromJson({
        'id': 'm1',
        'membershipRef': 'MBR-CHZ-000458',
        'planName': 'Court Time Membership',
        'description': ' Dedicated ',
        'durationDays': 30,
        'priceInr': 3000,
        'totalInr': 3000,
        'paidInr': 3000,
        'features': ['A', '', null, ' B '],
        'startDate': '2026-09-01',
        'endDate': '2026-09-30',
        'memberSince': '2026-09-01',
        'payState': 'PAID',
        'paymentMethod': 'UPI',
        'venue': {
          'id': 'v1',
          'name': 'Champz Turf',
          'area': 'Iyyapanthangal',
          'city': 'Chennai',
          'phone': '98765',
          'imageUrl': 'http://x/y.jpg',
        },
        'slot': {
          'batchName': 'Evening',
          'sport': 'Badminton',
          'court': 'Court 2',
          'daysOfWeek': [1, 2, 3, 4, 5],
          'startTime': '18:00',
          'endTime': '19:00',
        },
        'usage': {'sessionsTotal': 20, 'sessionsUsed': 12},
        'payments': [
          {
            'id': 'p',
            'amountInr': 3000,
            'status': 'paid',
            'method': 'UPI',
            'paidAt': '2026-09-01T10:00:00Z',
            'reference': 'pay_1',
          },
        ],
        'bookings': [
          {
            'id': 'b',
            'startTime': '2026-09-02T12:30:00Z',
            'endTime': '2026-09-02T13:30:00Z',
            'status': 'COMPLETED',
            'court': 'Court 2',
            'sport': 'Badminton',
            'source': 'BOOKING',
          },
        ],
      });
      expect(m.ref, 'MBR-CHZ-000458');
      expect(m.description, 'Dedicated');
      expect(m.features, ['A', 'B']);
      expect(m.venue.place, 'Iyyapanthangal, Chennai');
      expect(m.slot!.label, 'Mon – Fri, 6:00 PM – 7:00 PM');
      expect(m.usage.used, 12);
      expect(m.payments.single.statusLabel, 'Paid');
      expect(m.bookings.single.status, 'completed');
      expect(m.bookings.single.statusLabel, 'Completed');
    });

    test('a venue whose area repeats the city shows the city once', () {
      expect(
        const MembershipVenue(
          id: 'v',
          name: 'V',
          area: 'Chennai',
          city: 'Chennai',
        ).place,
        'Chennai',
      );
      expect(const MembershipVenue(id: 'v', name: 'V').place, '');
    });
  });

  group('getting there', () {
    testWidgets(
      'the My Membership route builds the page (phone: its own screen with a back arrow)',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final c = ProviderContainer(
          overrides: [
            membershipDetailRepositoryProvider.overrideWithValue(
              _Repo([champz()]),
            ),
          ],
        );
        addTearDown(c.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: c,
            child: MaterialApp(
              theme: AppTheme.dark(),
              home: playerPageForRoute(AppRoutes.myMembership),
            ),
          ),
        );
        await tester.pumpAndSettle(const Duration(milliseconds: 100));
        expect(find.byType(AppBar), findsOneWidget);
        expect(find.byType(MyMembershipPage), findsOneWidget);
        expect(find.text('Court Time Membership'), findsWidgets);
      },
    );

    PlayerHomeData homeWith({required bool membership}) => PlayerHomeData(
      fullName: 'Uma',
      signedIn: true,
      unreadNotifications: 0,
      hasActiveMembership: membership,
      hasActiveCoaching: false,
      hasBookingHistory: false,
      upcomingBookings: const [],
    );

    for (final active in [true, false]) {
      testWidgets(
        'the top bar "Memberships" link goes to ${active ? 'the membership details' : 'the list of memberships'} when the player ${active ? 'has' : 'has no'} an active membership',
        (tester) async {
          tester.view.physicalSize = const Size(1600, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final routes = <String>[];
          final c = ProviderContainer(
            overrides: [
              playerHomeRepositoryProvider.overrideWithValue(
                _Home(homeWith(membership: active)),
              ),
              membershipDetailRepositoryProvider.overrideWithValue(
                _Repo([champz()]),
              ),
            ],
          );
          addTearDown(c.dispose);
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: c,
              child: MaterialApp(
                theme: AppTheme.dark(),
                home: PlayerShell(onNavigate: routes.add),
              ),
            ),
          );
          await tester.pumpAndSettle(const Duration(milliseconds: 200));
          await tester.tap(find.byKey(const ValueKey('nav-Memberships')));
          await tester.pumpAndSettle();
          expect(routes, [
            active ? AppRoutes.myMembership : AppRoutes.memberships,
          ]);
        },
      );
    }
  });
}
