/// One of the player's coaching enrolments with everything the My Coaching page shows. Read from the database function
/// `get_my_coaching_details` (migration 0183): the programme, its coach and batch, the venue, the sessions, the fee and what has been paid,
/// and the coach's notes — all from the club's own records.
class CoachingDetail {
  const CoachingDetail({
    required this.id,
    required this.ref,
    required this.programName,
    required this.venue,
    this.status = 'ACTIVE',
    this.level,
    this.sport,
    this.programType,
    this.description,
    this.sessionsPerWeek,
    this.startDate,
    this.endDate,
    this.feeType = 'ONE_TIME',
    this.coach,
    this.batch,
    this.progress = const CoachingProgress(),
    this.totalInr = 0,
    this.chargeInr = 0,
    this.paidInr = 0,
    this.payState = 'PAID',
    this.upcoming = const [],
    this.past = const [],
    this.payments = const [],
    this.notes = const [],
  });

  factory CoachingDetail.fromJson(Map<String, dynamic> j) {
    Map<String, dynamic>? map(Object? v) =>
        v is Map ? v.cast<String, dynamic>() : null;
    List<Map<String, dynamic>> list(Object? v) => [
      for (final e in (v as List<dynamic>? ?? const []))
        if (e is Map) e.cast<String, dynamic>(),
    ];
    final venue = map(j['venue']) ?? const {};
    final coach = map(j['coach']);
    final batch = map(j['batch']);
    return CoachingDetail(
      id: j['id'] as String,
      ref: (j['enrollmentRef'] as String?) ?? '',
      programName: (j['programName'] as String?) ?? 'Coaching',
      status: (j['status'] as String?) ?? 'ACTIVE',
      level: _clean(j['level'] as String?),
      sport: _clean(j['sport'] as String?),
      programType: j['programType'] as String?,
      description: _clean(j['description'] as String?),
      sessionsPerWeek: (j['sessionsPerWeek'] as num?)?.toInt(),
      startDate: _date(j['startDate']),
      endDate: _date(j['endDate']),
      feeType: (j['feeType'] as String?) ?? 'ONE_TIME',
      venue: CoachingVenue(
        id: (venue['id'] as String?) ?? '',
        name: (venue['name'] as String?) ?? '',
        area: _clean(venue['area'] as String?),
        city: _clean(venue['city'] as String?),
        phone: _clean(venue['phone'] as String?),
        imageUrl: _clean(venue['imageUrl'] as String?),
      ),
      coach: coach == null
          ? null
          : CoachingCoach(
              name: (coach['name'] as String?) ?? 'Your coach',
              avatarUrl: _clean(coach['avatarUrl'] as String?),
              certification: _clean(coach['certification'] as String?),
              experienceYears: (coach['experienceYears'] as num?)?.toDouble(),
              rating: (coach['rating'] as num?)?.toDouble(),
              reviews: (coach['reviews'] as num?)?.toInt(),
            ),
      batch: batch == null
          ? null
          : CoachingBatchInfo(
              name: (batch['name'] as String?) ?? '',
              days: [
                for (final d
                    in (batch['daysOfWeek'] as List<dynamic>? ?? const []))
                  (d as num).toInt(),
              ],
              startTime: batch['startTime'] as String?,
              endTime: batch['endTime'] as String?,
              capacity: (batch['capacity'] as num?)?.toInt(),
              court: _clean(batch['court'] as String?),
            ),
      progress: () {
        final p = map(j['progress']) ?? const {};
        return CoachingProgress(
          total: (p['sessionsTotal'] as num?)?.toInt(),
          attended: (p['sessionsAttended'] as num?)?.toInt() ?? 0,
          percent: (p['percent'] as num?)?.toInt() ?? 0,
        );
      }(),
      totalInr: (j['totalInr'] as num?)?.toInt() ?? 0,
      chargeInr: (j['chargeInr'] as num?)?.toInt() ?? 0,
      paidInr: (j['paidInr'] as num?)?.toInt() ?? 0,
      payState: (j['payState'] as String?) ?? 'PAID',
      upcoming: [
        for (final s in list(j['upcoming'])) CoachingSession.fromJson(s),
      ],
      past: [for (final s in list(j['past'])) CoachingSession.fromJson(s)],
      payments: [
        for (final p in list(j['payments'])) CoachingPayment.fromJson(p),
      ],
      notes: [for (final n in list(j['notes'])) CoachingNote.fromJson(n)],
    );
  }

