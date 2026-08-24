import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/data/models/operating_hours.dart';
import 'package:gameall_club_mobile/features/bookings/booking_slots.dart';

OperatingDay day({
  bool isClosed = false,
  bool is24Hours = false,
  List<OperatingTimeSlot> slots = const [
    OperatingTimeSlot(startTime: '09:00', endTime: '12:00', crossesMidnight: false, displayOrder: 0),
  ],
}) {
  return OperatingDay(dayOfWeek: 1, isClosed: isClosed, is24Hours: is24Hours, slots: slots);
}

void main() {
  final monday = DateTime(2026, 1, 5);

  test('is empty when the day is closed', () {
    expect(computeAvailableSlots(monday, day(isClosed: true), const []), isEmpty);
  });

  test('generates one slot per hour across the open window', () {
    final slots = computeAvailableSlots(monday, day(), const []);
    expect(slots.length, 3);
    expect(slots.every((s) => s.available), isTrue);
  });

  test('caps a 24-hour day at the local calendar day boundary', () {
    final slots = computeAvailableSlots(monday, day(is24Hours: true), const []);
    expect(slots.length, 24);
    expect(slots.first.startTime.hour, 0);
    expect(slots.last.endTime, DateTime(2026, 1, 6));
  });

  test('marks a slot unavailable when an existing booking overlaps it', () {
    final existing = [(startTime: DateTime(2026, 1, 5, 10), endTime: DateTime(2026, 1, 5, 11))];
    final slots = computeAvailableSlots(monday, day(), existing);
    final overlapping = slots.firstWhere((s) => s.startTime.hour == 10);
    final untouched = slots.firstWhere((s) => s.startTime.hour == 9);
    expect(overlapping.available, isFalse);
    expect(untouched.available, isTrue);
  });

  test("extends an overnight slot's window but still caps it at end-of-day", () {
    final overnight = day(
      slots: const [OperatingTimeSlot(startTime: '22:00', endTime: '02:00', crossesMidnight: true, displayOrder: 0)],
    );
    final slots = computeAvailableSlots(monday, overnight, const []);
    expect(slots.length, 2);
  });
}