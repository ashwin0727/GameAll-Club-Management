import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/shared/widgets/booking_slot_chip.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('an available slot invokes onTap when tapped', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      _wrap(BookingSlotChip(label: '10:00 AM', available: true, selected: false, onTap: () => tapped = true)),
    );

    await tester.tap(find.byType(BookingSlotChip));
    await tester.pump();

    expect(tapped, isTrue);
  });

  testWidgets('a booked slot never invokes onTap — it is not a selectable control', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      _wrap(BookingSlotChip(label: '10:00 AM', available: false, selected: false, onTap: () => tapped = true)),
    );

    await tester.tap(find.byType(BookingSlotChip));
    await tester.pump();

    expect(tapped, isFalse);
  });

  testWidgets('a selected slot renders the Selected label', (tester) async {
    await tester.pumpWidget(
      _wrap(const BookingSlotChip(label: '10:00 AM', available: true, selected: true)),
    );

    expect(find.text('Selected'), findsOneWidget);
  });

  testWidgets('an available, unselected slot renders the Available label', (tester) async {
    await tester.pumpWidget(
      _wrap(const BookingSlotChip(label: '10:00 AM', available: true, selected: false)),
    );

    expect(find.text('Available'), findsOneWidget);
  });

  testWidgets('a booked slot renders the Booked label', (tester) async {
    await tester.pumpWidget(
      _wrap(const BookingSlotChip(label: '10:00 AM', available: false, selected: false)),
    );

    expect(find.text('Booked'), findsOneWidget);
  });

  testWidgets('exposes an accessible semantic label distinguishing booked from available', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _wrap(const BookingSlotChip(label: '10:00 AM', available: false, selected: false)),
    );

    final semantics = tester.getSemantics(find.byType(BookingSlotChip));
    expect(semantics.label, contains('booked'));
    handle.dispose();
  });
}