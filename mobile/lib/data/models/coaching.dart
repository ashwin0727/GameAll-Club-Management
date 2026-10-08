// ═══════════════════════════════════════════════════════════════════════════
// Coaching Management — mirrors src/features/coaching/types.ts.
// Backend: migrations 0082-0086. Coaching is an integration module — a coach
// is an existing staff member, a student an existing member, a session
// reserves a real court through the existing availability engine, and a fee
// is an obligation settled through the one payment path. Money is in integer
// minor units (paise).
// ═══════════════════════════════════════════════════════════════════════════

int _int(dynamic v) => (v as num?)?.toInt() ?? 0;
int? _intN(dynamic v) => (v as num?)?.toInt();
double? _dblN(dynamic v) => (v as num?)?.toDouble();
double _dbl(dynamic v) => (v as num?)?.toDouble() ?? 0;
List<Map<String, dynamic>> _rows(dynamic v) =>
    (v as List<dynamic>? ?? const []).map((e) => (e as Map).cast<String, dynamic>()).toList();

enum CoachStatus {
  active,
  inactive,
  onLeave;

  static CoachStatus fromJson(String? v) => switch (v) {
        'INACTIVE' => CoachStatus.inactive,
        'ON_LEAVE' => CoachStatus.onLeave,
        _ => CoachStatus.active,
      };
  String toJson() => switch (this) {
        CoachStatus.inactive => 'INACTIVE',
        CoachStatus.onLeave => 'ON_LEAVE',
        CoachStatus.active => 'ACTIVE',
      };
  String get label => switch (this) {
        CoachStatus.inactive => 'Inactive',
        CoachStatus.onLeave => 'On Leave',
        CoachStatus.active => 'Active',
      };
}

enum ProgramStatus {
  active,
  inactive;

  static ProgramStatus fromJson(String? v) => v == 'INACTIVE' ? ProgramStatus.inactive : ProgramStatus.active;
  String toJson() => this == ProgramStatus.inactive ? 'INACTIVE' : 'ACTIVE';
  String get label => this == ProgramStatus.inactive ? 'Inactive' : 'Active';
}

enum SessionStatus {
  scheduled,
  confirmed,
  inProgress,
  completed,
  cancelled;

  static SessionStatus fromJson(String? v) => switch (v) {
        'CONFIRMED' => SessionStatus.confirmed,
        'IN_PROGRESS' => SessionStatus.inProgress,
        'COMPLETED' => SessionStatus.completed,
        'CANCELLED' => SessionStatus.cancelled,
        _ => SessionStatus.scheduled,
      };
  String toJson() => switch (this) {
        SessionStatus.confirmed => 'CONFIRMED',
        SessionStatus.inProgress => 'IN_PROGRESS',
        SessionStatus.completed => 'COMPLETED',
        SessionStatus.cancelled => 'CANCELLED',
        SessionStatus.scheduled => 'SCHEDULED',
      };
  String get label => switch (this) {
        SessionStatus.confirmed => 'Confirmed',
        SessionStatus.inProgress => 'In Progress',
        SessionStatus.completed => 'Completed',
        SessionStatus.cancelled => 'Cancelled',
        SessionStatus.scheduled => 'Scheduled',
      };
  bool get isLive => this == SessionStatus.scheduled || this == SessionStatus.confirmed;
}

enum EnrollmentStatus {
  active,
  paused,
  completed,
  cancelled;

  static EnrollmentStatus fromJson(String? v) => switch (v) {
        'PAUSED' => EnrollmentStatus.paused,
        'COMPLETED' => EnrollmentStatus.completed,
        'CANCELLED' => EnrollmentStatus.cancelled,
        _ => EnrollmentStatus.active,
      };
  String toJson() => switch (this) {
        EnrollmentStatus.paused => 'PAUSED',
        EnrollmentStatus.completed => 'COMPLETED',
        EnrollmentStatus.cancelled => 'CANCELLED',
        EnrollmentStatus.active => 'ACTIVE',
      };
  String get label => switch (this) {
        EnrollmentStatus.paused => 'Paused',
        EnrollmentStatus.completed => 'Completed',
        EnrollmentStatus.cancelled => 'Cancelled',
        EnrollmentStatus.active => 'Active',
      };
}

enum EnrollmentPaymentStatus {
  included,
  paid,
  partial,
  pending;

  static EnrollmentPaymentStatus fromJson(String? v) => switch (v) {
        'INCLUDED' => EnrollmentPaymentStatus.included,
        'PAID' => EnrollmentPaymentStatus.paid,
        'PARTIAL' => EnrollmentPaymentStatus.partial,
        _ => EnrollmentPaymentStatus.pending,
      };
  String get label => switch (this) {
        EnrollmentPaymentStatus.included => 'Included',
        EnrollmentPaymentStatus.paid => 'Paid',
        EnrollmentPaymentStatus.partial => 'Partially Paid',
        EnrollmentPaymentStatus.pending => 'Unpaid',
      };
}

enum ProgressStatus {
  onTrack,
  needsWork,
  excelling,
  atRisk;

  static ProgressStatus fromJson(String? v) => switch (v) {
        'NEEDS_WORK' => ProgressStatus.needsWork,
        'EXCELLING' => ProgressStatus.excelling,
        'AT_RISK' => ProgressStatus.atRisk,
        _ => ProgressStatus.onTrack,
      };
  String toJson() => switch (this) {
        ProgressStatus.needsWork => 'NEEDS_WORK',
        ProgressStatus.excelling => 'EXCELLING',
        ProgressStatus.atRisk => 'AT_RISK',
        ProgressStatus.onTrack => 'ON_TRACK',
      };
  String get label => switch (this) {
        ProgressStatus.needsWork => 'Needs Work',
        ProgressStatus.excelling => 'Excelling',
        ProgressStatus.atRisk => 'At Risk',
        ProgressStatus.onTrack => 'On Track',
      };
}

