import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/features/onboarding/submit_review_dialog.dart';

void main() {
  Future<void> open(WidgetTester tester, ValueSetter<bool> result) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(body: Center(child: TextButton(onPressed: () async => result(await confirmSubmitForReview(context)), child: const Text('Complete Setup')))),
      ),
    ));
    await tester.tap(find.text('Complete Setup'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows both statements and cannot be submitted until both are ticked', (tester) async {
    bool? answer;
    await open(tester, (v) => answer = v);

    expect(find.text('Confirm & Submit for Review'), findsOneWidget);
    expect(find.textContaining('Terms and Conditions', findRichText: true), findsOneWidget);
    expect(find.textContaining('Privacy Policy', findRichText: true), findsOneWidget);

    // nothing happens while a statement is still unticked
    await tester.ensureVisible(find.byKey(const ValueKey('submit-for-review')));
    await tester.tap(find.byKey(const ValueKey('submit-for-review')));
    await tester.pumpAndSettle();
    expect(answer, isNull);

    await tester.ensureVisible(find.byKey(const ValueKey('confirm-accurate')));
    await tester.tap(find.byKey(const ValueKey('confirm-accurate')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('submit-for-review')));
    await tester.tap(find.byKey(const ValueKey('submit-for-review')));
    await tester.pumpAndSettle();
    expect(answer, isNull, reason: 'the terms are still unticked');

    // tapped on its box: tapping the middle of the row could land on a link
    final termsBox = find.descendant(of: find.byKey(const ValueKey('confirm-terms')), matching: find.byType(Checkbox));
    await tester.ensureVisible(termsBox);
    await tester.tapAt(tester.getCenter(termsBox));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('submit-for-review')));
    await tester.tap(find.byKey(const ValueKey('submit-for-review')));
    await tester.pumpAndSettle();
    expect(answer, isTrue);
  });

  testWidgets('Cancel and the close button leave the setup unsubmitted', (tester) async {
    bool? answer;
    await open(tester, (v) => answer = v);
    await tester.ensureVisible(find.byKey(const ValueKey('submit-cancel')));
    await tester.tap(find.byKey(const ValueKey('submit-cancel')));
    await tester.pumpAndSettle();
    expect(answer, isFalse);

    answer = null;
    await tester.tap(find.text('Complete Setup'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('submit-close')));
    await tester.pumpAndSettle();
    expect(answer, isFalse);
  });
}
