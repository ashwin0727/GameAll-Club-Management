import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/shared/widgets/day_chip.dart';

void main() {
  testWidgets('a selected day shows a tick and reports the new value when tapped', (tester) async {
    bool? changed;
    var selected = false;
    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(
        builder: (context, setState) => Scaffold(
          body: DayChip(label: 'Mon', selected: selected, onChanged: (v) => setState(() {
            selected = v;
            changed = v;
          })),
        ),
      ),
    ));
    expect(find.byIcon(Icons.check_rounded), findsNothing);
    await tester.tap(find.text('Mon'));
    await tester.pump();
    expect(changed, true);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    await tester.tap(find.text('Mon'));
    await tester.pump();
    expect(changed, false);
    expect(find.byIcon(Icons.check_rounded), findsNothing);
  });
}