// ── Overview ───────────────────────────────────────────────────────────────
class CoachingOverview {
  const CoachingOverview({
    required this.activeStudents,
    required this.activePrograms,
    required this.activeCoaches,
    required this.coachesOnLeave,
    required this.sessionsThisMonth,
    required this.upcomingSessionsCount,
    required this.revenueThisMonthMinor,
    required this.upcomingSessions,
    required this.programs,
    required this.studentsByProgram,
    required this.studentGrowth,
    required this.recentEnrollments,
  });

  final int activeStudents;
  final int activePrograms;
  final int activeCoaches;
  final int coachesOnLeave;
  final int sessionsThisMonth;
  final int upcomingSessionsCount;
  final int revenueThisMonthMinor;
  final List<UpcomingSession> upcomingSessions;
  final List<OverviewProgram> programs;
  final List<StudentsByProgram> studentsByProgram;
  final List<GrowthPoint> studentGrowth;
  final List<RecentEnrollment> recentEnrollments;

  factory CoachingOverview.fromJson(Map<String, dynamic> j) {
    final k = (j['kpis'] as Map?)?.cast<String, dynamic>() ?? const {};
    return CoachingOverview(
      activeStudents: _int(k['activeStudents']),
      activePrograms: _int(k['activePrograms']),
      activeCoaches: _int(k['activeCoaches']),
      coachesOnLeave: _int(k['coachesOnLeave']),
      sessionsThisMonth: _int(k['sessionsThisMonth']),
      upcomingSessionsCount: _int(k['upcomingSessions']),
      revenueThisMonthMinor: _int(k['revenueThisMonthMinor']),
      upcomingSessions: _rows(j['upcomingSessions']).map(UpcomingSession.fromJson).toList(),
      programs: _rows(j['activePrograms']).map(OverviewProgram.fromJson).toList(),
      studentsByProgram: _rows(j['studentsByProgram']).map(StudentsByProgram.fromJson).toList(),
      studentGrowth: _rows(j['studentGrowth']).map(GrowthPoint.fromJson).toList(),
      recentEnrollments: _rows(j['recentEnrollments']).map(RecentEnrollment.fromJson).toList(),
    );
  }
}

class UpcomingSession {
  const UpcomingSession({
    required this.id,
    required this.startAt,
    required this.endAt,
    required this.programName,
    required this.coachName,
    required this.courtName,
    required this.enrolled,
    required this.capacity,
    required this.status,
  });
  final String id;
  final DateTime startAt;
  final DateTime endAt;
  final String programName;
  final String coachName;
  final String courtName;
  final int enrolled;
  final int capacity;
  final SessionStatus status;
  factory UpcomingSession.fromJson(Map<String, dynamic> j) => UpcomingSession(
        id: j['id'] as String,
        startAt: DateTime.parse(j['startAt'] as String),
        endAt: DateTime.parse(j['endAt'] as String),
        programName: j['programName'] as String? ?? '',
        coachName: j['coachName'] as String? ?? '',
        courtName: j['courtName'] as String? ?? '',
        enrolled: _int(j['enrolled']),
        capacity: _int(j['capacity']),
        status: SessionStatus.fromJson(j['status'] as String?),
      );
}

class OverviewProgram {
  const OverviewProgram({required this.id, required this.name, required this.level, required this.studentCount, required this.sessionCount});
  final String id;
  final String name;
  final String level;
  final int studentCount;
  final int sessionCount;
  factory OverviewProgram.fromJson(Map<String, dynamic> j) => OverviewProgram(
        id: j['id'] as String,
        name: j['name'] as String,
        level: j['level'] as String? ?? '',
        studentCount: _int(j['studentCount']),
        sessionCount: _int(j['sessionCount']),
      );
}

class StudentsByProgram {
  const StudentsByProgram({required this.programName, required this.students});
  final String programName;
  final int students;
  factory StudentsByProgram.fromJson(Map<String, dynamic> j) =>
      StudentsByProgram(programName: j['programName'] as String? ?? '', students: _int(j['students']));
}

class GrowthPoint {
  const GrowthPoint({required this.month, required this.students});
  final String month;
  final int students;
  factory GrowthPoint.fromJson(Map<String, dynamic> j) =>
      GrowthPoint(month: j['month'] as String? ?? '', students: _int(j['students']));
}

class RecentEnrollment {
  const RecentEnrollment({required this.id, required this.studentName, required this.programName, required this.enrolledAt, required this.status});
  final String id;
  final String studentName;
  final String programName;
  final DateTime enrolledAt;
  final EnrollmentStatus status;
  factory RecentEnrollment.fromJson(Map<String, dynamic> j) => RecentEnrollment(
        id: j['id'] as String,
        studentName: j['studentName'] as String? ?? '',
        programName: j['programName'] as String? ?? '',
        enrolledAt: DateTime.parse(j['enrolledAt'] as String),
        status: EnrollmentStatus.fromJson(j['status'] as String?),
      );
}

// ── Coaches ────────────────────────────────────────────────────────────────
class CoachRow {
  const CoachRow({
    required this.id,
    required this.userId,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.avatarUrl,
    required this.specialization,
    required this.experienceYears,
    required this.status,
    required this.programCount,
    required this.sessionCount,
    required this.studentCount,
  });
  final String id;
  final String userId;
  final String fullName;
  final String? email;
  final String? phone;
  final String? avatarUrl;
  final String? specialization;
  final double? experienceYears;
  final CoachStatus status;
  final int programCount;
  final int sessionCount;
  final int studentCount;
  factory CoachRow.fromJson(Map<String, dynamic> j) => CoachRow(
        id: j['id'] as String,
        userId: j['user_id'] as String,
        fullName: j['full_name'] as String,
        email: j['email'] as String?,
        phone: j['phone'] as String?,
        avatarUrl: j['avatar_url'] as String?,
        specialization: j['specialization'] as String?,
        experienceYears: _dblN(j['experience_years']),
        status: CoachStatus.fromJson(j['status'] as String?),
        programCount: _int(j['program_count']),
        sessionCount: _int(j['session_count']),
        studentCount: _int(j['student_count']),
      );
}

