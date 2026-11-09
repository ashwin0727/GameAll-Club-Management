import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_player/core/theme/app_theme.dart';
import 'package:gameall_player/features/player_home/domain/player_dashboard_models.dart';
import 'package:gameall_player/features/player_home/presentation/widgets/payment_prompts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

PendingPayment _b(String id, int inr) => PendingPayment(
  kind: PendingPaymentKind.booking,
  id: id,
  title: 'Guest Booking',
  venueName: 'Smash Arena',
  balanceInr: inr,
  startTime: DateTime(2026, 11, 7, 20),
);

Widget _app(Widget child) => ProviderScope(
  child: MaterialApp(theme: AppTheme.dark(), home: Scaffold(body: child)),
);

void main() {
  var now = DateTime(2026, 11, 8, 12);
  setUp(() {
    PaymentPrompts.resetReminder();
    now = DateTime(2026, 11, 8, 12);
    PaymentPrompts.clock = () => now;
  });

  testWidgets('the popup opens with arrows for several payments, Pay enabled', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(PaymentPrompts(payments: [_b('a', 550), _b('b', 1100)], popup: true)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('payment-reminder')), findsOneWidget);
    expect(find.text('Payment pending (1 of 2)'), findsOneWidget);
    expect(find.byKey(const ValueKey('reminder-pay-booking-a')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('reminder-next')));
    await tester.pump();
    expect(find.text('Payment pending (2 of 2)'), findsOneWidget);
    expect(find.byKey(const ValueKey('reminder-pay-booking-b')), findsOneWidget);
    // close: the slim banner stays on Home
    await tester.tap(find.byKey(const ValueKey('reminder-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('payment-reminder')), findsNothing);
    expect(find.text('2 payments pending'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('after closing, it comes back once the gap has passed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(PaymentPrompts(payments: [_b('a', 550)], popup: true)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reminder-close')));
    await tester.pumpAndSettle();
    now = now.add(const Duration(minutes: 2));
    await tester.pump(const Duration(seconds: 25));
    expect(find.byKey(const ValueKey('payment-reminder')), findsNothing);
    now = now.add(const Duration(minutes: 3, seconds: 30));
    await tester.pump(const Duration(seconds: 25));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('payment-reminder')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the banner reopens the popup on tap', (tester) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(PaymentPrompts(payments: [_b('a', 550)], popup: true)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reminder-close')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('payment-prompts')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('payment-reminder')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}

