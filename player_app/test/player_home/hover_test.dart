import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_player/core/theme/app_theme.dart';
import 'package:gameall_player/core/widgets/gameall_buttons.dart';
import 'package:gameall_player/core/widgets/hover_scope.dart';
import 'package:gameall_player/core/widgets/pressable.dart';

Future<TestGesture> mouse(WidgetTester tester) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: const Offset(1, 1));
  addTearDown(gesture.removePointer);
  return gesture;
}

FontWeight? weightOf(WidgetTester tester, String text) {
  final animated = tester.widget<AnimatedDefaultTextStyle>(find.ancestor(of: find.text(text), matching: find.byType(AnimatedDefaultTextStyle)).first);
  return animated.style.fontWeight;
}

void main() {
  for (final entry in {'dark': AppTheme.dark(), 'light': AppTheme.light()}.entries) {
    test('the ${entry.key} theme never shades a surface on hover or press', () {
      final t = entry.value;
      expect(t.hoverColor, Colors.transparent);
      expect(t.highlightColor, Colors.transparent);
      expect(t.splashColor, Colors.transparent);
      expect(t.splashFactory, NoSplash.splashFactory);
    });
  }

  testWidgets('text inside a link is light at rest and a little heavier under the mouse', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: Center(
          child: Pressable(onTap: () {}, child: const Padding(padding: EdgeInsets.all(20), child: HoverText('Venues', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)))),
        ),
      ),
    ));
    final g = await mouse(tester);

    expect(weightOf(tester, 'Venues'), FontWeight.w500);

    await g.moveTo(tester.getCenter(find.text('Venues')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(weightOf(tester, 'Venues'), FontWeight.w600);

    await g.moveTo(const Offset(5, 5));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(weightOf(tester, 'Venues'), FontWeight.w500);
  });

  testWidgets('a button label does the same, and the button paints no hover shade', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: Center(child: GameAllButton.gradient(label: 'Find a Court', onPressed: () {}))),
    ));
    final g = await mouse(tester);
    expect(weightOf(tester, 'Find a Court'), FontWeight.w600);

    await g.moveTo(tester.getCenter(find.text('Find a Court')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(weightOf(tester, 'Find a Court'), FontWeight.w700);

    // the tap target itself has no hover / press colour
    final ink = tester.widget<InkWell>(find.descendant(of: find.byType(Pressable), matching: find.byType(InkWell)));
    expect(ink.hoverColor, Colors.transparent);
    expect(ink.highlightColor, Colors.transparent);
    expect(ink.splashColor, Colors.transparent);
  });

  testWidgets('a disabled button does not react to the mouse', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: AppTheme.dark(), home: const Scaffold(body: Center(child: GameAllButton(label: 'Unavailable', onPressed: null)))));
    final g = await mouse(tester);
    final before = weightOf(tester, 'Unavailable');
    await g.moveTo(tester.getCenter(find.text('Unavailable')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(weightOf(tester, 'Unavailable'), before);
  });

  testWidgets('HoverRegion shares the hover with the text inside list rows', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: Center(child: HoverRegion(child: SizedBox(width: 200, height: 60, child: Center(child: HoverText('Chennai, Tamil Nadu', style: TextStyle(fontWeight: FontWeight.w500))))))),
    ));
    final g = await mouse(tester);
    await g.moveTo(tester.getCenter(find.byType(HoverRegion)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(weightOf(tester, 'Chennai, Tamil Nadu'), FontWeight.w600);
  });
}