class CoachPage {
  const CoachPage({required this.coaches, required this.totalCount});
  final List<CoachRow> coaches;
  final int totalCount;
  factory CoachPage.fromRows(List<Map<String, dynamic>> rows) => CoachPage(
        coaches: rows.map(CoachRow.fromJson).toList(),
        totalCount: rows.isEmpty ? 0 : _int(rows.first['total_count']),
      );
}

class AvailabilityWindow {
  const AvailabilityWindow({this.id, required this.dayOfWeek, required this.startTime, required this.endTime});
  final String? id;
  final int dayOfWeek; // 0 = Sun … 6 = Sat
  final String startTime; // "HH:MM" or "HH:MM:SS"
  final String endTime;
  factory AvailabilityWindow.fromJson(Map<String, dynamic> j) => AvailabilityWindow(
        id: j['id'] as String?,
        dayOfWeek: _int(j['dayOfWeek']),
        startTime: (j['startTime'] as String).substring(0, 5),
        endTime: (j['endTime'] as String).substring(0, 5),
      );
  Map<String, dynamic> toPayload() => {'dayOfWeek': dayOfWeek, 'startTime': startTime, 'endTime': endTime};
  AvailabilityWindow copyWith({int? dayOfWeek, String? startTime, String? endTime}) => AvailabilityWindow(
        id: id,
        dayOfWeek: dayOfWeek ?? this.dayOfWeek,
        startTime: startTime ?? this.startTime,
        endTime: endTime ?? this.endTime,
      );
}

class CoachDetail {
  const CoachDetail({
    required this.id,
    required this.userId,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.avatarUrl,
    required this.specialization,
    required this.experienceYears,
    required this.certifications,
    required this.bio,
    required this.hourlyRateMinor,
    required this.status,
    required this.joinedOn,
    required this.title,
    required this.sessionsThisMonth,
    required this.activeStudents,
    required this.programsCount,
    required this.todaySchedule,
    required this.programs,
    required this.students,
    required this.availability,
  });

  final String id;
  final String userId;
  final String fullName;
  final String? email;
  final String? phone;
  final String? avatarUrl;
  final String? specialization;
  final double? experienceYears;
  final String? certifications;
  final String? bio;
  final int? hourlyRateMinor;
  final CoachStatus status;
  final String? joinedOn;
  final String? title;
  final int sessionsThisMonth;
  final int activeStudents;
  final int programsCount;
  final List<SessionRow> todaySchedule;
  final List<({String id, String name, String level})> programs;
  final List<({String enrollmentId, String name, String programName, EnrollmentStatus status})> students;
  final List<AvailabilityWindow> availability;

  factory CoachDetail.fromJson(Map<String, dynamic> j) {
    final stats = (j['stats'] as Map?)?.cast<String, dynamic>() ?? const {};
    return CoachDetail(
      id: j['id'] as String,
      userId: j['userId'] as String,
      fullName: j['fullName'] as String,
      email: j['email'] as String?,
      phone: j['phone'] as String?,
      avatarUrl: j['avatarUrl'] as String?,
      specialization: j['specialization'] as String?,
      experienceYears: _dblN(j['experienceYears']),
      certifications: j['certifications'] as String?,
      bio: j['bio'] as String?,
      hourlyRateMinor: _intN(j['hourlyRateMinor']),
      status: CoachStatus.fromJson(j['status'] as String?),
      joinedOn: j['joinedOn'] as String?,
      title: j['title'] as String?,
      sessionsThisMonth: _int(stats['sessionsThisMonth']),
      activeStudents: _int(stats['activeStudents']),
      programsCount: _int(stats['programs']),
      todaySchedule: _rows(j['todaySchedule'])
          .map((r) => SessionRow(
                id: r['id'] as String,
                programId: '',
                programName: r['programName'] as String? ?? '',
                coachId: j['id'] as String,
                coachName: j['fullName'] as String,
                courtId: '',
                courtName: r['courtName'] as String? ?? '',
                startAt: DateTime.parse(r['startAt'] as String),
                endAt: DateTime.parse(r['endAt'] as String),
                capacity: 0,
                enrolledCount: 0,
                status: SessionStatus.fromJson(r['status'] as String?),
              ))
          .toList(),
      programs: _rows(j['programs'])
          .map((r) => (id: r['id'] as String, name: r['name'] as String? ?? '', level: r['level'] as String? ?? ''))
          .toList(),
      students: _rows(j['students'])
          .map((r) => (
                enrollmentId: r['enrollmentId'] as String,
                name: r['name'] as String? ?? '',
                programName: r['programName'] as String? ?? '',
                status: EnrollmentStatus.fromJson(r['status'] as String?),
              ))
          .toList(),
      availability: _rows(j['availability']).map(AvailabilityWindow.fromJson).toList(),
    );
  }
}

class CoachCandidate {
  const CoachCandidate({required this.userId, required this.fullName, this.title});
  final String userId;
  final String fullName;
  final String? title;
  factory CoachCandidate.fromJson(Map<String, dynamic> j) =>
      CoachCandidate(userId: j['user_id'] as String, fullName: j['full_name'] as String, title: j['title'] as String?);
}

class CoachOption {
  const CoachOption({required this.id, required this.name});
  final String id;
  final String name;
  factory CoachOption.fromJson(Map<String, dynamic> j) => CoachOption(id: j['id'] as String, name: j['name'] as String);
}

