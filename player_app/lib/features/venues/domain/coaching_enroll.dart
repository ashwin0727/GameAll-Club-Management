import 'membership_enroll.dart' show clockLabel;

/// What the Coaching page shows for one venue (`get_public_coaching_enroll`, migration 0176).
class CoachingInfo {
  const CoachingInfo({
    required this.venueId,
    required this.venueName,
    this.accepting = true,
    this.autopayAvailable = true,
    this.sports = const [],
    this.programs = const [],
  });

  factory CoachingInfo.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> map(Object? v) =>
        v is Map ? v.cast<String, dynamic>() : const {};
    return CoachingInfo(
      venueId: (json['facilityId'] as String?) ?? '',
      venueName: (json['facilityName'] as String?) ?? '',
      accepting: json['accepting'] != false,
      autopayAvailable: json['autopayAvailable'] != false,
      sports: [
        for (final s in (json['sports'] as List<dynamic>? ?? const []))
          CoachingSport(
            id: (map(s)['id'] as String?) ?? '',
            name: (map(s)['name'] as String?) ?? '',
          ),
      ],
      programs: [
        for (final p in (json['programs'] as List<dynamic>? ?? const []))
          CoachingProgram.fromJson(map(p)),
      ],
    );
  }

  final String venueId;
  final String venueName;

  /// False when the club's plan does not let players enrol online.
  final bool accepting;

  /// False when the club has no AutoPay, so a monthly programme cannot be paid online.
  final bool autopayAvailable;
  final List<CoachingSport> sports;
  final List<CoachingProgram> programs;

  /// The programmes of one sport. A programme with no sport of its own is offered under every sport.
  List<CoachingProgram> forSport(String? sportId) => [
    for (final p in programs)
      if (sportId == null || p.sportId == null || p.sportId == sportId) p,
  ];
}

class CoachingSport {
  const CoachingSport({required this.id, required this.name});
  final String id;
  final String name;
}

/// The coach behind a batch (the staff member the club made a coach).
class CoachInfo {
  const CoachInfo({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.certifications,
    this.specialization,
    this.rating,
    this.sessions = 0,
  });

