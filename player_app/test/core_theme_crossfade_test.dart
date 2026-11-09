import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_player/core/widgets/theme_crossfade.dart';

void main() {
  testWidgets('a theme switch fades the old look away and leaves no overlay', (
    tester,
  ) async {
    Widget app(ThemeMode m) => MaterialApp(
      themeMode: m,
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      themeAnimationDuration: Duration.zero,
      builder: (context, child) => ThemeCrossfade(mode: m, child: child!),
      home: const Scaffold(body: Center(child: Text('Hello'))),
    );
    await tester.pumpWidget(app(ThemeMode.dark));
    expect(find.byType(RawImage), findsNothing);
    await tester.pumpWidget(app(ThemeMode.light));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(RawImage), findsOneWidget);
    expect(find.text('Hello'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(find.byType(RawImage), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
