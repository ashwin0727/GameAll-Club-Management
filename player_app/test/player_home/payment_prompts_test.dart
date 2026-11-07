import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_payment_receipts.dart';

import 'package:gameall_player/features/payments/application/payment_flow.dart';
import 'package:gameall_player/core/theme/app_theme.dart';
import 'package:gameall_player/core/utils/external_links.dart';
import 'package:gameall_player/features/player_home/application/player_home_controller.dart';
import 'package:gameall_player/features/player_home/data/pending_payment_repository.dart';
import 'package:gameall_player/features/player_home/data/player_home_repository.dart';
import 'package:gameall_player/features/player_home/domain/player_dashboard_models.dart';
import 'package:gameall_player/features/player_home/domain/player_home_models.dart';
import 'package:gameall_player/features/player_home/presentation/pages/player_dashboard_desktop.dart';
import 'package:gameall_player/features/player_home/presentation/widgets/payment_prompts.dart';

PendingPayment _p(
  PendingPaymentKind kind, {
  String id = 'x1',
  String title = 'Monthly Unlimited',
  String venue = 'Champz Turf',
  bool failed = false,
  bool overdue = false,
  bool autopay = true,
  DateTime? start,
}) => PendingPayment(
  kind: kind,
  id: id,
  title: title,
  venueName: venue,
  failed: failed,
  overdue: overdue,
  autopay: autopay,
  startTime: start,
);

class _Pay implements PendingPaymentRepository {
  _Pay({this.link, this.fail});
  final Uri? link;
  final String? fail;
  final asked = <PendingPayment>[];

  @override
  Future<Uri?> paymentLink(PendingPayment payment) async {
    asked.add(payment);
    if (fail != null) throw PaymentLinkException(fail!);
    return link;
  }
}

class _Home implements PlayerHomeRepository {
  int loads = 0;
  @override
  Future<PlayerHomeData> load() async {
    loads++;
    return const PlayerHomeData.guest();
  }
}