  factory CoachInfo.fromJson(Map<String, dynamic> json) {
    String? clean(Object? v) {
      final s = (v as String?)?.trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    final rating = (json['rating'] as num?)?.toDouble();
    return CoachInfo(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? 'Coach',
      avatarUrl: clean(json['avatarUrl']),
      certifications: clean(json['certifications']),
      specialization: clean(json['specialization']),
      rating: (rating == null || rating <= 0) ? null : rating,
      sessions: (json['sessions'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String name;
  final String? avatarUrl;
  final String? certifications;
  final String? specialization;

  /// Null until the club has rated the coach (nothing is made up).
  final double? rating;

  /// Sessions this coach has completed.
  final int sessions;

  /// "BWF Level 1 Certified", or the specialisation when no certificate is on file.
  String? get credential => certifications ?? specialization;
}

/// One day/time batch of a programme: its own coach, days and seats.
class CoachingBatch {
  const CoachingBatch({
    required this.id,
    required this.name,
    required this.days,
    required this.start,
    required this.end,
    this.capacity = 0,
    this.enrolled = 0,
    this.coach,
  });

  factory CoachingBatch.fromJson(Map<String, dynamic> json) => CoachingBatch(
    id: (json['id'] as String?) ?? '',
    name: (json['name'] as String?) ?? '',
    days: [
      for (final d in (json['daysOfWeek'] as List<dynamic>? ?? const []))
        (d as num).toInt(),
    ],
    start: _clock(json['startTime']),
    end: _clock(json['endTime']),
    capacity: (json['capacity'] as num?)?.toInt() ?? 0,
    enrolled: (json['enrolled'] as num?)?.toInt() ?? 0,
    coach: json['coach'] is Map
        ? CoachInfo.fromJson((json['coach'] as Map).cast<String, dynamic>())
        : null,
  );

  final String id;
  final String name;

  /// 0 = Sunday … 6 = Saturday.
  final List<int> days;

  /// Minutes after midnight.
  final int start;
  final int end;
  final int capacity;
  final int enrolled;
  final CoachInfo? coach;

  int get seatsLeft => (capacity - enrolled).clamp(0, capacity);
  bool get full => capacity > 0 && enrolled >= capacity;

  CoachingSlot get slot => CoachingSlot(start: start, end: end);

  /// "Mon, Wed, Fri", or "Every day".
  String get daysLabel {
    const names = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    final d = ({...days}.toList()..sort());
    if (d.length == 7) return 'Every day';
    // Monday first, like the club's calendar
    d.sort((a, b) => ((a + 6) % 7).compareTo((b + 6) % 7));
    return d.map((x) => names[x % 7]).join(', ');
  }
}

/// One clock time range ("6:00 PM – 7:00 PM") a player picks as their regular training time.
class CoachingSlot implements Comparable<CoachingSlot> {
  const CoachingSlot({required this.start, required this.end});
  final int start;
  final int end;

  String get label => '${clockLabel(start)} – ${clockLabel(end)}';

  @override
  int compareTo(CoachingSlot other) => start != other.start
      ? start.compareTo(other.start)
      : end.compareTo(other.end);

  @override
  bool operator ==(Object other) =>
      other is CoachingSlot && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// A coaching programme the staff created, with its fee model and batches.
class CoachingProgram {
  const CoachingProgram({
    required this.id,
    required this.name,
    this.level = 'All Levels',
    this.ageGroup,
    this.description,
    this.sportId,
    this.sportName,
    this.programType = 'GROUP',
    this.feeType = 'ONE_TIME',
    this.durationMinutes = 60,
    this.sessionsPerWeek,
    this.sessionCount,
    this.structure = const [],
    this.baseMinor = 0,
    this.discountMinor = 0,
    this.taxPercent = 0,
    this.chargeMinor = 0,
    this.cycles = 1,
    this.startDate,
    this.endDate,
    this.enrollmentDeadline,
    this.membershipIncluded = false,
    this.paymentNotes,
    this.enrollmentOpen = true,
    this.onlinePayable = true,
    this.batches = const [],
  });

  factory CoachingProgram.fromJson(Map<String, dynamic> json) {
    String? clean(Object? v) {
      final s = (v as String?)?.trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    return CoachingProgram(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      level: clean(json['level']) ?? 'All Levels',
      ageGroup: clean(json['ageGroup']),
      description: clean(json['description']),
      sportId: json['facilitySportId'] as String?,
      sportName: clean(json['sportName']),
      programType: (json['programType'] as String?) ?? 'GROUP',
      feeType: (json['feeType'] as String?) ?? 'ONE_TIME',
      durationMinutes: (json['durationMinutes'] as num?)?.toInt() ?? 60,
      sessionsPerWeek: (json['sessionsPerWeek'] as num?)?.toInt(),
      sessionCount: (json['sessionCount'] as num?)?.toInt(),
      structure: [
        for (final s in (json['structure'] as List<dynamic>? ?? const []))
          if (clean(s) != null) clean(s)!,
      ],
      baseMinor: (json['baseMinor'] as num?)?.toInt() ?? 0,
      discountMinor: (json['discountMinor'] as num?)?.toInt() ?? 0,
      taxPercent: (json['taxPercent'] as num?)?.toDouble() ?? 0,
      chargeMinor: (json['chargeMinor'] as num?)?.toInt() ?? 0,
      cycles: (json['cycles'] as num?)?.toInt() ?? 1,
      startDate: DateTime.tryParse((json['startDate'] as String?) ?? ''),
      endDate: DateTime.tryParse((json['endDate'] as String?) ?? ''),
      enrollmentDeadline: DateTime.tryParse(
        (json['enrollmentDeadline'] as String?) ?? '',
      ),
      membershipIncluded: json['membershipIncluded'] == true,
      paymentNotes: clean(json['paymentNotes']),
      enrollmentOpen: json['enrollmentOpen'] != false,
      onlinePayable: json['onlinePayable'] != false,
      batches: [
        for (final b in (json['batches'] as List<dynamic>? ?? const []))
          CoachingBatch.fromJson((b as Map).cast<String, dynamic>()),
      ],
    );
  }

  final String id;
  final String name;

  /// Beginner, Intermediate, Advanced or All Levels.
  final String level;
  final String? ageGroup;
  final String? description;
  final String? sportId;
  final String? sportName;

  /// GROUP, ONE_ON_ONE or TRIAL.
  final String programType;

  /// ONE_TIME (one fee) or MONTHLY (the fee is charged every month until the programme ends).
  final String feeType;
  final int durationMinutes;
  final int? sessionsPerWeek;
  final int? sessionCount;
  final List<String> structure;

  /// Paise.
  final int baseMinor;
  final int discountMinor;
  final double taxPercent;

  /// One charge, paise: fee − discount + tax. For a monthly programme this is the fee of one month.
  final int chargeMinor;

  /// How many charges a monthly programme makes from the start date to its end (1 for a one-time fee).
  final int cycles;
  final DateTime? startDate;
  final DateTime? endDate;
  final DateTime? enrollmentDeadline;
  final bool membershipIncluded;
  final String? paymentNotes;
  final bool enrollmentOpen;

  /// False when the club collects this one at the club (or it is included in a membership).
  final bool onlinePayable;
  final List<CoachingBatch> batches;

  bool get isMonthly => feeType == 'MONTHLY';

  /// Whole rupees of one charge.
  int get chargeInr => (chargeMinor / 100).round();
  int get baseInr => (baseMinor / 100).round();
  int get discountInr => (discountMinor / 100).round();
  int get taxInr {
    final net = baseMinor - discountMinor;
    return (chargeMinor - (net < 0 ? 0 : net)) ~/ 100;
  }

  int get totalInr => chargeInr * cycles;

  /// "Group", "One-on-one", "Trial".
  String get typeLabel => switch (programType) {
    'ONE_ON_ONE' => 'One-on-one',
    'TRIAL' => 'Trial',
    _ => 'Group',
  };

  /// Beginner / Intermediate / Advanced, or null for "All Levels" (which belongs to every coaching type).
  String? get levelKey {
    final l = level.toLowerCase();
    if (l.contains('begin')) return 'Beginner';
    if (l.contains('inter')) return 'Intermediate';
    if (l.contains('adv')) return 'Advanced';
    return null;
  }

  /// "Monthly (3 months)", "Monthly (1 month)", "One-time".
  String get durationLabel => isMonthly
      ? 'Monthly ($cycles ${cycles == 1 ? 'month' : 'months'})'
      : 'One-time fee';
}

/// A programme in one specific batch: what a card on the Coaching page stands for (one coach, one time slot, one price).
class CoachingOffer {
  const CoachingOffer({required this.program, this.batch});
  final CoachingProgram program;

  /// Null for a programme the club made without any batch.
  final CoachingBatch? batch;

  String get key => '${program.id}|${batch?.id ?? ''}';
  bool get full => batch?.full ?? false;

  /// Group size shown on the card: "Group (Max 8)", "One-on-one", "Trial".
  String get groupLabel {
    final b = batch;
    if (program.programType == 'GROUP' && b != null && b.capacity > 0) {
      return 'Group (Max ${b.capacity})';
    }
    return program.typeLabel;
  }

  @override
  bool operator ==(Object other) => other is CoachingOffer && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// A coaching enrolment the player already has at the venue (`get_my_coaching_at`).
class MyCoaching {
  const MyCoaching({
    required this.enrollmentId,
    required this.programId,
    required this.programName,
    this.batchId,
    this.status = 'ACTIVE',
    this.feeType = 'ONE_TIME',
    this.priceMinor = 0,
    this.paidMinor = 0,
    this.billingKind,
    this.billingStatus,
    this.billingUrl,
    this.endDate,
  });

  factory MyCoaching.fromJson(Map<String, dynamic> json) => MyCoaching(
    enrollmentId: (json['enrollmentId'] as String?) ?? '',
    programId: (json['programId'] as String?) ?? '',
    programName: (json['programName'] as String?) ?? 'Coaching',
    batchId: json['batchId'] as String?,
    status: (json['status'] as String?) ?? 'ACTIVE',
    feeType: (json['feeType'] as String?) ?? 'ONE_TIME',
    priceMinor: (json['priceMinor'] as num?)?.toInt() ?? 0,
    paidMinor: (json['paidMinor'] as num?)?.toInt() ?? 0,
    billingKind: json['billingKind'] as String?,
    billingStatus: json['billingStatus'] as String?,
    billingUrl: json['billingUrl'] as String?,
    endDate: DateTime.tryParse((json['endDate'] as String?) ?? ''),
  );

  final String enrollmentId;
  final String programId;
  final String programName;
  final String? batchId;
  final String status;
  final String feeType;
  final int priceMinor;
  final int paidMinor;
  final String? billingKind;
  final String? billingStatus;
  final String? billingUrl;
  final DateTime? endDate;

  /// Paid, or the AutoPay mandate is approved: nothing more to do.
  bool get settled =>
      paidMinor > 0 ||
      const {
        'AUTHENTICATED',
        'ACTIVE',
        'PENDING',
        'PAID',
        'COMPLETED',
      }.contains(billingStatus);

  /// Made but not paid yet.
  bool get awaitingPayment => !settled;
}

/// The pending enrolment made by a Pay & Enroll tap.
class CoachingStart {
  const CoachingStart({
    required this.enrollmentId,
    required this.feeType,
    required this.cycles,
    required this.chargeMinor,
    required this.totalMinor,
  });
  final String enrollmentId;
  final String feeType;
  final int cycles;
  final int chargeMinor;
  final int totalMinor;
}

/// "18:30:00" → minutes after midnight.
int _clock(Object? v) {
  final parts = ((v as String?) ?? '').split(':');
  if (parts.length < 2) return 0;
  return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
}