// ── Programs ───────────────────────────────────────────────────────────────
class ProgramRow {
  const ProgramRow({
    required this.id,
    required this.name,
    required this.level,
    required this.ageGroup,
    required this.category,
    required this.defaultDurationMinutes,
    required this.defaultCapacity,
    required this.sessionCount,
    required this.defaultPriceMinor,
    required this.isMembershipIncluded,
    required this.status,
    required this.studentCount,
    required this.scheduledSessionCount,
  });
  final String id;
  final String name;
  final String level;
  final String ageGroup;
  final String category;
  final int defaultDurationMinutes;
  final int defaultCapacity;
  final int? sessionCount;
  final int? defaultPriceMinor;
  final bool isMembershipIncluded;
  final ProgramStatus status;
  final int studentCount;
  final int scheduledSessionCount;
  factory ProgramRow.fromJson(Map<String, dynamic> j) => ProgramRow(
        id: j['id'] as String,
        name: j['name'] as String,
        level: j['level'] as String? ?? '',
        ageGroup: j['age_group'] as String? ?? '',
        category: j['category'] as String? ?? '',
        defaultDurationMinutes: _int(j['default_duration_minutes']),
        defaultCapacity: _int(j['default_capacity']),
        sessionCount: _intN(j['session_count']),
        defaultPriceMinor: _intN(j['default_price_minor']),
        isMembershipIncluded: j['is_membership_included'] as bool? ?? false,
        status: ProgramStatus.fromJson(j['status'] as String?),
        studentCount: _int(j['student_count']),
        scheduledSessionCount: _int(j['scheduled_session_count']),
      );
}

class ProgramPage {
  const ProgramPage({required this.programs, required this.totalCount});
  final List<ProgramRow> programs;
  final int totalCount;
  factory ProgramPage.fromRows(List<Map<String, dynamic>> rows) => ProgramPage(
        programs: rows.map(ProgramRow.fromJson).toList(),
        totalCount: rows.isEmpty ? 0 : _int(rows.first['total_count']),
      );
}

/// A recurring weekly slot of a program (one day-set / time / court / coach) that students are
/// enrolled into — coaching_program_batches (migration 0100).
class ProgramBatch {
  const ProgramBatch({
    required this.id,
    required this.name,
    required this.daysOfWeek,
    required this.startTime,
    required this.endTime,
    required this.capacity,
    required this.status,
    required this.courtId,
    required this.courtName,
    required this.coachId,
    required this.coachName,
    this.enrolledCount,
  });
  final String id;
  final String name;

  /// 0 = Sunday … 6 = Saturday.
  final List<int> daysOfWeek;
  final String startTime;
  final String endTime;
  final int capacity;
  final String status;
  final String? courtId;
  final String? courtName;
  final String? coachId;
  final String? coachName;

  /// Only present on list_coaching_program_batches, not on get_coaching_program's embedded batches.
  final int? enrolledCount;

  bool get isFull => enrolledCount != null && enrolledCount! >= capacity;

  static String _hhmm(dynamic v) {
    final t = (v as String?) ?? '';
    return t.length >= 5 ? t.substring(0, 5) : t;
  }

  /// "Mon, Wed, Fri · 17:00–18:00".
  String get scheduleLabel {
    const d = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    final days = ([...daysOfWeek]..sort()).map((i) => d[i % 7]).join(', ');
    return '$days · $startTime–$endTime';
  }

  /// Accepts both the embedded camelCase shape (get_coaching_program) and the snake_case rows of
  /// list_coaching_program_batches.
  factory ProgramBatch.fromJson(Map<String, dynamic> j) => ProgramBatch(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        daysOfWeek: ((j['daysOfWeek'] ?? j['days_of_week']) as List<dynamic>? ?? const []).map((e) => (e as num).toInt()).toList(),
        startTime: _hhmm(j['startTime'] ?? j['start_time']),
        endTime: _hhmm(j['endTime'] ?? j['end_time']),
        capacity: _int(j['capacity']),
        status: j['status'] as String? ?? 'ACTIVE',
        courtId: (j['courtId'] ?? j['court_id']) as String?,
        courtName: (j['courtName'] ?? j['court_name']) as String?,
        coachId: (j['coachId'] ?? j['coach_id']) as String?,
        coachName: (j['coachName'] ?? j['coach_name']) as String?,
        enrolledCount: _intN(j['enrolled_count'] ?? j['enrolledCount']),
      );
}

class ProgramDetail {
  const ProgramDetail({
    required this.id,
    required this.name,
    required this.level,
    required this.ageGroup,
    required this.category,
    required this.description,
    required this.defaultDurationMinutes,
    required this.defaultCapacity,
    required this.sessionCount,
    required this.defaultPriceMinor,
    required this.isMembershipIncluded,
    required this.status,
    required this.createdAt,
    required this.activeStudents,
    required this.totalEnrollments,
    required this.scheduledSessions,
    required this.completedSessions,
    this.startDate,
    this.endDate,
    this.sessionsPerWeek,
    this.paymentMode = 'BOTH',
    this.feeType = 'ONE_TIME',
    this.earlyBirdDiscountMinor,
    this.discountValidTill,
    this.taxPercent,
    this.batches = const [],
  });
  final String id;
  final String name;
  final String level;
  final String ageGroup;
  final String category;
  final String? description;
  final int defaultDurationMinutes;
  final int defaultCapacity;
  final int? sessionCount;
  final int? defaultPriceMinor;
  final bool isMembershipIncluded;
  final ProgramStatus status;
  final String createdAt;
  final int activeStudents;
  final int totalEnrollments;
  final int scheduledSessions;
  final int completedSessions;
  final String? startDate;
  final String? endDate;
  final int? sessionsPerWeek;

  /// OFFLINE | ONLINE | BOTH — which collection methods the program allows.
  final String paymentMode;

  /// ONE_TIME | MONTHLY. For MONTHLY, [defaultPriceMinor] is the fee PER MONTH (migration 0110).
  final String feeType;
  final int? earlyBirdDiscountMinor;
  final String? discountValidTill;
  final double? taxPercent;
  final List<ProgramBatch> batches;

  bool get isMonthly => feeType == 'MONTHLY' && !isMembershipIncluded;

  /// Once students have joined, the program's terms are what they signed up for — editing or
  /// deactivating it underneath them is blocked (mirrors the web program page).
  bool get isLocked => activeStudents > 0;

