import '../../data/models/operating_hours.dart';
import 'operating_hours_validation.dart' show isOvernightSlot;

/// Pure rules for the Operating Hours step — the same plans, break handling, totals and checks as the website's `setup-model.ts`, kept out
/// of widgets so they can be unit-tested and never drift between the two apps.

enum HoursMode { standard, custom }

/// One day as the owner sets it: open or closed, from one time to another (or open all day).
class DayPlan {
  DayPlan({required this.dayOfWeek, required this.isOpen, this.open = '06:00', this.close = '23:00', this.is24Hours = false});

  final int dayOfWeek;
  bool isOpen;

  /// "HH:MM" (24-hour).
  String open;
  String close;
  bool is24Hours;

  DayPlan copy() => DayPlan(dayOfWeek: dayOfWeek, isOpen: isOpen, open: open, close: close, is24Hours: is24Hours);
}

class BreakTime {
  const BreakTime(this.start, this.end);
  final String start;
  final String end;
}

const Map<int, String> shortDay = {0: 'Sun', 1: 'Mon', 2: 'Tue', 3: 'Wed', 4: 'Thu', 5: 'Fri', 6: 'Sat'};

int toMinutes(String time) {
  final p = time.split(':');
  return (int.tryParse(p[0]) ?? 0) * 60 + (int.tryParse(p.length > 1 ? p[1] : '0') ?? 0);
}

String fromMinutes(int total) {
  final t = ((total % 1440) + 1440) % 1440;
  return '${(t ~/ 60).toString().padLeft(2, '0')}:${(t % 60).toString().padLeft(2, '0')}';
}

/// "6:00 AM"
String formatClock(String time) {
  final h = toMinutes(time) ~/ 60;
  final m = toMinutes(time) % 60;
  final hour12 = h % 12 == 0 ? 12 : h % 12;
  return '$hour12:${m.toString().padLeft(2, '0')} ${h < 12 ? 'AM' : 'PM'}';
}

/// Every half hour of the day, the way the time lists show them.
final List<({String value, String label})> timeOptions = [
  for (var i = 0; i < 48; i++) (value: fromMinutes(i * 30), label: formatClock(fromMinutes(i * 30))),
];

DayPlan defaultPlan(int day, {bool isOpen = true}) => DayPlan(dayOfWeek: day, isOpen: isOpen);

/// A new venue starts open Monday to Saturday, 6 AM to 11 PM, closed on Sunday.
List<DayPlan> defaultPlans() => [for (final d in daysOfWeek) defaultPlan(d, isOpen: d != 0)];

List<DayPlan> orderedPlans(List<DayPlan> plans) => [
      for (final d in displayOrder)
        if (plans.any((p) => p.dayOfWeek == d)) plans.firstWhere((p) => p.dayOfWeek == d),
    ];

int _span(String from, String to) {
  final d = toMinutes(to) - toMinutes(from);
  return d > 0 ? d : d + 1440;
}

/// Whether the break sits inside a day's working hours (so it can split them into two slots).
bool breakFitsDay(DayPlan plan, BreakTime brk) {
  final total = _span(plan.open, plan.close);
  final from = (toMinutes(brk.start) - toMinutes(plan.open) + 1440) % 1440;
  final to = from + _span(brk.start, brk.end);
  return from > 0 && to < total;
}

// ── schedule <-> plans ──────────────────────────────────────────────────

/// Reads the stored schedule back as plans (a daily break is folded back into one span).
List<DayPlan> plansFromSchedule(List<OperatingDay> days) {
  return [
    for (final d in daysOfWeek)
      () {
        final day = days.where((x) => x.dayOfWeek == d).firstOrNull;
        if (day == null || day.isClosed || (!day.is24Hours && day.slots.isEmpty)) return defaultPlan(d, isOpen: false);
        if (day.is24Hours) return DayPlan(dayOfWeek: d, isOpen: true, is24Hours: true);
        return DayPlan(dayOfWeek: d, isOpen: true, open: day.slots.first.startTime, close: day.slots.last.endTime);
      }(),
  ];
}

/// Turns the plans (and the optional daily break) into the schedule that is stored.
List<OperatingDay> scheduleFromPlans(List<DayPlan> plans, BreakTime? brk) {
  OperatingTimeSlot slot(String start, String end, int order) => OperatingTimeSlot(
        startTime: start,
        endTime: end,
        crossesMidnight: isOvernightSlot(OperatingTimeSlot(startTime: start, endTime: end, crossesMidnight: false, displayOrder: order)),
        displayOrder: order,
      );
  return [
    for (final d in daysOfWeek)
      () {
        final plan = plans.where((p) => p.dayOfWeek == d).firstOrNull ?? defaultPlan(d, isOpen: false);
        if (!plan.isOpen) return OperatingDay(dayOfWeek: d, isClosed: true, is24Hours: false, slots: const []);
        if (plan.is24Hours) return OperatingDay(dayOfWeek: d, isClosed: false, is24Hours: true, slots: const []);
        if (brk != null && breakFitsDay(plan, brk)) {
          return OperatingDay(dayOfWeek: d, isClosed: false, is24Hours: false, slots: [slot(plan.open, brk.start, 0), slot(brk.end, plan.close, 1)]);
        }
        return OperatingDay(dayOfWeek: d, isClosed: false, is24Hours: false, slots: [slot(plan.open, plan.close, 0)]);
      }(),
  ];
}

