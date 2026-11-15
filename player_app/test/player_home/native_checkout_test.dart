import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_player/core/theme/app_theme.dart';
import 'package:gameall_player/core/utils/external_links.dart';
import 'package:gameall_player/features/auth/application/auth_providers.dart';
import 'package:gameall_player/features/auth/domain/player_profile.dart';
import 'package:gameall_player/features/payments/application/payment_flow.dart';
import 'package:gameall_player/features/payments/data/native_checkout.dart';
import 'package:gameall_player/features/payments/data/receipt_pdf.dart';
import 'package:gameall_player/features/payments/domain/payment_receipt.dart';

import '../support/fake_payment_receipts.dart';

/// What the page did with the in-app payment sheet.
class _Sheet {
  _Sheet(this.result);
  CheckoutResult result;
  final opened = <CheckoutRequest>[];
  final verified = <(CheckoutRequest, CheckoutPaid)>[];
  final browser = <Uri>[];
}

const _booking = CheckoutRequest(
  kind: PaymentKind.booking,
  itemId: 'b1',
  keyId: 'rzp_test_key',
  orderId: 'order_1',
  paymentOrderId: 'po1',
  amountMinor: 50000,
  description: 'Court booking',
);

Future<_Sheet> _pump(
  WidgetTester tester, {
  required CheckoutResult result,
  FakePaymentReceipts? fake,
  CheckoutRequest request = _booking,
}) async {
  tester.view.physicalSize = const Size(1000, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  CheckoutStore.instance.clear();
  addTearDown(CheckoutStore.instance.clear);
  final sheet = _Sheet(result);
  final hosted = Uri.parse('https://rzp.io/i/x');
  final link = CheckoutStore.instance.register(request, hostedPage: hosted);
  final c = ProviderContainer(
    overrides: [
      paymentReceiptRepositoryProvider.overrideWithValue(
        fake ?? FakePaymentReceipts(paidAfterSyncs: 1),
      ),
      linkOpenerProvider.overrideWithValue((u) async {
        sheet.browser.add(u);
        return true;
      }),
      nativeCheckoutProvider.overrideWithValue((r) async {
        sheet.opened.add(r);
        return sheet.result;
      }),
      checkoutVerifierProvider.overrideWithValue((r, p) async {
        sheet.verified.add((r, p));
        return true;
      }),
      receiptSaverProvider.overrideWithValue((b, n) async {}),
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
                  onNavigate: (_) {},
                  job: PaymentJob(
                    kind: request.kind,
                    title: 'Court booking',
                    venueName: 'Ace Arena',
                    prepare: () async =>
                        PaymentTarget(id: request.itemId, link: link),
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
  return sheet;
}

void main() {
  group('the payment page opens the in-app sheet, not the browser', () {
    testWidgets(
      'a paid sheet is checked by the server, then the receipt is looked up and the success page opens',
      (tester) async {
        final s = await _pump(
          tester,
          result: const CheckoutPaid(
            paymentId: 'pay_1',
            signature: 'sig',
            orderId: 'order_1',
          ),
        );
        await tester.tap(find.byKey(const ValueKey('go')));
        await tester.pumpAndSettle();
        expect(s.opened.single.orderId, 'order_1');
        // the sheet is told who pays, so it opens on the payment options and never asks for a mobile number or email
        expect(s.opened.single.contact, '+919000000001');
        expect(s.opened.single.name, 'Arun');
        expect(s.opened.single.email, 'player.9000000001@gameall.co');
        expect(s.browser, isEmpty, reason: 'no web page is opened');
        expect(s.verified, hasLength(1));
        expect(s.verified.single.$2.paymentId, 'pay_1');
        expect(find.byKey(const ValueKey('pay-success')), findsOneWidget);
      },
    );

    testWidgets(
      'closing the sheet is not a payment: nothing is verified and the player can try again',
      (tester) async {
        final s = await _pump(
          tester,
          result: const CheckoutCancelled(),
          fake: FakePaymentReceipts(paidAfterSyncs: 99),
        );
        await tester.tap(find.byKey(const ValueKey('go')));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        expect(s.verified, isEmpty);
        expect(find.byKey(const ValueKey('pay-success')), findsNothing);
        expect(find.byKey(const ValueKey('pay-progress')), findsOneWidget);
        expect(find.textContaining('was not completed'), findsOneWidget);
        expect(s.browser, isEmpty);
      },
    );

    testWidgets('a failed payment says why and verifies nothing', (
      tester,
    ) async {
      final s = await _pump(
        tester,
        result: const CheckoutFailed('Your bank declined the payment.'),
        fake: FakePaymentReceipts(paidAfterSyncs: 99),
      );
      await tester.tap(find.byKey(const ValueKey('go')));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(s.verified, isEmpty);
      expect(find.text('Your bank declined the payment.'), findsOneWidget);
    });

    testWidgets(
      'a payment the server could not verify is still decided by the database, not by the sheet',
      (tester) async {
        // the sheet says paid, but the receipt never shows it: no success page
        final s = await _pump(
          tester,
          result: const CheckoutPaid(paymentId: 'pay_x', signature: 'forged'),
          fake: FakePaymentReceipts(paidAfterSyncs: 99),
        );
        await tester.tap(find.byKey(const ValueKey('go')));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        expect(s.verified, hasLength(1));
        expect(find.byKey(const ValueKey('pay-success')), findsNothing);
      },
    );
  });

  group('checkoutLinkFrom', () {
    setUp(CheckoutStore.instance.clear);

    test('a booking order becomes a sheet under a made-up address', () {
      final link = checkoutLinkFrom(
        {
          'paymentOrderId': 'po1',
          'checkout': {
            'keyId': 'rzp_test_key',
            'orderId': 'order_1',
            'amountMinor': 50000,
          },
        },
        kind: PaymentKind.booking,
        itemId: 'b1',
        description: 'Court booking',
      );
      expect(link, isNotNull);
      expect(link!.scheme, 'gameall-checkout');
      final r = CheckoutStore.instance.forLink(link)!;
      expect(r.orderId, 'order_1');
      expect(r.paymentOrderId, 'po1');
      expect(r.amountMinor, 50000);
      expect(r.isSubscription, isFalse);
    });

    test('an AutoPay subscription becomes a sheet, keeping the hosted page as the address', () {
      final link = checkoutLinkFrom(
        {
          'keyId': 'rzp_test_key',
          'subscriptionId': 'sub_1',
          'shortUrl': 'https://rzp.io/i/sub',
        },
        kind: PaymentKind.membership,
        itemId: 'm1',
        description: 'Membership AutoPay',
      );
      expect(link.toString(), 'https://rzp.io/i/sub');
      final r = CheckoutStore.instance.forLink(link)!;
      expect(r.subscriptionId, 'sub_1');
      expect(r.isSubscription, isTrue);
    });

    test('a one-time payment link (no order, no subscription) stays a hosted page', () {
      final link = checkoutLinkFrom(
        {'shortUrl': 'https://rzp.io/i/one'},
        kind: PaymentKind.coaching,
        itemId: 'e1',
        description: 'Coaching fee',
      );
      expect(link.toString(), 'https://rzp.io/i/one');
      expect(CheckoutStore.instance.forLink(link), isNull);
    });

    test('nothing usable in the answer gives no address', () {
      expect(
        checkoutLinkFrom(
          const {},
          kind: PaymentKind.booking,
          itemId: 'b1',
          description: 'x',
        ),
        isNull,
      );
    });

    test('off Android the sheet is never used: the hosted page is', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final link = checkoutLinkFrom(
        {
          'keyId': 'rzp_test_key',
          'subscriptionId': 'sub_1',
          'shortUrl': 'https://rzp.io/i/sub',
        },
        kind: PaymentKind.membership,
        itemId: 'm1',
        description: 'Membership AutoPay',
      );
      expect(link.toString(), 'https://rzp.io/i/sub');
      expect(CheckoutStore.instance.forLink(link), isNull);
    });
  });
}