  /// The same lock message the web shows, or null when the program is free to change.
  String? get lockReason => activeStudents > 0
      ? '$activeStudents ${activeStudents == 1 ? 'student is' : 'students are'} enrolled in this program, so it can\'t be edited or deactivated.'
      : null;

  ProgramDetail withFeeType(String value) => ProgramDetail(
        id: id,
        name: name,
        level: level,
        ageGroup: ageGroup,
        category: category,
        description: description,
        defaultDurationMinutes: defaultDurationMinutes,
        defaultCapacity: defaultCapacity,
        sessionCount: sessionCount,
        defaultPriceMinor: defaultPriceMinor,
        isMembershipIncluded: isMembershipIncluded,
        status: status,
        createdAt: createdAt,
        activeStudents: activeStudents,
        totalEnrollments: totalEnrollments,
        scheduledSessions: scheduledSessions,
        completedSessions: completedSessions,
        startDate: startDate,
        endDate: endDate,
        sessionsPerWeek: sessionsPerWeek,
        paymentMode: paymentMode,
        feeType: value,
        earlyBirdDiscountMinor: earlyBirdDiscountMinor,
        discountValidTill: discountValidTill,
        taxPercent: taxPercent,
        batches: batches,
      );

  factory ProgramDetail.fromJson(Map<String, dynamic> j) {
    final s = (j['stats'] as Map?)?.cast<String, dynamic>() ?? const {};
    return ProgramDetail(
      id: j['id'] as String,
      name: j['name'] as String,
      level: j['level'] as String? ?? '',
      ageGroup: j['ageGroup'] as String? ?? '',
      category: j['category'] as String? ?? '',
      description: j['description'] as String?,
      defaultDurationMinutes: _int(j['defaultDurationMinutes']),
      defaultCapacity: _int(j['defaultCapacity']),
      sessionCount: _intN(j['sessionCount']),
      defaultPriceMinor: _intN(j['defaultPriceMinor']),
      isMembershipIncluded: j['isMembershipIncluded'] as bool? ?? false,
      status: ProgramStatus.fromJson(j['status'] as String?),
      createdAt: j['createdAt'] as String? ?? '',
      activeStudents: _int(s['activeStudents']),
      totalEnrollments: _int(s['totalEnrollments']),
      scheduledSessions: _int(s['scheduledSessions']),
      completedSessions: _int(s['completedSessions']),
      startDate: j['startDate'] as String?,
      endDate: j['endDate'] as String?,
      sessionsPerWeek: _intN(j['sessionsPerWeek']),
      paymentMode: j['paymentMode'] as String? ?? 'BOTH',
      feeType: j['feeType'] as String? ?? 'ONE_TIME',
      earlyBirdDiscountMinor: _intN(j['earlyBirdDiscountMinor']),
      discountValidTill: j['discountValidTill'] as String?,
      taxPercent: (j['taxPercent'] as num?)?.toDouble(),
      batches: ((j['batches'] as List<dynamic>?) ?? const [])
          .map((b) => ProgramBatch.fromJson((b as Map).cast<String, dynamic>()))
          .toList(),
    );
  }
}

class ProgramOption {
  const ProgramOption({
    required this.id,
    required this.name,
    required this.defaultCapacity,
    required this.defaultDurationMinutes,
    required this.defaultPriceMinor,
    required this.isMembershipIncluded,
    required this.sessionCount,
    this.feeType = 'ONE_TIME',
    this.endDate,
    this.startDate,
    this.paymentMode = 'BOTH',
    this.earlyBirdDiscountMinor,
    this.taxPercent,
  });
  final String id;
  final String name;
  final int defaultCapacity;
  final int defaultDurationMinutes;
  final int? defaultPriceMinor;
  final bool isMembershipIncluded;
  final int? sessionCount;

  /// 'ONE_TIME' or 'MONTHLY'. For a MONTHLY program [defaultPriceMinor] is the fee PER MONTH and
  /// the enrollment total is that fee × the months until [endDate] (migration 0110).
  final String feeType;
  final String? endDate;

  /// The program's own start date — a program that has not begun yet enrolls students from here.
  final String? startDate;

  /// OFFLINE | ONLINE | BOTH.
  final String paymentMode;
  final int? earlyBirdDiscountMinor;
  final double? taxPercent;

  /// What ONE charge costs a student, in paise: (fee − early-bird discount) + tax, or 0 when the
  /// program is included in a membership. For a monthly program this is the fee for one month.
  /// Same formula as the web Add Student wizard.
  int get chargeMinor {
    if (isMembershipIncluded) return 0;
    final base = defaultPriceMinor ?? 0;
    final afterDiscount = (base - (earlyBirdDiscountMinor ?? 0)).clamp(0, base);
    final tax = taxPercent == null ? 0 : ((afterDiscount / 100) * taxPercent! / 100).round() * 100;
    return afterDiscount + tax;
  }

  bool get onlineAllowed => paymentMode != 'OFFLINE';
  bool get isMonthly => feeType == 'MONTHLY' && !isMembershipIncluded;

  factory ProgramOption.fromJson(Map<String, dynamic> j) => ProgramOption(
        feeType: j['fee_type'] as String? ?? 'ONE_TIME',
        endDate: j['end_date'] as String?,
        startDate: j['start_date'] as String?,
        paymentMode: j['payment_mode'] as String? ?? 'BOTH',
        earlyBirdDiscountMinor: _intN(j['early_bird_discount_minor']),
        taxPercent: (j['tax_percent'] as num?)?.toDouble(),
        id: j['id'] as String,
        name: j['name'] as String,
        defaultCapacity: _int(j['default_capacity']),
        defaultDurationMinutes: _int(j['default_duration_minutes']),
        defaultPriceMinor: _intN(j['default_price_minor']),
        isMembershipIncluded: j['is_membership_included'] as bool? ?? false,
        sessionCount: _intN(j['session_count']),
      );
}

