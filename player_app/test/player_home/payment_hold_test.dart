import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_player/core/theme/app_theme.dart';
import 'package:gameall_player/core/utils/external_links.dart';
import 'package:gameall_player/features/auth/application/auth_providers.dart';
import 'package:gameall_player/features/auth/domain/player_profile.dart';
import 'package:gameall_player/features/payments/application/payment_flow.dart';
import 'package:gameall_player/features/payments/domain/payment_receipt.dart';

import '../support/fake_payment_receipts.dart';

/// The test clock does not move DateTime.now(), so the page is given its own clock that these tests move with [_wait].
DateTime _now = DateTime(2026, 11, 20, 18, 0, 0);

Future<void> _wait(WidgetTester tester, Duration d) async {
  _now = _now.add(d);
  await tester.pump(d);
}

/// A booking that is only a HOLD on the court until it is paid: a 5-minute countdown, an automatic cancel when it runs out, and
/// "Cancel and go back" that gives the court back at once.
Future<List<String>> _pump(
  WidgetTester tester, {
  Duration? holdFor,
  bool withRelease = true,
  PaymentKind kind = PaymentKind.booking,
}) async {
  tester.view.physicalSize = const Size(1000, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final released = <String>[];
  _now = DateTime(2026, 11, 20, 18, 0, 0);
  paymentNow = () => _now;
  addTearDown(() => paymentNow = DateTime.now);
  final c = ProviderContainer(
    overrides: [
      paymentReceiptRepositoryProvider.overrideWithValue(FakePaymentReceipts(paidAfterSyncs: 999)),
      linkOpenerProvider.overrideWithValue((u) async => true),
      currentPlayerProvider.overrideWithValue(const PlayerProfile(id: 'p1', fullName: 'Arun', phone: '9000000001')),
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
                    kind: kind,
                    title: 'Badminton booking',
                    venueName: 'Smash Arena',
                    holdFor: holdFor,
                    releaseHold: withRelease
                        ? (id) async {
                            released.add(id);
                          }
                        : null,
                    prepare: () async => PaymentTarget(id: 'b1', link: Uri.parse('https://rzp.io/i/x')),
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
  await tester.tap(find.byKey(const ValueKey('go')));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
  return released;
}

void main() {
  testWidgets('a held booking shows a countdown for the 5 minutes', (tester) async {
    await _pump(tester, holdFor: const Duration(minutes: 5));
    expect(find.byKey(const ValueKey('pay-hold-countdown')), findsOneWidget);
    expect(find.textContaining('Complete your payment in 05:00'), findsOneWidget);
    await _wait(tester, const Duration(seconds: 61));
    expect(find.textContaining('Complete your payment in 03:5'), findsOneWidget);
  });

  testWidgets('"Cancel and go back" gives the court back at once and leaves the page', (tester) async {
    final released = await _pump(tester, holdFor: const Duration(minutes: 5));
    expect(released, isEmpty);
    await tester.tap(find.byKey(const ValueKey('pay-cancel')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(released, ['b1']);
    expect(find.byKey(const ValueKey('pay-progress')), findsNothing);
  });

  testWidgets('when the time is up the booking is cancelled by itself and the player is told', (tester) async {
    final released = await _pump(tester, holdFor: const Duration(seconds: 3));
    expect(released, isEmpty);
    await _wait(tester, const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 200));
    expect(released, ['b1']);
    expect(find.text('Time is up'), findsOneWidget);
    expect(find.byKey(const ValueKey('pay-hold-countdown')), findsNothing);
    expect(find.byKey(const ValueKey('pay-check-now')), findsNothing);
    // "Back" just leaves: the court is already free
    await tester.tap(find.byKey(const ValueKey('pay-cancel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pay-progress')), findsNothing);
    expect(released, ['b1']);
  });

  testWidgets('a payment that is not a held booking has no countdown and never cancels anything', (tester) async {
    final released = await _pump(tester, withRelease: false, kind: PaymentKind.membership);
    expect(find.byKey(const ValueKey('pay-hold-countdown')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('pay-cancel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pay-progress')), findsNothing);
    expect(released, isEmpty);
  });
}
