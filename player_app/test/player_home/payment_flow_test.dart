import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_player/core/theme/app_theme.dart';
import 'package:gameall_player/core/utils/external_links.dart';
import 'package:gameall_player/features/auth/application/auth_providers.dart';
import 'package:gameall_player/features/auth/domain/player_profile.dart';
import 'package:gameall_player/features/payments/application/payment_flow.dart';
import 'package:gameall_player/features/payments/data/receipt_pdf.dart';
import 'package:gameall_player/features/payments/domain/payment_receipt.dart';
import 'package:gameall_player/features/player_home/domain/player_dashboard_models.dart';

import '../support/fake_payment_receipts.dart';

class _Harness {
  _Harness(this.fake);
  final FakePaymentReceipts fake;
  final opened = <Uri>[];
  final routes = <String>[];
  final saved = <(Uint8List, String)>[];
  bool openOk = true;
}

class _Boom implements Exception {
  const _Boom(this.message);
  final String message;
}

Future<_Harness> _pump(
  WidgetTester tester, {
  FakePaymentReceipts? fake,
  Future<PaymentTarget> Function()? prepare,
  PaymentKind kind = PaymentKind.membership,
  bool openOk = true,
  bool balance = false,
}) async {
  tester.view.physicalSize = const Size(1000, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final h = _Harness(fake ?? FakePaymentReceipts())..openOk = openOk;
  final c = ProviderContainer(
    overrides: [
      paymentReceiptRepositoryProvider.overrideWithValue(h.fake),
      linkOpenerProvider.overrideWithValue((u) async {
        h.opened.add(u);
        return h.openOk;
      }),
      receiptSaverProvider.overrideWithValue(
        (b, n) async => h.saved.add((b, n)),
      ),
      receiptLogoProvider.overrideWithValue(() async => null),
      currentPlayerProvider.overrideWithValue(
        const PlayerProfile(id: 'p1', fullName: 'Arun', phone: '9000000001'),
      ),
    ],
  );
  addTearDown(c.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const ValueKey('go'),
                onPressed: () => openPaymentFlow(
                  context,
                  onNavigate: h.routes.add,
                  job: PaymentJob(
                    kind: kind,
                    title: 'Court Time Membership',
                    venueName: 'Ace Arena',
                    balance: balance,
                    prepare:
                        prepare ??
                        () async => PaymentTarget(
                          id: 'm1',
                          link: Uri.parse('https://rzp.io/i/x'),
                        ),
                  ),
                ),
                child: const Text('Pay'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  addTearDown(() async => tester.pumpWidget(const SizedBox()));
  return h;
}

void main() {
  balanceTests();
  logoTests();
  testWidgets(
    'a pay button shows the progress page with a spinner while the payment is awaited',
    (tester) async {
      final h = await _pump(
        tester,
        fake: FakePaymentReceipts(paidAfterSyncs: 99),
      );
      await tester.tap(find.byKey(const ValueKey('go')));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('pay-progress')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      expect(h.opened.single.toString(), 'https://rzp.io/i/x');
      expect(find.text('Waiting for your payment…'), findsOneWidget);
      expect(find.byKey(const ValueKey('pay-check-now')), findsOneWidget);
    },
  );

  testWidgets(
    'once the payment is received the success page opens by itself, with the details',
    (tester) async {
      final h = await _pump(
        tester,
        fake: FakePaymentReceipts(paidAfterSyncs: 2),
      );
      await tester.tap(find.byKey(const ValueKey('go')));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pay-progress')), findsNothing);
      expect(find.byKey(const ValueKey('pay-success')), findsOneWidget);
      expect(find.text('Payment Successful'), findsOneWidget);
      expect(find.text('₹1,400'), findsOneWidget);
      expect(find.text('RCP-1A2B3C4D'), findsOneWidget);
      expect(find.text('pay_TEST123'), findsOneWidget);
      expect(find.text('MBR-ACE-000012'), findsOneWidget);
      expect(find.text('Ace Arena'), findsWidgets);
      expect(h.routes, isEmpty);
    },
  );

  testWidgets(
    '"I have paid" checks at once and the download button saves a PDF receipt',
    (tester) async {
      final h = await _pump(
        tester,
        fake: FakePaymentReceipts(paidAfterSyncs: 1),
      );
      await tester.tap(find.byKey(const ValueKey('go')));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const ValueKey('pay-check-now')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pay-success')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('pay-download')));
      await tester.tap(find.byKey(const ValueKey('pay-download')));
      await tester.pumpAndSettle();
      expect(h.saved, hasLength(1));
      final (bytes, name) = h.saved.single;
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
      expect(name, 'GameAll-Receipt-RCP-1A2B3C4D.pdf');
    },
  );

  testWidgets(
    '"View membership" leaves the payment pages and opens the membership',
    (tester) async {
      final h = await _pump(
        tester,
        fake: FakePaymentReceipts(paidAfterSyncs: 1),
      );
      await tester.tap(find.byKey(const ValueKey('go')));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const ValueKey('pay-check-now')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('pay-view')));
      await tester.tap(find.byKey(const ValueKey('pay-view')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pay-success')), findsNothing);
      expect(h.routes, hasLength(1));
      expect(h.routes.single, contains('membership'));
    },
  );

  testWidgets(
    'a failure to prepare shows the reason, with Try again and Cancel',
    (tester) async {
      await _pump(
        tester,
        prepare: () async => throw const _Boom('This membership is full.'),
      );
      await tester.tap(find.byKey(const ValueKey('go')));
      await tester.pumpAndSettle();
      expect(find.text('This membership is full.'), findsOneWidget);
      expect(find.byKey(const ValueKey('pay-retry')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pay-cancel')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pay-progress')), findsNothing);
      expect(find.byKey(const ValueKey('go')), findsOneWidget);
    },
  );

  testWidgets('a blocked payment page is reported, not silently ignored', (
    tester,
  ) async {
    await _pump(tester, openOk: false);
    await tester.tap(find.byKey(const ValueKey('go')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining("couldn't open the payment page"),
      findsOneWidget,
    );
  });

  testWidgets(
    'a coaching payment shows coaching details and no membership button',
    (tester) async {
      await _pump(
        tester,
        kind: PaymentKind.coaching,
        fake: FakePaymentReceipts(paidAfterSyncs: 2),
      );
      await tester.tap(find.byKey(const ValueKey('go')));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();
      expect(find.text('Coaching details'), findsOneWidget);
      expect(find.text('Coach Arjun'), findsOneWidget);
      expect(find.byKey(const ValueKey('pay-view')), findsNothing);
    },
  );

  test('receipt PDF builds for every kind', () async {
    for (final k in PaymentKind.values) {
      final r = await FakePaymentReceipts().receipt(k, 'x');
      final bytes = await buildReceiptPdf(
        r!,
        playerName: 'Arun',
        playerPhone: '9000000001',
      );
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    }
  });

  test('inrText uses Rs. for the PDF fonts', () {
    expect(inrText(1400), 'Rs. 1,400');
  });
}

void logoTests() {
  testWidgets(
    'the receipt PDF carries the GameAll logo image when the logo loads',
    (tester) async {
      await tester.runAsync(() async {
        final logo = await loadReceiptLogoPng();
        expect(logo, isNotNull, reason: 'the app logo decodes to PNG');
        expect(logo!.take(4).toList(), [0x89, 0x50, 0x4E, 0x47]);
        final r = await FakePaymentReceipts().receipt(
          PaymentKind.coaching,
          'x',
        );
        final withLogo = await buildReceiptPdf(r!, logoPng: logo);
        final without = await buildReceiptPdf(r);
        expect(String.fromCharCodes(withLogo.take(4)), '%PDF');
        expect(String.fromCharCodes(withLogo), contains('/Subtype/Image'));
        expect(
          String.fromCharCodes(without),
          isNot(contains('/Subtype/Image')),
        );
      });
    },
  );
}

void balanceTests() {
  test(
    'a booking prompt with a balance asks for the balance, with the amount',
    () {
      final p = PendingPayment.fromJson({
        'kind': 'booking',
        'id': 'b1',
        'title': 'Guest Booking',
        'venueName': 'Smash Arena',
        'state': 'PENDING',
        'overdue': false,
        'startTime': '2026-11-07T14:30:00Z',
        'mode': 'LINK',
        'balance': true,
        'balanceInr': 550,
      });
      expect(p.isBalance, isTrue);
      expect(p.balanceInr, 550);
      final c = paymentPromptCopy(p);
      expect(
        c.title,
        'Balance payment pending for Guest Booking at Smash Arena',
      );
      expect(c.message, contains('₹550'));
      expect(c.message, contains('about to end'));
      expect(c.button, 'Pay balance');
    },
  );

  test('once the booking has ended the balance prompt says so', () {
    final p = PendingPayment.fromJson({
      'kind': 'booking',
      'id': 'b1',
      'title': 'Guest Booking',
      'venueName': 'Smash Arena',
      'state': 'PENDING',
      'overdue': true,
      'mode': 'LINK',
      'balance': true,
      'balanceInr': 550,
    });
    expect(paymentPromptCopy(p).message, contains('has ended'));
    expect(p.urgent, isTrue);
  });

  test('a booking that is not paid at all still gets the ordinary prompt', () {
    final p = PendingPayment.fromJson({
      'kind': 'booking',
      'id': 'b1',
      'title': 'Guest Booking',
      'venueName': 'X',
      'state': 'PENDING',
      'mode': 'LINK',
    });
    expect(p.isBalance, isFalse);
    expect(paymentPromptCopy(p).button, 'Complete payment');
  });

  testWidgets(
    'a balance payment waits for the WHOLE amount, not the advance that is already in',
    (tester) async {
      // the receipt already says PAID (the advance), but only 550 of 1,100 is in
      final fake = _BalanceReceipts();
      final h = await _pump(tester, fake: fake, balance: true);
      await tester.tap(find.byKey(const ValueKey('go')));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.byKey(const ValueKey('pay-success')),
        findsNothing,
        reason: 'the advance alone is not the balance',
      );
      expect(h.opened, hasLength(1));
      expect(
        find.text('₹550'),
        findsOneWidget,
        reason: 'the page shows the balance, not the total',
      );
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pay-success')), findsOneWidget);
      expect(find.text('Balance Paid'), findsOneWidget);
    },
  );
}

class _BalanceReceipts extends FakePaymentReceipts {
  _BalanceReceipts() : super(kindOverride: PaymentKind.booking);

  PaymentReceipt _r(int paid, int syncs) => PaymentReceipt(
    kind: PaymentKind.booking,
    id: 'b1',
    state: PaymentState.paid,
    title: 'Badminton booking',
    venueName: 'Smash Arena',
    totalInr: 1100,
    paidInr: paid,
    amountInr: paid == 1100 ? 550 : 550,
    receiptNo: 'RCP-AAAA1111',
    paidAt: DateTime(2026, 11, 7, 20),
  );

  @override
  Future<PaymentReceipt?> receipt(PaymentKind kind, String id) async =>
      _r(syncs >= 2 ? 1100 : 550, syncs);
}
