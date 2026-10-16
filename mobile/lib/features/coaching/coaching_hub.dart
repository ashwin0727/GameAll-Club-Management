// The figures behind the Coaching hub's "View More Insights" panels — pure, so they are tested rather
// than eyeballed. Money is in minor units (paise) here, as the models carry it.

import '../../data/models/coaching.dart';

class ProgramInsights {
  const ProgramInsights({
    required this.total,
    required this.active,
    required this.inactive,
    required this.students,
    required this.scheduledSessions,
    required this.avgFeeMinor,
    required this.membershipIncluded,
  });

  final int total;
  final int active;
  final int inactive;

  /// Students across every program (active enrollments).
  final int students;
  final int scheduledSessions;

  /// The average default fee of the programs that charge one; null when none do.
  final int? avgFeeMinor;
  final int membershipIncluded;
}

/// The Programs tab's four cards, computed in the database across every program (migration 0122).
class ProgramCardStats {
  const ProgramCardStats({required this.total, required this.active, required this.enrolled, required this.availableSeats});

  final int total;
  final int active;
  final int enrolled;

  /// Open seats across all active programs' batches (or the program capacity when it has no batches).
  final int availableSeats;

  factory ProgramCardStats.fromJson(Map<String, dynamic> j) => ProgramCardStats(
        total: (j['totalPrograms'] as num?)?.toInt() ?? 0,
        active: (j['activePrograms'] as num?)?.toInt() ?? 0,
        enrolled: (j['enrolledStudents'] as num?)?.toInt() ?? 0,
        availableSeats: (j['availableSeats'] as num?)?.toInt() ?? 0,
      );
}

/// [total] is the facility-wide count (the list may be a capped page of it).
ProgramInsights programInsights(List<ProgramRow> programs, {int? total}) {
  final active = programs.where((p) => p.status == ProgramStatus.active).length;
  final priced = [for (final p in programs) if ((p.defaultPriceMinor ?? 0) > 0) p.defaultPriceMinor!];
  return ProgramInsights(
    total: total ?? programs.length,
    active: active,
    inactive: programs.length - active,
    students: programs.fold(0, (s, p) => s + p.studentCount),
    scheduledSessions: programs.fold(0, (s, p) => s + p.scheduledSessionCount),
    avgFeeMinor: priced.isEmpty ? null : (priced.reduce((a, b) => a + b) / priced.length).round(),
    membershipIncluded: programs.where((p) => p.isMembershipIncluded).length,
  );
}

/// The Students tab's four cards, computed in the database (migration 0123). Money in minor units.
class StudentCardStats {
  const StudentCardStats({required this.totalStudents, required this.enrolledStudents, required this.revenueMinor, required this.pendingMinor});

  /// Unique students with any enrollment — not enrollment rows.
  final int totalStudents;

  /// Unique students with an active enrollment.
  final int enrolledStudents;

  /// Confirmed coaching payments this month.
  final int revenueMinor;

  /// Still owed on enrollments (fee minus confirmed payments).
  final int pendingMinor;

  factory StudentCardStats.fromJson(Map<String, dynamic> j) => StudentCardStats(
        totalStudents: (j['totalStudents'] as num?)?.toInt() ?? 0,
        enrolledStudents: (j['enrolledStudents'] as num?)?.toInt() ?? 0,
        revenueMinor: (j['revenueMinor'] as num?)?.toInt() ?? 0,
        pendingMinor: (j['pendingMinor'] as num?)?.toInt() ?? 0,
      );
}

class StudentInsights {
  const StudentInsights({
    required this.total,
    required this.active,
    required this.inactive,
    required this.paymentPending,
    required this.activeFeesMinor,
  });

  final int total;
  final int active;

  /// Paused, completed or cancelled.
  final int inactive;

  /// Active enrollments whose fee is unpaid or only partly paid.
  final int paymentPending;

  /// What active enrollments are charged in total.
  final int activeFeesMinor;
}

StudentInsights studentInsights(List<EnrollmentRow> enrollments, {int? total}) {
  final active = enrollments.where((e) => e.status == EnrollmentStatus.active).toList();
  bool owes(EnrollmentRow e) => e.paymentStatus == EnrollmentPaymentStatus.pending || e.paymentStatus == EnrollmentPaymentStatus.partial;
  return StudentInsights(
    total: total ?? enrollments.length,
    active: active.length,
    inactive: enrollments.length - active.length,
    paymentPending: active.where(owes).length,
    activeFeesMinor: active.fold(0, (s, e) => s + e.priceMinor),
  );
}

/// Active first, then the rest; newest start first within each.
List<EnrollmentRow> orderStudents(List<EnrollmentRow> rows) {
  final out = [...rows];
  out.sort((a, b) {
    final aActive = a.status == EnrollmentStatus.active ? 0 : 1;
    final bActive = b.status == EnrollmentStatus.active ? 0 : 1;
    if (aActive != bActive) return aActive.compareTo(bActive);
    return b.startDate.compareTo(a.startDate);
  });
  return out;
}

/// Active first, then inactive; busiest first within each.
List<ProgramRow> orderPrograms(List<ProgramRow> rows) {
  final out = [...rows];
  out.sort((a, b) {
    final aActive = a.status == ProgramStatus.active ? 0 : 1;
    final bActive = b.status == ProgramStatus.active ? 0 : 1;
    if (aActive != bActive) return aActive.compareTo(bActive);
    return b.studentCount.compareTo(a.studentCount);
  });
  return out;
}

