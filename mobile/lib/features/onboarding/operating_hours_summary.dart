// The "Operating Hours" summary shown at the bottom of the operating-hours step — the same grouping as the web's
// summary.ts: consecutive days that read identically collapse into one line ("Monday – Friday").

import '../../data/models/operating_hours.dart';

/// "6:00 AM" from "06:00" / "06:00:00".
String formatTime12h(String time) {
  final parts = time.split(':');
  final h = int.tryParse(parts.first) ?? 0;
  final m = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
  final hour12 = h % 12 == 0 ? 12 : h % 12;
  return '$hour12:${m.toString().padLeft(2, '0')} ${h < 12 ? 'AM' : 'PM'}';
}

class OperatingHoursGroup {
  const OperatingHoursGroup(this.label, this.description);
  final String label;
  final String description;
}

/// Groups consecutive days (Monday first) whose hours read the same.
List<OperatingHoursGroup> groupOperatingDays(List<OperatingDay> days) {
  final groups = <({String start, String end, String description})>[];
  int? lastIndex;
  for (final dow in displayOrder) {
    final day = days.where((d) => d.dayOfWeek == dow).firstOrNull;
    if (day == null) {
      lastIndex = null;
      continue;
    }
    final description = day.describe(formatTime12h);
    final index = displayOrder.indexOf(dow);
    if (groups.isNotEmpty && groups.last.description == description && lastIndex != null && index == lastIndex + 1) {
      final g = groups.removeLast();
      groups.add((start: g.start, end: dayLabels[dow], description: description));
    } else {
      groups.add((start: dayLabels[dow], end: dayLabels[dow], description: description));
    }
    lastIndex = index;
  }
  return [for (final g in groups) OperatingHoursGroup(g.start == g.end ? g.start : '${g.start} – ${g.end}', g.description)];
}
