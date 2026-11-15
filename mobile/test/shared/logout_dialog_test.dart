import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/shared/widgets/logout_dialog.dart';

void main() {
  Future<void> open(WidgetTester tester, ValueSetter<bool> result) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(body: Center(child: TextButton(onPressed: () async => result(await confirmLogout(context)), child: const Text('Log out')))),
      ),
    ));
    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();
  }

  testWidgets('asks first, and Log Out is the only way to confirm', (tester) async {
    bool? answer;
    await open(tester, (v) => answer = v);
    expect(find.text('Log Out?'), findsOneWidget);
    expect(find.text('Are you sure you want to log out of your GameAll account?'), findsOneWidget);
    expect(answer, isNull);

    await tester.tap(find.byKey(const ValueKey('logout-confirm')));
    await tester.pumpAndSettle();
    expect(answer, isTrue);
  });

  testWidgets('Cancel and the close button leave you signed in', (tester) async {
    bool? answer;
    await open(tester, (v) => answer = v);
    await tester.tap(find.byKey(const ValueKey('logout-cancel')));
    await tester.pumpAndSettle();
    expect(answer, isFalse);

    answer = null;
    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('logout-close')));
    await tester.pumpAndSettle();
    expect(answer, isFalse);
  });
}