/// Standard when every open day shares the same hours (the simple case), otherwise custom.
HoursMode detectMode(List<DayPlan> plans) {
  final open = plans.where((p) => p.isOpen).toList();
  if (open.isEmpty) return HoursMode.standard;
  String key(DayPlan p) => p.is24Hours ? '24h' : '${p.open}-${p.close}';
  return open.every((p) => key(p) == key(open.first)) ? HoursMode.standard : HoursMode.custom;
}

/// Standard mode: the chosen days all get the same hours; the others are closed.
List<DayPlan> applyStandard(List<int> openDays, String open, String close, {bool is24Hours = false}) =>
    [for (final d in daysOfWeek) DayPlan(dayOfWeek: d, isOpen: openDays.contains(d), open: open, close: close, is24Hours: is24Hours)];

// ── hours ───────────────────────────────────────────────────────────────

int dailyMinutes(DayPlan plan, BreakTime? brk) {
  if (!plan.isOpen) return 0;
  if (plan.is24Hours) return 1440;
  final total = _span(plan.open, plan.close);
  return brk != null && breakFitsDay(plan, brk) ? total - _span(brk.start, brk.end) : total;
}

int weeklyMinutes(List<DayPlan> plans, BreakTime? brk) => plans.fold(0, (sum, p) => sum + dailyMinutes(p, brk));

/// "17 Hours", "1 Hour", "17.5 Hours"
String formatHours(int minutes) {
  final hours = (minutes / 60 * 10).round() / 10;
  final text = hours == hours.roundToDouble() ? hours.toInt().toString() : hours.toStringAsFixed(1);
  return '$text ${hours == 1 ? 'Hour' : 'Hours'}';
}

/// "6:00 AM – 11:00 PM", with "(next day)" when it closes after midnight.
String describePlan(DayPlan plan) {
  if (!plan.isOpen) return 'Closed';
  if (plan.is24Hours) return 'Open 24 hours';
  final next = toMinutes(plan.close) <= toMinutes(plan.open) ? ' (next day)' : '';
  return '${formatClock(plan.open)} – ${formatClock(plan.close)}$next';
}

// ── validation ──────────────────────────────────────────────────────────

class PlanProblems {
  const PlanProblems({this.general, this.byDay = const {}, this.breakTime});

  final String? general;
  final Map<int, String> byDay;
  final String? breakTime;

  bool get any => general != null || breakTime != null || byDay.isNotEmpty;
}

PlanProblems validatePlans(List<DayPlan> plans, BreakTime? brk) {
  final byDay = <int, String>{};
  final open = plans.where((p) => p.isOpen).toList();
  String? general;
  if (open.isEmpty) general = 'Select at least one operating day.';
  for (final p in open) {
    if (p.is24Hours) continue;
    if (p.open.isEmpty || p.close.isEmpty) {
      byDay[p.dayOfWeek] = 'Select opening and closing time.';
    } else if (p.open == p.close) {
      byDay[p.dayOfWeek] = 'Opening and closing time cannot be the same.';
    }
  }
  String? breakTime;
  if (brk != null) {
    if (brk.start.isEmpty || brk.end.isEmpty) {
      breakTime = 'Select the break’s start and end time.';
    } else if (brk.start == brk.end) {
      breakTime = 'The break’s start and end time cannot be the same.';
    } else {
      final timed = open.where((p) => !p.is24Hours && p.open != p.close);
      if (timed.isNotEmpty && timed.any((p) => !breakFitsDay(p, brk))) {
        breakTime = 'The break must fall inside the working hours of every open day.';
      }
    }
  }
  return PlanProblems(general: general, byDay: byDay, breakTime: breakTime);
}

// ── closures ────────────────────────────────────────────────────────────

const List<String> _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const List<String> _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// "15 Aug 2026 (Sat)"
String formatClosureDate(String iso) {
  final p = iso.split('-');
  final y = int.parse(p[0]);
  final m = int.parse(p[1]);
  final d = int.parse(p[2]);
  final weekday = _weekdays[DateTime(y, m, d).weekday - 1];
  return '${d.toString().padLeft(2, '0')} ${_months[m - 1]} $y ($weekday)';
}

String isoDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// What is wrong with a closure about to be added or saved (null when it is fine). [today] is "yyyy-MM-dd".
String? closureProblem(ClosureEntry closure, List<ClosureEntry> others, String today, {ClosureEntry? editing}) {
  if (closure.date.isEmpty) return 'Select a date.';
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(closure.date)) return 'Select a valid date.';
  if (closure.date.compareTo(today) < 0 && closure.date != editing?.date) return 'Choose today or a future date.';
  final name = closure.name.trim();
  if (name.length < 2) return 'Enter a name of at least 2 characters.';
  if (name.length > 60) return 'Keep the name under 60 characters.';
  if (others.any((c) => c.date == closure.date && !identical(c, editing))) return 'This date is already marked as closed.';
  return null;
}

List<ClosureEntry> sortClosures(List<ClosureEntry> closures) => [...closures]..sort((a, b) => a.date.compareTo(b.date));
