import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_player/core/theme/app_theme.dart';
import 'package:gameall_player/features/venues/presentation/payment_option_sheet.dart';

Future<String?> _open(
  WidgetTester tester, {
  int? totalMinor,
  Size size = const Size(390, 844),
  double text = 1.0,
  required Future<void> Function() act,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  String? result = 'unset';
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: MediaQuery(
        data: MediaQueryData(size: size, textScaler: TextScaler.linear(text)),
        child: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  result = await showPaymentOptionSheet(context, totalMinor: totalMinor),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
  await act();
  return result;
}

void main() {
  testWidgets('shows both options with the amounts and the refund rules', (
    tester,
  ) async {
    await _open(
      tester,
      totalMinor: 120000,
      act: () async {
        expect(find.text('Pay 50% now'), findsOneWidget);
        expect(find.text('Pay full amount'), findsOneWidget);
        expect(find.text('₹600 now  ·  ₹600 later'), findsOneWidget);
        expect(find.text('₹1,200 now'), findsOneWidget);
        // nothing chosen yet: the button says so and does nothing
        expect(find.text('Choose an option'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('pay-opt-rules')));
        await tester.pumpAndSettle();
        expect(find.text('Cancel with 12 hours or more left'), findsOneWidget);
        expect(find.text('100% deducted'), findsOneWidget);
      },
    );
  });

  testWidgets('choosing 50% returns ADVANCE and the button shows what is paid now', (
    tester,
  ) async {
    String? got;
    await _open(
      tester,
      totalMinor: 100100,
      act: () async {
        await tester.tap(find.byKey(const ValueKey('pay-opt-advance')));
        await tester.pump();
        // half of 1,001 rounds up
        expect(find.text('Continue · ₹501'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('pay-opt-continue')));
        await tester.pumpAndSettle();
      },
    ).then((r) => got = r);
    expect(got, 'ADVANCE');
  });

  testWidgets('choosing the full amount returns FULL', (tester) async {
    final r = await _open(
      tester,
      totalMinor: 50000,
      act: () async {
        await tester.tap(find.byKey(const ValueKey('pay-opt-full')));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('pay-opt-continue')));
        await tester.pumpAndSettle();
      },
    );
    expect(r, 'FULL');
  });

  testWidgets('an unknown price still works, and a small phone with large text does not overflow', (
    tester,
  ) async {
    await _open(
      tester,
      totalMinor: null,
      size: const Size(320, 640),
      text: 1.4,
      act: () async {
        expect(find.text('Half now, the rest later'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
