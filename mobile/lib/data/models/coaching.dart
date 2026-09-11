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
  });
  final String id;
  final String name;
  final int defaultCapacity;
  final int defaultDurationMinutes;
  final int? defaultPriceMinor;
  final bool isMembershipIncluded;
  final int? sessionCount;
  factory ProgramOption.fromJson(Map<String, dynamic> j) => ProgramOption(
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
  });
  final String id;
  final String studentName;
  final String programName;
  final String startDate;
  final String? endDate;
  final int priceMinor;
  final EnrollmentStatus status;
  final EnrollmentPaymentStatus paymentStatus;
  factory EnrollmentRow.fromJson(Map<String, dynamic> j) => EnrollmentRow(
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
  });

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
