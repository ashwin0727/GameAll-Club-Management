/// Labels and grouping for the membership timing breakdown — the Dart twin of
/// src/features/reports/membership-timing.ts.
library;

import '../../data/models/analytics.dart';

const _day = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

/// "05:00:00" → "5:00 AM".
String formatClock(String? hhmmss) {
  if (hhmmss == null || hhmmss.isEmpty) return '';
  final parts = hhmmss.split(':');
  final hour = int.tryParse(parts[0]) ?? 0;
  final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
  final hour12 = hour % 12 == 0 ? 12 : hour % 12;
  return '$hour12:${minute.toString().padLeft(2, '0')} ${hour < 12 ? 'AM' : 'PM'}';
}

/// "5:00 AM – 6:00 AM".
String formatTiming(String? start, String? end) =>
    start != null && end != null ? '${formatClock(start)} – ${formatClock(end)}' : '';

/// Weekdays as ranges, Monday first: [1..6] → "Mon–Sat", [0,6] → "Sat, Sun".
String formatDays(List<int> days) {
  final order = days.toSet().toList()..sort((a, b) => ((a + 6) % 7).compareTo((b + 6) % 7));
  if (order.length == 7) return 'Every day';
  final runs = <List<int>>[];
  for (final d in order) {
    if (runs.isNotEmpty && (runs.last.last + 1) % 7 == d && d != 0) {
      runs.last.add(d);
    } else {
      runs.add([d]);
    }
  }
  return runs
      .map((r) => r.length >= 3 ? '${_day[r.first]}–${_day[r.last]}' : r.map((d) => _day[d]).join(', '))
      .join(', ');
}

class TimingCourt {
  TimingCourt(this.courtName, this.members);

  final String courtName;
  final int members;
  final List<MembershipBatchRow> timings = [];
}

class TimingGroup {
  TimingGroup(this.sportName, this.members);

  final String sportName;

  /// Distinct people in the sport.
  final int members;
  final List<TimingCourt> courts = [];
}

/// Rows (already ordered sport → court → time) folded into sport → court →
/// timings. The "no timing" row (null batch) is left out.
List<TimingGroup> groupByCourt(List<MembershipBatchRow> rows) {
  final groups = <TimingGroup>[];
  for (final r in rows) {
    if (r.batchId == null) continue;
    var sport = groups.where((g) => g.sportName == r.sportName).firstOrNull;
    if (sport == null) {
      sport = TimingGroup(r.sportName, r.sportMembers);
      groups.add(sport);
    }
    final courtName = r.courtName ?? '';
    var court = sport.courts.where((c) => c.courtName == courtName).firstOrNull;
    if (court == null) {
      court = TimingCourt(courtName, r.courtMembers);
      sport.courts.add(court);
    }
    court.timings.add(r);
  }
  return groups;
}