/// How many upcoming sessions the Coaching tab shows: just the next two.
const upcomingSessionLimit = 2;

/// The next [upcomingSessionLimit] sessions in start order, whichever day they fall on.
List<UpcomingSession> nextSessions(List<UpcomingSession> sessions, {int limit = upcomingSessionLimit}) {
  final out = [...sessions]..sort((a, b) => a.startAt.compareTo(b.startAt));
  return out.take(limit).toList();
}

/// "Today", "Tomorrow", or the date — so a session tomorrow isn't mistaken for one later today.
String sessionDayLabel(DateTime startAt, {DateTime? now}) {
  final n = (now ?? DateTime.now());
  final d = startAt.toLocal();
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = day.difference(today).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${months[d.month - 1]}';
}

// ── Coaches ───────────────────────────────────────────────────────────────

enum CoachSort {
  name('Name (A–Z)'),
  players('Most players'),
  sessions('Most sessions / week'),
  experience('Most experience');

  const CoachSort(this.label);
  final String label;
}

class CoachFilters {
  const CoachFilters({this.status, this.sport, this.sort = CoachSort.name});

  final CoachStatus? status;
  final String? sport;
  final CoachSort sort;

  /// Whether anything beyond the default order is applied — drives the filter button's dot.
  bool get isActive => status != null || sport != null || sort != CoachSort.name;

  CoachFilters copyWith({CoachStatus? status, String? sport, CoachSort? sort, bool clearStatus = false, bool clearSport = false}) => CoachFilters(
        status: clearStatus ? null : (status ?? this.status),
        sport: clearSport ? null : (sport ?? this.sport),
        sort: sort ?? this.sort,
      );
}

/// "Badminton Coach" — the coach's sports, else their specialization, else just "Coach".
String coachSportLabel(CoachRow c) {
  final sports = c.sports.where((s) => s.trim().isNotEmpty).toList();
  if (sports.isNotEmpty) return '${sports.join(', ')} Coach';
  final spec = c.specialization?.trim();
  if (spec != null && spec.isNotEmpty) return spec;
  return 'Coach';
}

/// "3" for 3.0, "2.5" for 2.5, "—" when not recorded.
String experienceLabel(double? years) {
  if (years == null) return '—';
  return years == years.roundToDouble() ? years.round().toString() : years.toStringAsFixed(1);
}

/// The seven days starting today (local midnight to midnight a week on). A rolling week rather than
/// Monday–Sunday: sessions are generated from today onward, so a calendar week that is half over would
/// undercount — and on a Sunday show almost nothing.
({DateTime start, DateTime end}) weekRange(DateTime now) {
  final start = DateTime(now.year, now.month, now.day);
  return (start: start, end: start.add(const Duration(days: 7)));
}

/// How many sessions each coach has in the next seven days (cancelled ones don't count).
Map<String, int> sessionsPerWeek(List<SessionRow> sessions, DateTime now) {
  final week = weekRange(now);
  final out = <String, int>{};
  for (final s in sessions) {
    if (s.status == SessionStatus.cancelled) continue;
    final t = s.startAt.toLocal();
    if (t.isBefore(week.start) || !t.isBefore(week.end)) continue;
    out[s.coachId] = (out[s.coachId] ?? 0) + 1;
  }
  return out;
}

/// Every distinct sport across the coaches, A–Z.
List<String> coachSportOptions(List<CoachRow> coaches) => ({for (final c in coaches) ...c.sports}.toList()..sort());

/// Search by name or sport (and specialization), then filter, then sort.
List<CoachRow> filterCoaches(
  List<CoachRow> coaches, {
  String query = '',
  CoachFilters filters = const CoachFilters(),
  Map<String, int> perWeek = const {},
}) {
  final q = query.trim().toLowerCase();
  final out = coaches.where((c) {
    if (filters.status != null && c.status != filters.status) return false;
    if (filters.sport != null && !c.sports.contains(filters.sport)) return false;
    if (q.isEmpty) return true;
    return c.fullName.toLowerCase().contains(q) ||
        c.sports.any((s) => s.toLowerCase().contains(q)) ||
        (c.specialization ?? '').toLowerCase().contains(q);
  }).toList();
  int byName(CoachRow a, CoachRow b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
  switch (filters.sort) {
    case CoachSort.name:
      out.sort(byName);
    case CoachSort.players:
      out.sort((a, b) => b.studentCount != a.studentCount ? b.studentCount.compareTo(a.studentCount) : byName(a, b));
    case CoachSort.sessions:
      out.sort((a, b) {
        final x = perWeek[a.id] ?? 0;
        final y = perWeek[b.id] ?? 0;
        return x != y ? y.compareTo(x) : byName(a, b);
      });
    case CoachSort.experience:
      out.sort((a, b) {
        final x = a.experienceYears ?? -1;
        final y = b.experienceYears ?? -1;
        return x != y ? y.compareTo(x) : byName(a, b);
      });
  }
  return out;
}

// ── Active Sessions ───────────────────────────────────────────────────────

/// Active Sessions is a daily figure: how many coaching sessions the current day has.
/// Every session the day has — still to come, under way or already done. Only cancelled ones are left out.
int todaysActiveCount(List<SessionRow> sessions) => sessions.where((s) => s.status != SessionStatus.cancelled).length;