// ── Sessions ───────────────────────────────────────────────────────────────
class SessionRow {
  const SessionRow({
    required this.id,
    required this.programId,
    required this.programName,
    required this.coachId,
    required this.coachName,
    required this.courtId,
    required this.courtName,
    required this.startAt,
    required this.endAt,
    required this.capacity,
    required this.enrolledCount,
    required this.status,
  });
  final String id;
  final String programId;
  final String programName;
  final String coachId;
  final String coachName;
  final String courtId;
  final String courtName;
  final DateTime startAt;
  final DateTime endAt;
  final int capacity;
  final int enrolledCount;
  final SessionStatus status;
  factory SessionRow.fromJson(Map<String, dynamic> j) => SessionRow(
        id: j['id'] as String,
        programId: j['program_id'] as String? ?? '',
        programName: j['program_name'] as String? ?? '',
        coachId: j['coach_id'] as String? ?? '',
        coachName: j['coach_name'] as String? ?? '',
        courtId: j['court_id'] as String? ?? '',
        courtName: j['court_name'] as String? ?? '',
        startAt: DateTime.parse(j['start_at'] as String),
        endAt: DateTime.parse(j['end_at'] as String),
        capacity: _int(j['capacity']),
        enrolledCount: _int(j['enrolled_count']),
        status: SessionStatus.fromJson(j['status'] as String?),
      );
}

class SessionPage {
  const SessionPage({required this.sessions, required this.totalCount});
  final List<SessionRow> sessions;
  final int totalCount;
  factory SessionPage.fromRows(List<Map<String, dynamic>> rows) => SessionPage(
        sessions: rows.map(SessionRow.fromJson).toList(),
        totalCount: rows.isEmpty ? 0 : _int(rows.first['total_count']),
      );
}

class SessionStudent {
  const SessionStudent({required this.enrollmentId, required this.name, required this.phone, required this.enrollmentStatus});
  final String enrollmentId;
  final String name;
  final String? phone;
  final EnrollmentStatus enrollmentStatus;
  factory SessionStudent.fromJson(Map<String, dynamic> j) => SessionStudent(
        enrollmentId: j['enrollmentId'] as String,
        name: j['name'] as String? ?? '',
        phone: j['phone'] as String?,
        enrollmentStatus: EnrollmentStatus.fromJson(j['enrollmentStatus'] as String?),
      );
}

class SessionProgressNote {
  const SessionProgressNote({required this.id, required this.memberName, required this.skillOrGoal, required this.note, required this.progressStatus, required this.createdAt});
  final String id;
  final String memberName;
  final String? skillOrGoal;
  final String note;
  final ProgressStatus progressStatus;
  final DateTime createdAt;
  factory SessionProgressNote.fromJson(Map<String, dynamic> j) => SessionProgressNote(
        id: j['id'] as String,
        memberName: j['memberName'] as String? ?? '',
        skillOrGoal: j['skillOrGoal'] as String?,
        note: j['note'] as String? ?? '',
        progressStatus: ProgressStatus.fromJson(j['progressStatus'] as String?),
        createdAt: DateTime.parse(j['createdAt'] as String),
      );
}

class CoachingEventRow {
  const CoachingEventRow({required this.id, required this.summary, required this.actorName, required this.createdAt});
  final String id;
  final String summary;
  final String? actorName;
  final DateTime createdAt;
  factory CoachingEventRow.fromJson(Map<String, dynamic> j) => CoachingEventRow(
        id: j['id'] as String,
        summary: j['summary'] as String? ?? '',
        actorName: j['actorName'] as String? ?? j['actor_name'] as String?,
        createdAt: DateTime.parse((j['createdAt'] ?? j['created_at']) as String),
      );
}

class SessionDetail {
  const SessionDetail({
    required this.id,
    required this.facilityId,
    required this.programId,
    required this.programName,
    required this.programLevel,
    required this.coachId,
    required this.coachName,
    required this.courtId,
    required this.courtName,
    required this.startAt,
    required this.endAt,
    required this.capacity,
    required this.status,
    required this.notes,
    required this.objective,
    required this.objectiveResult,
    required this.cancelReason,
    required this.enrolledCount,
    required this.students,
    required this.progressNotes,
    required this.canViewProgress,
    required this.events,
  });

  final String id;
  final String facilityId;
  final String programId;
  final String programName;
  final String programLevel;
  final String coachId;
  final String coachName;
  final String courtId;
  final String courtName;
  final DateTime startAt;
  final DateTime endAt;
  final int capacity;
  final SessionStatus status;
  final String? notes;
  final String? objective;
  final String? objectiveResult;
  final String? cancelReason;
  final int enrolledCount;
  final List<SessionStudent> students;
  final List<SessionProgressNote> progressNotes;
  final bool canViewProgress;
  final List<CoachingEventRow> events;

  factory SessionDetail.fromJson(Map<String, dynamic> j) => SessionDetail(
        id: j['id'] as String,
        facilityId: j['facilityId'] as String,
        programId: j['programId'] as String,
        programName: j['programName'] as String? ?? '',
        programLevel: j['programLevel'] as String? ?? '',
        coachId: j['coachId'] as String,
        coachName: j['coachName'] as String? ?? '',
        courtId: j['courtId'] as String,
        courtName: j['courtName'] as String? ?? '',
        startAt: DateTime.parse(j['startAt'] as String),
        endAt: DateTime.parse(j['endAt'] as String),
        capacity: _int(j['capacity']),
        status: SessionStatus.fromJson(j['status'] as String?),
        notes: j['notes'] as String?,
        objective: j['objective'] as String?,
        objectiveResult: j['objectiveResult'] as String?,
        cancelReason: j['cancelReason'] as String?,
        enrolledCount: _int(j['enrolledCount']),
        students: _rows(j['students']).map(SessionStudent.fromJson).toList(),
        canViewProgress: j['progressNotes'] != null,
        progressNotes: _rows(j['progressNotes']).map(SessionProgressNote.fromJson).toList(),
        events: _rows(j['events']).map(CoachingEventRow.fromJson).toList(),
      );
}

