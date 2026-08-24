import '../../data/models/booking.dart';
import '../../data/models/operating_hours.dart';

/// Port of src/features/bookings/slots.ts — splits a day's open windows
/// into fixed-size candidate slots and flags each as available/unavailable
/// against existing bookings. Windows are capped at end-of-day (1440) —
/// bookings may not cross a local calendar day (see 0007_bookings.sql).
List<BookingTimeSlot> computeAvailableSlots(
  DateTime date,
  OperatingDay day,
  List<({DateTime startTime, DateTime endTime})> existingBookings, {
  int slotMinutes = 60,
}) {
  final windows = _windowsForDay(day);
  final slots = <BookingTimeSlot>[];

  for (final window in windows) {
    for (var start = window.startMin; start + slotMinutes <= window.endMin; start += slotMinutes) {
      final end = start + slotMinutes;
      final startTime = _atMinutes(date, start);
      final endTime = _atMinutes(date, end);
      final available = !existingBookings.any(
        (b) => startTime.isBefore(b.endTime) && b.startTime.isBefore(endTime),
      );
      slots.add(BookingTimeSlot(startTime: startTime, endTime: endTime, available: available));
    }
  }

  return slots;
}

class _Window {
  const _Window(this.startMin, this.endMin);
  final int startMin;
  final int endMin;
}

List<_Window> _windowsForDay(OperatingDay day) {
  if (day.isClosed) return [];
  if (day.is24Hours) return [const _Window(0, 1440)];

  return day.slots.map((slot) {
    final start = _toMinutes(slot.startTime);
    var end = _toMinutes(slot.endTime);
    if (slot.crossesMidnight || end <= start) end += 1440;
    return _Window(start, end > 1440 ? 1440 : end);
  }).toList();
}

int _toMinutes(String time) {
  final parts = time.split(':');
  final h = int.tryParse(parts[0]) ?? 0;
  final m = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
  return h * 60 + m;
}

DateTime _atMinutes(DateTime date, int minutes) {
  final base = DateTime(date.year, date.month, date.day);
  return base.add(Duration(minutes: minutes));
}