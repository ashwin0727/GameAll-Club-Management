/// Day-of-week helpers for membership access days and time slots.
/// Mirrors src/features/memberships/slot-form.ts (`ALL_DAYS`, `WEEKDAYS`,
/// `DAY_OPTIONS`, `sameDays`). `0` = Sunday .. `6` = Saturday, matching
/// Postgres `extract(dow ...)` and the `membership_batches.days_of_week` /
/// `facilities.membership_access_days` columns.
library;

const List<int> allDays = [0, 1, 2, 3, 4, 5, 6];
const List<int> weekdays = [1, 2, 3, 4, 5];

const List<String> _labels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

String dayLabel(int day) => _labels[day % 7];

/// Order-independent set equality for two day lists.
bool sameDays(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  final sa = a.toSet();
  return b.every(sa.contains);
}

/// Returns a new list with [day] toggled — added if absent, removed if present.
/// Kept sorted so the on-the-wire value is stable.
List<int> toggleDay(List<int> days, int day) {
  final next = days.contains(day) ? (days.toList()..remove(day)) : (days.toList()..add(day));
  next.sort();
  return next;
}