// ── Enrollments ────────────────────────────────────────────────────────────
class EnrollmentRow {
  const EnrollmentRow({
    required this.id,
    required this.studentName,
    required this.programName,
    required this.startDate,
    required this.endDate,
    required this.priceMinor,
    required this.status,
    required this.paymentStatus,
    this.programId = '',
    this.studentPhone,
    this.studentAge,
    this.batchName,
    this.coachName,
  });
  final String programId;
  final String? studentPhone;
  final int? studentAge;
  final String? batchName;
  final String? coachName;
  final String id;
  final String studentName;
  final String programName;
  final String startDate;
  final String? endDate;
  final int priceMinor;
  final EnrollmentStatus status;
  final EnrollmentPaymentStatus paymentStatus;
  factory EnrollmentRow.fromJson(Map<String, dynamic> j) => EnrollmentRow(
        programId: j['program_id'] as String? ?? '',
        studentPhone: j['student_phone'] as String?,
        studentAge: _intN(j['student_age']),
        batchName: j['batch_name'] as String?,
        coachName: j['coach_name'] as String?,
        id: j['id'] as String,
        studentName: j['student_name'] as String? ?? '',
        programName: j['program_name'] as String? ?? '',
        startDate: j['start_date'] as String? ?? '',
        endDate: j['end_date'] as String?,
        priceMinor: _int(j['price_minor']),
        status: EnrollmentStatus.fromJson(j['status'] as String?),
        paymentStatus: EnrollmentPaymentStatus.fromJson(j['payment_status'] as String?),
      );
}

class EnrollmentPage {
  const EnrollmentPage({required this.enrollments, required this.totalCount});
  final List<EnrollmentRow> enrollments;
  final int totalCount;
  factory EnrollmentPage.fromRows(List<Map<String, dynamic>> rows) => EnrollmentPage(
        enrollments: rows.map(EnrollmentRow.fromJson).toList(),
        totalCount: rows.isEmpty ? 0 : _int(rows.first['total_count']),
      );
}

class EnrollmentSessionRef {
  const EnrollmentSessionRef({required this.id, required this.startAt, required this.programName, required this.courtName, required this.status});
  final String id;
  final DateTime startAt;
  final String programName;
  final String courtName;
  final SessionStatus status;
  factory EnrollmentSessionRef.fromJson(Map<String, dynamic> j) => EnrollmentSessionRef(
        id: j['id'] as String,
        startAt: DateTime.parse(j['startAt'] as String),
        programName: j['programName'] as String? ?? '',
        courtName: j['courtName'] as String? ?? '',
        status: SessionStatus.fromJson(j['status'] as String?),
      );
}

class EnrollmentPaymentRef {
  const EnrollmentPaymentRef({required this.id, required this.amountMinor, required this.paidAt, required this.method});
  final String id;
  final int amountMinor;
  final DateTime paidAt;
  final String? method;
  factory EnrollmentPaymentRef.fromJson(Map<String, dynamic> j) => EnrollmentPaymentRef(
        id: j['id'] as String,
        amountMinor: _int(j['amountMinor']),
        paidAt: DateTime.parse(j['paidAt'] as String),
        method: j['method'] as String?,
      );
}

class EnrollmentProgressNote {
  const EnrollmentProgressNote({required this.id, required this.skillOrGoal, required this.note, required this.progressStatus, required this.coachName, required this.createdAt});
  final String id;
  final String? skillOrGoal;
  final String note;
  final ProgressStatus progressStatus;
  final String? coachName;
  final DateTime createdAt;
  factory EnrollmentProgressNote.fromJson(Map<String, dynamic> j) => EnrollmentProgressNote(
        id: j['id'] as String,
        skillOrGoal: j['skillOrGoal'] as String?,
        note: j['note'] as String? ?? '',
        progressStatus: ProgressStatus.fromJson(j['progressStatus'] as String?),
        coachName: j['coachName'] as String?,
        createdAt: DateTime.parse(j['createdAt'] as String),
      );
}

class EnrollmentDetail {
  const EnrollmentDetail({
    required this.id,
    required this.facilityId,
    required this.studentName,
    required this.studentPhone,
    required this.programId,
    required this.programName,
    required this.programLevel,
    required this.coachName,
    required this.startDate,
    required this.endDate,
    required this.sessionsTotal,
    required this.priceMinor,
    required this.paidMinor,
    required this.outstandingMinor,
    required this.pricingType,
    required this.status,
    required this.notes,
    required this.cancelReason,
    required this.createdAt,
    required this.sessions,
    required this.payments,
    required this.progressNotes,
    required this.canViewProgress,
    this.batchName,
  });

  final String? batchName;
  final String id;
  final String facilityId;
  final String studentName;
  final String? studentPhone;
  final String programId;
  final String programName;
  final String programLevel;
  final String? coachName;
  final String startDate;
  final String? endDate;
  final int? sessionsTotal;
  final int priceMinor;
  final int paidMinor;
  final int outstandingMinor;
  final String pricingType;
  final EnrollmentStatus status;
  final String? notes;
  final String? cancelReason;
  final String createdAt;
  final List<EnrollmentSessionRef> sessions;
  final List<EnrollmentPaymentRef> payments;
  final List<EnrollmentProgressNote> progressNotes;
  final bool canViewProgress;

  bool get isMembershipIncluded => pricingType == 'MEMBERSHIP_INCLUDED';

