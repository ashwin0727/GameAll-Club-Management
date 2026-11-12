import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/features/onboarding/setup_ui.dart';

const _states = ['Andhra Pradesh', 'Assam', 'Bihar', 'Delhi', 'Goa', 'Gujarat', 'Karnataka', 'Kerala', 'Maharashtra', 'Tamil Nadu', 'Telangana', 'West Bengal'];
const _types = ['Indoor', 'Outdoor', 'Hybrid'];

class _Host extends StatefulWidget {
  const _Host({required this.options, this.initial, this.validator, this.formKey, this.onPicked});

  final List<String> options;
  final String? initial;
  final String? Function(String?)? validator;
  final GlobalKey<FormState>? formKey;
  final ValueChanged<String?>? onPicked;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late String? value = widget.initial;

  void setExternally(String? v) => setState(() => value = v);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Form(
          key: widget.formKey,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SetupDropdown<String>(
              label: 'State',
              hint: 'Select state',
              value: value,
              required: true,
              validator: widget.validator,
              items: [for (final o in widget.options) DropdownMenuItem(value: o, child: Text(o))],
              onChanged: (v) {
                setState(() => value = v);
                widget.onPicked?.call(v);
              },
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('select-State')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the hint until something is chosen', (tester) async {
    await tester.pumpWidget(const _Host(options: _states));
    expect(find.text('Select state'), findsOneWidget);
  });

  testWidgets('always shows the current value, including one the screen sets itself (a prefill, or coming Back)', (tester) async {
    await tester.pumpWidget(const _Host(options: _states, initial: 'Kerala'));
    expect(find.text('Kerala'), findsOneWidget);

    tester.state<_HostState>(find.byType(_Host)).setExternally('Goa');
    await tester.pump();
    expect(find.text('Goa'), findsOneWidget);
    expect(find.text('Kerala'), findsNothing);

    tester.state<_HostState>(find.byType(_Host)).setExternally(null);
    await tester.pump();
    expect(find.text('Select state'), findsOneWidget);
  });

  testWidgets('tapping it opens every option in a list from the bottom, the chosen one highlighted with a tick', (tester) async {
    await tester.pumpWidget(const _Host(options: _types, initial: 'Outdoor'));
    await _open(tester);

    for (final t in _types) {
      expect(find.text(t), findsWidgets, reason: t);
    }
    // the chosen row has a tick; the others do not
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.descendant(of: find.widgetWithText(Material, 'Outdoor').last, matching: find.byIcon(Icons.check)), findsOneWidget);
  });

  testWidgets('choosing an option closes the list, shows it in the field and tells the screen', (tester) async {
    String? picked;
    await tester.pumpWidget(_Host(options: _types, onPicked: (v) => picked = v));
    await _open(tester);

    await tester.tap(find.text('Hybrid').last);
    await tester.pumpAndSettle();

    expect(picked, 'Hybrid');
    expect(find.text('Hybrid'), findsOneWidget); // only in the field now: the list is gone
    expect(find.byIcon(Icons.check), findsNothing);
  });

  testWidgets('a short list has no search box', (tester) async {
    await tester.pumpWidget(const _Host(options: _types));
    await _open(tester);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('a long list (states, banks) gets a search box that narrows it', (tester) async {
    await tester.pumpWidget(const _Host(options: _states));
    await _open(tester);

    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'ker');
    await tester.pumpAndSettle();
    expect(find.text('Kerala'), findsOneWidget);
    expect(find.text('Goa'), findsNothing);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('No matches'), findsOneWidget);
  });

  testWidgets('the list opens with the chosen option in view, even far down a long list', (tester) async {
    await tester.pumpWidget(const _Host(options: _states, initial: 'West Bengal'));
    await _open(tester);
    expect(find.text('West Bengal'), findsWidgets);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('dismissing the list changes nothing', (tester) async {
    String? picked = 'unchanged';
    await tester.pumpWidget(_Host(options: _types, initial: 'Indoor', onPicked: (v) => picked = v));
    await _open(tester);
    await tester.tapAt(const Offset(10, 10)); // outside the sheet
    await tester.pumpAndSettle();
    expect(picked, 'unchanged');
    expect(find.text('Indoor'), findsOneWidget);
  });

  testWidgets('its validator judges the value the screen holds now, and shows the message under the field', (tester) async {
    final formKey = GlobalKey<FormState>();
    await tester.pumpWidget(_Host(options: _types, formKey: formKey, validator: (v) => v == null ? 'State is required.' : null));

    expect(formKey.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('State is required.'), findsOneWidget);

    // the screen sets a value itself (not through the dropdown), and the form is happy
    tester.state<_HostState>(find.byType(_Host)).setExternally('Indoor');
    await tester.pump();
    expect(formKey.currentState!.validate(), isTrue);
    await tester.pump();
    expect(find.text('State is required.'), findsNothing);
  });

  testWidgets('long labels are cut with an ellipsis in the field, never overflowing', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const _Host(options: ['An extraordinarily long option label that cannot possibly fit on one line of a phone'], initial: 'An extraordinarily long option label that cannot possibly fit on one line of a phone'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('works at large text sizes without overflowing', (tester) async {
    tester.view.physicalSize = const Size(640, 1136);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MediaQuery(data: MediaQueryData(size: Size(320, 568), textScaler: TextScaler.linear(1.6)), child: _Host(options: _states, initial: 'Tamil Nadu')));
    await _open(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the loading placeholder has no spinner and no "Step" text, and keeps one shimmer', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SetupLoadingPage()));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('Step'), findsNothing);
    expect(find.byType(SetupShimmer), findsWidgets);
    expect(find.byType(SetupSkeletonBox), findsWidgets);
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });
}
