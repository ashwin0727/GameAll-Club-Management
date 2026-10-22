import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/core/theme/app_theme.dart';
import 'package:gameall_club_mobile/shared/widgets/app_dropdown.dart';
import 'package:gameall_club_mobile/shared/widgets/smooth_switcher.dart';

Widget _host(Widget child) => MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: child)),
    );

void main() {
  testWidgets('shows the hint, opens a list under the field and reports the pick', (tester) async {
    String? picked;
    await tester.pumpWidget(_host(
      AppDropdown<String>(
        hint: const Text('Select Your Gender'),
        items: const [
          DropdownMenuItem(value: 'm', child: Text('Male')),
          DropdownMenuItem(value: 'f', child: Text('Female')),
        ],
        onChanged: (v) => picked = v,
      ),
    ));
    expect(find.text('Select Your Gender'), findsOneWidget);

    await tester.tap(find.text('Select Your Gender'));
    await tester.pumpAndSettle();
    expect(find.text('Male'), findsOneWidget);
    expect(find.text('Female'), findsOneWidget);

    await tester.tap(find.text('Female'));
    await tester.pumpAndSettle();
    expect(picked, 'f');
    // The chosen value now sits in the field, and the list has closed.
    expect(find.text('Female'), findsOneWidget);
    expect(find.text('Male'), findsNothing);
  });

  testWidgets('works as a form field: a validator blocks an empty choice', (tester) async {
    final key = GlobalKey<FormState>();
    await tester.pumpWidget(_host(
      Form(
        key: key,
        child: AppDropdown<String>(
          decoration: const InputDecoration(labelText: 'Gender'),
          validator: (v) => v == null ? 'Choose one' : null,
          items: const [DropdownMenuItem(value: 'm', child: Text('Male'))],
          onChanged: (_) {},
        ),
      ),
    ));
    expect(key.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('Choose one'), findsOneWidget);
  });

  testWidgets('a disabled dropdown does not open', (tester) async {
    await tester.pumpWidget(_host(
      AppDropdown<String>(
        hint: const Text('Pick'),
        items: const [DropdownMenuItem(value: 'a', child: Text('A'))],
        onChanged: null,
      ),
    ));
    await tester.tap(find.text('Pick'));
    await tester.pumpAndSettle();
    expect(find.text('A'), findsNothing);
  });

  testWidgets('SmoothSwitcher fades a new child in and removes the old one', (tester) async {
    Widget build(bool loading) => _host(SmoothSwitcher(child: loading ? const Text('loading', key: ValueKey('l')) : const Text('ready', key: ValueKey('r'))));
    await tester.pumpWidget(build(true));
    expect(find.text('loading'), findsOneWidget);
    await tester.pumpWidget(build(false));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('ready'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('loading'), findsNothing);
  });
}
