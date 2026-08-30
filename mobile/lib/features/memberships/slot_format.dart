/// Port of src/features/memberships/slot-format.ts — formats a membership
/// batch's recurring days + hours into one human string, e.g.
/// "Mon/Wed/Fri · 5:00 AM – 6:00 AM".
library;

const List<String> _dayAbbr = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

/// "06:00:00" | "06:00" -> "6:00 AM".
String formatClock(String time) {
  final parts = time.split(':');
  final h = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 0;
  final m = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
  final h12 = h % 12 == 0 ? 12 : h % 12;
  final meridiem = h < 12 ? 'AM' : 'PM';
  return '$h12:${m.toString().padLeft(2, '0')} $meridiem';
}

/// [1, 3, 5] + times -> "Mon/Wed/Fri · 5:00 AM – 6:00 AM".
String formatSlot(List<int> daysOfWeek, String startTime, String endTime) {
  final days = ([...daysOfWeek]..sort())
      .map((d) => d >= 0 && d < _dayAbbr.length ? _dayAbbr[d] : '')
      .where((s) => s.isNotEmpty)
      .join('/');
  final range = '${formatClock(startTime)} – ${formatClock(endTime)}';
  return days.isEmpty ? range : '$days · $range';
}