  factory EnrollmentDetail.fromJson(Map<String, dynamic> j) => EnrollmentDetail(
        batchName: j['batchName'] as String?,
        id: j['id'] as String,
        facilityId: j['facilityId'] as String,
        studentName: j['studentName'] as String? ?? '',
        studentPhone: j['studentPhone'] as String?,
        programId: j['programId'] as String,
        programName: j['programName'] as String? ?? '',
        programLevel: j['programLevel'] as String? ?? '',
        coachName: j['coachName'] as String?,
        startDate: j['startDate'] as String? ?? '',
        endDate: j['endDate'] as String?,
        sessionsTotal: _intN(j['sessionsTotal']),
        priceMinor: _int(j['priceMinor']),
        paidMinor: _int(j['paidMinor']),
        outstandingMinor: _int(j['outstandingMinor']),
        pricingType: j['pricingType'] as String? ?? 'STANDARD',
        status: EnrollmentStatus.fromJson(j['status'] as String?),
        notes: j['notes'] as String?,
        cancelReason: j['cancelReason'] as String?,
        createdAt: j['createdAt'] as String? ?? '',
        sessions: _rows(j['sessions']).map(EnrollmentSessionRef.fromJson).toList(),
        payments: _rows(j['payments']).map(EnrollmentPaymentRef.fromJson).toList(),
        canViewProgress: j['progressNotes'] != null,
        progressNotes: _rows(j['progressNotes']).map(EnrollmentProgressNote.fromJson).toList(),
      );
}

// ── Reports ────────────────────────────────────────────────────────────────
class CoachingReports {
  const CoachingReports({
    required this.activeStudents,
    required this.activePrograms,
    required this.sessionsInRange,
    required this.completedSessionsInRange,
    required this.coachingRevenueMinor,
    required this.avgCapacityUtilization,
    required this.programPerformance,
    required this.coachUtilization,
    required this.studentGrowth,
  });

  final int activeStudents;
  final int activePrograms;
  final int sessionsInRange;
  final int completedSessionsInRange;
  final int coachingRevenueMinor;
  final double avgCapacityUtilization;
  final List<ProgramPerformance> programPerformance;
  final List<CoachUtilization> coachUtilization;
  final List<GrowthPoint> studentGrowth;

  factory CoachingReports.fromJson(Map<String, dynamic> j) {
    final k = (j['kpis'] as Map?)?.cast<String, dynamic>() ?? const {};
    return CoachingReports(
      activeStudents: _int(k['activeStudents']),
      activePrograms: _int(k['activePrograms']),
      sessionsInRange: _int(k['sessionsInRange']),
      completedSessionsInRange: _int(k['completedSessionsInRange']),
      coachingRevenueMinor: _int(k['coachingRevenueMinor']),
      avgCapacityUtilization: _dbl(k['avgCapacityUtilization']),
      programPerformance: _rows(j['programPerformance']).map(ProgramPerformance.fromJson).toList(),
      coachUtilization: _rows(j['coachUtilization']).map(CoachUtilization.fromJson).toList(),
      studentGrowth: _rows(j['studentGrowth']).map(GrowthPoint.fromJson).toList(),
    );
  }
}

class ProgramPerformance {
  const ProgramPerformance({required this.programName, required this.activeStudents, required this.sessions, required this.capacityUtilization, required this.revenueMinor});
  final String programName;
  final int activeStudents;
  final int sessions;
  final double capacityUtilization;
  final int revenueMinor;
  factory ProgramPerformance.fromJson(Map<String, dynamic> j) => ProgramPerformance(
        programName: j['programName'] as String? ?? '',
        activeStudents: _int(j['activeStudents']),
        sessions: _int(j['sessions']),
        capacityUtilization: _dbl(j['capacityUtilization']),
        revenueMinor: _int(j['revenueMinor']),
      );
}

class CoachUtilization {
  const CoachUtilization({required this.coachName, required this.scheduledHours, required this.weeklyAvailableHours, required this.sessions});
  final String coachName;
  final double scheduledHours;
  final double weeklyAvailableHours;
  final int sessions;
  factory CoachUtilization.fromJson(Map<String, dynamic> j) => CoachUtilization(
        coachName: j['coachName'] as String? ?? '',
        scheduledHours: _dbl(j['scheduledHours']),
        weeklyAvailableHours: _dbl(j['weeklyAvailableHours']),
        sessions: _int(j['sessions']),
      );
}

// ── Online billing (Razorpay payment link / monthly subscription) ──────────
/// The Razorpay link (one-time program) or AutoPay subscription (monthly program) behind an
/// enrollment — a row of coaching_enrollment_billing (migration 0110).
class EnrollmentBilling {
  const EnrollmentBilling({
    required this.kind,
    required this.status,
    required this.amountMinor,
    required this.totalCycles,
    required this.chargeCount,
    required this.shortUrl,
    required this.currentEnd,
  });

  /// 'PAYMENT_LINK' or 'SUBSCRIPTION'.
  final String kind;

  /// CREATED, AUTHENTICATED, ACTIVE, PENDING, HALTED, PAID, CANCELLED, COMPLETED or EXPIRED.
  final String status;

  /// One charge — the whole fee for a link, the per-month fee for a subscription.
  final int amountMinor;
  final int totalCycles;
  final int chargeCount;
  final String? shortUrl;
  final String? currentEnd;

  bool get isSubscription => kind == 'SUBSCRIPTION';

  /// Still able to take money (not paid / cancelled / finished / expired).
  bool get isLive => const {'CREATED', 'AUTHENTICATED', 'ACTIVE', 'PENDING', 'HALTED'}.contains(status);

  String get statusLabel => switch (status) {
        'CREATED' => 'Awaiting payment',
        'AUTHENTICATED' => 'Mandate approved',
        'ACTIVE' => 'Active',
        'PENDING' => 'Charge pending',
        'HALTED' => 'Halted — charge failed',
        'PAID' => 'Paid',
        'CANCELLED' => 'Cancelled',
        'COMPLETED' => 'Completed',
        'EXPIRED' => 'Link expired',
        _ => status,
      };

  factory EnrollmentBilling.fromJson(Map<String, dynamic> j) => EnrollmentBilling(
        kind: j['kind'] as String,
        status: j['status'] as String,
        amountMinor: _int(j['amount_minor']),
        totalCycles: _int(j['total_cycles']),
        chargeCount: _int(j['charge_count']),
        shortUrl: j['short_url'] as String?,
        currentEnd: j['current_end'] as String?,
      );
}
