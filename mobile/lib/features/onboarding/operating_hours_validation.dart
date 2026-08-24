import '../../data/models/operating_hours.dart';

/// Port of src/features/operating-hours/validation.ts so the mobile app
/// enforces the same overlap/required-field rules before hitting the RPC.

int _toMinutes(String time) {
  final parts = time.split(':');
  final h = int.tryParse(parts[0]) ?? 0;
  final m = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
  return h * 60 + m;
}

/// A slot wraps past midnight when its end clock-time is not after its start.
bool isOvernightSlot(OperatingTimeSlot slot) => _toMinutes(slot.endTime) <= _toMinutes(slot.startTime);

class _Interval {
  _Interval(this.start, this.end);
  final int start;
  final int end;
}

_Interval _slotToInterval(OperatingTimeSlot slot) {
  final start = _toMinutes(slot.startTime);
  var end = _toMinutes(slot.endTime);
  if (end <= start) end += 24 * 60;
  return _Interval(start, end);
}

bool _intervalsOverlap(_Interval a, _Interval b) {
  for (final shift in [-1440, 0, 1440]) {
    final start = b.start + shift;
    final end = b.end + shift;
    if (a.start < end && start < a.end) return true;
  }
  return false;
}

bool hasOverlappingSlots(List<OperatingTimeSlot> slots) {
  final intervals = slots.map(_slotToInterval).toList();
  for (var i = 0; i < intervals.length; i++) {
    for (var j = i + 1; j < intervals.length; j++) {
      if (_intervalsOverlap(intervals[i], intervals[j])) return true;
    }
  }
  return false;
}

final RegExp _timeRe = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$');

String? validateTimeSlot(OperatingTimeSlot slot) {
  if (!_timeRe.hasMatch(slot.startTime)) return 'Opening time is required.';
  if (!_timeRe.hasMatch(slot.endTime)) return 'Closing time is required.';
  if (slot.startTime == slot.endTime) return 'Opening and closing time cannot be the same.';
  return null;
}

/// Returns a single user-facing message for the day, or null if it's valid.
String? validateOperatingDay(OperatingDay day) {
  if (day.isClosed || day.is24Hours) return null;
  if (day.slots.isEmpty) return 'Add at least one time slot, or mark the day Closed.';
  for (final slot in day.slots) {
    final error = validateTimeSlot(slot);
    if (error != null) return error;
  }
  if (hasOverlappingSlots(day.slots)) return 'Operating hours cannot overlap.';
  return null;
}

/// Map of dayOfWeek -> error message, empty when the whole schedule is valid.
Map<int, String> validateSchedule(List<OperatingDay> days) {
  final errors = <int, String>{};
  for (final day in days) {
    final error = validateOperatingDay(day);
    if (error != null) errors[day.dayOfWeek] = error;
  }
  return errors;
}

/// Recomputes crossesMidnight on every slot from its own start/end time,
/// mirroring web's withComputedOvernight().
OperatingDay withComputedOvernight(OperatingDay day) {
  return day.copyWith(
    slots: day.slots
        .map(
          (s) => OperatingTimeSlot(
            startTime: s.startTime,
            endTime: s.endTime,
            crossesMidnight: isOvernightSlot(s),
            displayOrder: s.displayOrder,
          ),
        )
        .toList(),
  );
}