  final String id;

  /// "CRS-CHA-1A2B3C".
  final String ref;
  final String programName;
  final CoachingVenue venue;

  /// ACTIVE or PAUSED.
  final String status;
  final String? level;
  final String? sport;

  /// GROUP, ONE_ON_ONE or TRIAL.
  final String? programType;
  final String? description;
  final int? sessionsPerWeek;
  final DateTime? startDate;
  final DateTime? endDate;

  /// MONTHLY (UPI AutoPay) or ONE_TIME.
  final String feeType;
  final CoachingCoach? coach;
  final CoachingBatchInfo? batch;
  final CoachingProgress progress;

  /// The fee of the whole programme.
  final int totalInr;

  /// What one payment is (the monthly fee for an AutoPay programme, else the whole fee).
  final int chargeInr;
  final int paidInr;

  /// PAID, PENDING or FAILED.
  final String payState;
  final List<CoachingSession> upcoming;
  final List<CoachingSession> past;
  final List<CoachingPayment> payments;
  final List<CoachingNote> notes;

  bool get isPaid => payState == 'PAID';
  bool get isPaused => status == 'PAUSED';
  bool get isMonthly => feeType == 'MONTHLY';

  /// "Group Coaching" / "Individual Coaching" / "Trial Class".
  String get typeLabel => switch (programType) {
    'ONE_ON_ONE' => 'Individual Coaching',
    'TRIAL' => 'Trial Class',
    _ => 'Group Coaching',
  };

  /// "Group Batch" / "Individual" / "Trial" (the programme details row).
  String get batchTypeLabel => switch (programType) {
    'ONE_ON_ONE' => 'Individual',
    'TRIAL' => 'Trial',
    _ => 'Group Batch',
  };

  /// "3 Months" / "1 Month" / "45 Days", from the programme's own dates (null when it has no end date).
  String? get durationLabel {
    final s = startDate;
    final e = endDate;
    if (s == null || e == null || e.isBefore(s)) return null;
    final days = e.difference(s).inDays + 1;
    final months = (days / 30).round();
    if (days >= 25 && months >= 1)
      return months == 1 ? '1 Month' : '$months Months';
    return days == 1 ? '1 Day' : '$days Days';
  }

  /// "Group Coaching • 3 Months".
  String get subtitle => [typeLabel, ?durationLabel].join(' • ');

  /// How much of the fee is still to pay (never negative).
  int get balanceInr => (totalInr - paidInr).clamp(0, totalInr);
}

class CoachingVenue {
  const CoachingVenue({
    required this.id,
    required this.name,
    this.area,
    this.city,
    this.phone,
    this.imageUrl,
  });

  final String id;
  final String name;
  final String? area;
  final String? city;
  final String? phone;
  final String? imageUrl;

  /// "Iyyapanthangal, Chennai".
  String get place {
    final a = area;
    final c = city;
    if (a != null && c != null && a.toLowerCase() == c.toLowerCase()) return c;
    return [?a, ?c].join(', ');
  }
}

class CoachingCoach {
  const CoachingCoach({
    required this.name,
    this.avatarUrl,
    this.certification,
    this.experienceYears,
    this.rating,
    this.reviews,
  });

  final String name;
  final String? avatarUrl;
  final String? certification;
  final double? experienceYears;