Future<(_Pay, _Home, List<Uri>)> _pump(
  WidgetTester tester,
  List<PendingPayment> payments, {
  _Pay? pay,
  Size size = const Size(1200, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = pay ?? _Pay(link: Uri.parse('https://rzp.io/i/abc'));
  final home = _Home();
  final opened = <Uri>[];
  final c = ProviderContainer(
    overrides: [
      pendingPaymentRepositoryProvider.overrideWithValue(repo),
      playerHomeRepositoryProvider.overrideWithValue(home),
      paymentReceiptRepositoryProvider.overrideWithValue(FakePaymentReceipts()),
      linkOpenerProvider.overrideWithValue((uri) async {
        opened.add(uri);
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
        home: Scaffold(
          body: SingleChildScrollView(
            child: PaymentPrompts(payments: payments),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async => tester.pumpWidget(const SizedBox()));
  return (repo, home, opened);
}

void main() {
  group('what the dashboard sends', () {
    test('a pending payment is read from the database JSON', () {
      final p = PendingPayment.fromJson({
        'kind': 'coaching',
        'id': 'e1',
        'title': 'Weekday Badminton Coaching',
        'venueName': 'Champz Turf',
        'state': 'FAILED',
        'overdue': true,
        'mode': 'AUTOPAY',
      });
      expect(p.kind, PendingPaymentKind.coaching);
      expect(p.failed, isTrue);
      expect(p.overdue, isTrue);
      expect(p.autopay, isTrue);
      expect(p.urgent, isTrue);
    });

    test('Home data carries the list, and a visitor has none', () {
      final d = PlayerHomeData.fromJson({
        'fullName': 'Test',
        'unreadNotifications': 0,
        'pendingPayments': [
          {
            'kind': 'booking',
            'id': 'b1',
            'title': 'Guest Booking',
            'venueName': 'Champz Turf',
            'state': 'PENDING',
            'startTime': '2026-11-06T11:30:00Z',
          },
        ],
      });
      expect(d.pendingPayments.single.kind, PendingPaymentKind.booking);
      expect(const PlayerHomeData.guest().pendingPayments, isEmpty);
    });
  });

  group('the words of a prompt', () {
    test('a booking says "Payment pending for Guest Booking at <venue>"', () {
      final c = paymentPromptCopy(
        _p(
          PendingPaymentKind.booking,
          title: 'Guest Booking',
          start: DateTime(2026, 11, 6, 17),
        ),
      );
      expect(c.title, 'Payment pending for Guest Booking at Champz Turf');
      expect(c.message, contains('Complete the payment'));
      expect(c.message, contains('Fri, 6 Nov · 5:00 PM'));
      expect(c.button, 'Complete payment');
    });

    test('a failed booking payment asks for a retry', () {
      final c = paymentPromptCopy(
        _p(PendingPaymentKind.booking, title: 'Guest Booking', failed: true),
      );
      expect(c.message, contains("didn't go through"));
      expect(c.button, 'Retry payment');
    });

    test('a membership that is only just unpaid is gentle, a failed or late one says it may be cancelled', () {
      final gentle = paymentPromptCopy(_p(PendingPaymentKind.membership));
      expect(gentle.title, 'Complete your membership payment');
      expect(gentle.message, isNot(contains('cancelled')));
      for (final firm in [
        _p(PendingPaymentKind.membership, failed: true),
        _p(PendingPaymentKind.membership, overdue: true),
      ]) {
        final c = paymentPromptCopy(firm);
        expect(c.title, 'Membership AutoPay not completed');
        expect(c.message, contains('complete the payment now'));
        expect(c.message, contains('may be cancelled'));
      }
    });

    test('coaching says AutoPay for a monthly programme and payment for a one-time one', () {
      expect(
        paymentPromptCopy(_p(PendingPaymentKind.coaching, failed: true)).title,
        'Coaching AutoPay not completed',
      );
      expect(
        paymentPromptCopy(
          _p(PendingPaymentKind.coaching, failed: true, autopay: false),
        ).title,
        'Coaching payment not completed',
      );
    });
  });

  group('prompts on Home', () {
    testWidgets('each unpaid item is a prompt with its own button', (
      tester,
    ) async {
      await _pump(tester, [
        _p(PendingPaymentKind.membership, id: 'm1'),
        _p(
          PendingPaymentKind.coaching,
          id: 'e1',
          title: 'Weekday Badminton Coaching',
          failed: true,
        ),
        _p(PendingPaymentKind.booking, id: 'b1', title: 'Guest Booking'),
      ]);
      expect(
        find.byKey(const ValueKey('prompt-pay-membership-m1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('prompt-pay-coaching-e1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('prompt-pay-booking-b1')),
        findsOneWidget,
      );
      expect(
        find.text('Payment pending for Guest Booking at Champz Turf'),
        findsOneWidget,
      );
      expect(find.text('Coaching AutoPay not completed'), findsOneWidget);
      expect(find.text('Retry payment'), findsOneWidget);
    });

    testWidgets('Complete payment opens the Razorpay page for that item', (
      tester,
    ) async {
      final (repo, _, opened) = await _pump(tester, [
        _p(PendingPaymentKind.booking, id: 'b1', title: 'Guest Booking'),
      ]);
      await tester.tap(find.byKey(const ValueKey('prompt-pay-booking-b1')));
      await tester.pumpAndSettle();
      expect(repo.asked.single.id, 'b1');
      expect(repo.asked.single.kind, PendingPaymentKind.booking);
      expect(opened.single.toString(), 'https://rzp.io/i/abc');
    });

    testWidgets(
      'a payment that already went through refreshes Home instead of opening a page',
      (tester) async {
        final (_, home, opened) = await _pump(tester, [
          _p(PendingPaymentKind.membership, id: 'm1'),
        ], pay: _Pay(link: null));
        await tester.tap(
          find.byKey(const ValueKey('prompt-pay-membership-m1')),
        );
        await tester.pumpAndSettle();
        expect(opened, isEmpty);
        expect(find.byKey(const ValueKey('pay-success')), findsOneWidget);
        expect(home.loads, greaterThan(0));
      },
    );

    testWidgets('a failure shows the reason and opens nothing', (tester) async {
      final (_, _, opened) = await _pump(
        tester,
        [_p(PendingPaymentKind.coaching, id: 'e1')],
        pay: _Pay(
          fail: "This club hasn't turned on monthly AutoPay yet. Please ask the club.",
        ),
      );
      await tester.tap(find.byKey(const ValueKey('prompt-pay-coaching-e1')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining("hasn't turned on monthly AutoPay"),
        findsOneWidget,
      );
      expect(opened, isEmpty);
    });

    testWidgets('works on a phone width', (tester) async {
      await _pump(tester, [
        _p(PendingPaymentKind.membership, failed: true),
        _p(PendingPaymentKind.booking, title: 'Guest Booking'),
      ], size: const Size(390, 800));
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('payment-prompts')), findsOneWidget);
    });

    testWidgets('nothing is shown when nothing is owed', (tester) async {
      await _pump(tester, const []);
      expect(find.byKey(const ValueKey('payment-prompts')), findsNothing);
    });
  });

  group('Home with an unpaid membership and coaching', () {
    Future<void> pumpHome(
      WidgetTester tester,
      Map<String, dynamic> json,
    ) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = ProviderContainer(
        overrides: [
          playerHomeRepositoryProvider.overrideWithValue(_Home()),
          pendingPaymentRepositoryProvider.overrideWithValue(_Pay()),
        ],
      );
      addTearDown(c.dispose);
      final data = PlayerHomeData.fromJson({
        'fullName': 'Test',
        'unreadNotifications': 0,
        ...json,
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: PlayerDashboardDesktop(data: data, onNavigate: (_) {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      addTearDown(() async => tester.pumpWidget(const SizedBox()));
    }

    testWidgets(
      'they stay on the cards, tagged Payment Incomplete instead of Active / Enrolled',
      (tester) async {
        await pumpHome(tester, {
          'memberships': [
            {
              'id': 'm1',
              'planName': 'Monthly Unlimited - Morning',
              'venueName': 'Champz Turf',
              'paymentIncomplete': true,
            },
          ],
          'coaching': [
            {
              'id': 'e1',
              'programName': 'Weekday Badminton Coaching',
              'venueName': 'Champz Turf',
              'paymentIncomplete': true,
            },
          ],
          'pendingPayments': [
            {
              'kind': 'membership',
              'id': 'm1',
              'title': 'Monthly Unlimited - Morning',
              'venueName': 'Champz Turf',
              'state': 'PENDING',
              'overdue': true,
              'mode': 'AUTOPAY',
            },
            {
              'kind': 'coaching',
              'id': 'e1',
              'title': 'Weekday Badminton Coaching',
              'venueName': 'Champz Turf',
              'state': 'FAILED',
              'mode': 'AUTOPAY',
            },
          ],
        });
        expect(find.text('Payment Incomplete'), findsNWidgets(2));
        expect(find.text('Active'), findsNothing);
        expect(find.text('Enrolled'), findsNothing);
        expect(find.text('Monthly Unlimited - Morning'), findsWidgets);
        expect(find.text('Membership AutoPay not completed'), findsOneWidget);
        expect(find.text('Coaching AutoPay not completed'), findsOneWidget);
      },
    );

    testWidgets('a paid one still says Active / Enrolled', (tester) async {
      await pumpHome(tester, {
        'memberships': [
          {'id': 'm1', 'planName': 'Gold', 'venueName': 'Champz Turf'},
        ],
        'coaching': [
          {'id': 'e1', 'programName': 'Juniors', 'venueName': 'Champz Turf'},
        ],
      });
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Enrolled'), findsOneWidget);
      expect(find.text('Payment Incomplete'), findsNothing);
      expect(find.byKey(const ValueKey('payment-prompts')), findsNothing);
    });
  });
}