  /// Null when the club has not rated the coach: no rating is shown then.
  final double? rating;
  final int? reviews;

  /// "5+ Years Experience", "8 Years Experience", "Under a year" — null when the club has not said.
  String? get experienceLabel {
    final y = experienceYears;
    if (y == null || y <= 0) return null;
    if (y < 1) return 'Under a year of experience';
    final whole = y.floor();
    return '$whole${y > whole ? '+' : ''} Year${whole == 1 && y <= whole ? '' : 's'} Experience';
  }
}

class CoachingBatchInfo {
  const CoachingBatchInfo({
    required this.name,
    this.days = const [],
    this.startTime,
    this.endTime,
    this.capacity,
    this.court,
  });

  final String name;

  /// 0 = Sunday … 6 = Saturday.
  final List<int> days;
  final String? startTime;
  final String? endTime;
  final int? capacity;
  final String? court;
}

class CoachingProgress {
  const CoachingProgress({this.total, this.attended = 0, this.percent = 0});

  final int? total;
  final int attended;

  /// 0 … 100.
  final int percent;
}

class CoachingSession {
  const CoachingSession({
    required this.id,
    required this.start,
    required this.end,
    required this.status,
    this.court,
  });

  factory CoachingSession.fromJson(Map<String, dynamic> j) => CoachingSession(
    id: (j['id'] as String?) ?? '',
    start: DateTime.parse(j['startTime'] as String).toLocal(),
    end: DateTime.parse(j['endTime'] as String).toLocal(),
    status: (j['status'] as String?) ?? 'SCHEDULED',
    court: _clean(j['court'] as String?),
  );

  final String id;
  final DateTime start;
  final DateTime end;

  /// SCHEDULED, CONFIRMED, IN_PROGRESS, COMPLETED or CANCELLED.
  final String status;
  final String? court;

  bool get completed => status == 'COMPLETED';
  bool get cancelled => status == 'CANCELLED';
}

class CoachingPayment {
  const CoachingPayment({
    required this.id,
    required this.amountInr,
    required this.status,
    this.method,
    this.paidAt,
    this.reference,
  });

  factory CoachingPayment.fromJson(Map<String, dynamic> j) => CoachingPayment(
    id: (j['id'] as String?) ?? '',
    amountInr: (j['amountInr'] as num?)?.toInt() ?? 0,
    status: (j['status'] as String?) ?? 'paid',
    method: _clean(j['method'] as String?),
    paidAt: j['paidAt'] is String
        ? DateTime.tryParse(j['paidAt'] as String)?.toLocal()
        : null,
    reference: _clean(j['reference'] as String?),
  );

  final String id;
  final int amountInr;

  /// paid, failed, created, refunded.
  final String status;
  final String? method;
  final DateTime? paidAt;
  final String? reference;
}

class CoachingNote {
  const CoachingNote({
    required this.id,
    required this.note,
    required this.progress,
    this.skill,
    this.coach,
    this.createdAt,
  });

  factory CoachingNote.fromJson(Map<String, dynamic> j) => CoachingNote(
    id: (j['id'] as String?) ?? '',
    note: (j['note'] as String?) ?? '',
    progress: (j['progress'] as String?) ?? 'ON_TRACK',
    skill: _clean(j['skill'] as String?),
    coach: _clean(j['coach'] as String?),
    createdAt: j['createdAt'] is String
        ? DateTime.tryParse(j['createdAt'] as String)?.toLocal()
        : null,
  );

  final String id;
  final String note;

  /// ON_TRACK, NEEDS_WORK, EXCELLING or AT_RISK.
  final String progress;
  final String? skill;
  final String? coach;
  final DateTime? createdAt;

  String get progressLabel => switch (progress) {
    'EXCELLING' => 'Excelling',
    'NEEDS_WORK' => 'Needs work',
    'AT_RISK' => 'Needs attention',
    _ => 'On track',
  };
}

DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v) : null;

String? _clean(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
