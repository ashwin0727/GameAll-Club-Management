/// What the Enroll Membership page shows for one venue (`get_public_membership_enroll`, migration 0175).
class EnrollInfo {
  const EnrollInfo({
    required this.venueId,
    required this.venueName,
    this.accepting = true,
    this.autopayAvailable = true,
    this.sports = const [],
    this.slots = const [],
    this.plans = const [],
  });

  factory EnrollInfo.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> map(Object? v) =>
        v is Map ? v.cast<String, dynamic>() : const {};
    List<Map<String, dynamic>> list(Object? v) => [
      for (final e in (v as List<dynamic>? ?? const [])) map(e),
    ];
    return EnrollInfo(
      venueId: (json['facilityId'] as String?) ?? '',
      venueName: (json['facilityName'] as String?) ?? '',
      accepting: json['accepting'] != false,
      autopayAvailable: json['autopayAvailable'] != false,
      sports: [
        for (final s in list(json['sports']))
          EnrollSport(
            id: (s['id'] as String?) ?? '',
            name: (s['name'] as String?) ?? '',
          ),
      ],
      slots: [for (final s in list(json['slots'])) EnrollSlot.fromJson(s)],
      plans: [for (final p in list(json['plans'])) EnrollPlan.fromJson(p)],
    );
  }

  final String venueId;
  final String venueName;

  /// False when the club's plan does not let players join online.
  final bool accepting;

  /// False when the club has no AutoPay, so nobody can pay online yet.
  final bool autopayAvailable;
  final List<EnrollSport> sports;
  final List<EnrollSlot> slots;
  final List<EnrollPlan> plans;

  /// Slots are what a player picks first; a club that made no time slots offers its plans without one.
  bool get hasSlots => slots.isNotEmpty;

  EnrollPlan? plan(String? id) => plans.where((p) => p.id == id).firstOrNull;
}

class EnrollSport {
  const EnrollSport({required this.id, required this.name});
  final String id;
  final String name;
}

/// One clock time for one sport, with every batch (court and plan) behind it.
class EnrollSlot {
  const EnrollSlot({
    required this.sportId,
    required this.sportName,
    required this.start,
    required this.end,
    this.capacity = 0,
    this.membersNow = 0,
    this.spare = 0,
    this.batches = const [],
  });

  factory EnrollSlot.fromJson(Map<String, dynamic> json) => EnrollSlot(
    sportId: (json['facilitySportId'] as String?) ?? '',
    sportName: (json['sportName'] as String?) ?? '',
    start: _clock(json['startTime']),
    end: _clock(json['endTime']),
    capacity: (json['capacity'] as num?)?.toInt() ?? 0,
    membersNow: (json['membersNow'] as num?)?.toInt() ?? 0,
    spare: (json['spare'] as num?)?.toInt() ?? 0,
    batches: [
      for (final b in (json['batches'] as List<dynamic>? ?? const []))
        EnrollBatch.fromJson((b as Map).cast<String, dynamic>()),
    ],
  );

  final String sportId;
  final String sportName;

  /// Minutes after midnight.
  final int start;
  final int end;
  final int capacity;

  /// Members who play in this slot today (all its batches).
  final int membersNow;
  final int spare;
  final List<EnrollBatch> batches;

  String get key => '$sportId|$start|$end';

  /// "6:00 PM – 7:00 PM".
  String get label => '${clockLabel(start)} – ${clockLabel(end)}';

  Set<String> get planIds => {for (final b in batches) b.planId};

  /// The first batch of [planId] in this slot. (Clubs put no limit on how many members share a slot.)
  EnrollBatch? batchFor(String planId) =>
      batches.where((b) => b.planId == planId).firstOrNull;

  /// Members playing in this slot on [planId]'s batches.
  int membersOn(String planId) => batches
      .where((b) => b.planId == planId)
      .fold(0, (n, b) => n + b.enrolled);

  @override
  bool operator ==(Object other) => other is EnrollSlot && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

class EnrollBatch {
  const EnrollBatch({
    required this.id,
    required this.planId,
    this.courtName = '',
    this.capacity = 0,
    this.enrolled = 0,
    this.spare = 0,
    this.days = const [],
  });

  factory EnrollBatch.fromJson(Map<String, dynamic> json) => EnrollBatch(
    id: (json['batchId'] as String?) ?? '',
    planId: (json['planId'] as String?) ?? '',
    courtName: (json['courtName'] as String?) ?? '',
    capacity: (json['capacity'] as num?)?.toInt() ?? 0,
    enrolled: (json['enrolled'] as num?)?.toInt() ?? 0,
    spare: (json['spare'] as num?)?.toInt() ?? 0,
    days: [
      for (final d in (json['daysOfWeek'] as List<dynamic>? ?? const []))
        (d as num).toInt(),
    ],
  );

  final String id;
  final String planId;
  final String courtName;
  final int capacity;
  final int enrolled;
  final int spare;

  /// 0 = Sunday … 6 = Saturday.
  final List<int> days;
}

class EnrollPlan {
  const EnrollPlan({
    required this.id,
    required this.name,
    required this.priceInr,
    required this.durationDays,
    this.description,
    this.badge,
    this.features = const [],
    this.joiningFeeInr = 0,
  });

  factory EnrollPlan.fromJson(Map<String, dynamic> json) {
    String? clean(Object? v) {
      final s = (v as String?)?.trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    return EnrollPlan(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      priceInr: (json['priceInr'] as num?)?.toInt() ?? 0,
      durationDays: (json['durationDays'] as num?)?.toInt() ?? 30,
      description: clean(json['description']),
      badge: clean(json['badgeText']),
      features: [
        for (final f in (json['features'] as List<dynamic>? ?? const []))
          if (clean(f) != null) clean(f)!,
      ],
      joiningFeeInr: (json['joiningFeeInr'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String name;
  final int priceInr;
  final int durationDays;
  final String? description;
  final String? badge;
  final List<String> features;
  final int joiningFeeInr;

  /// Whole months of the plan (30 → 1, 90 → 3, 365 → 12), or null for a custom length under four weeks.
  int? get months =>
      durationDays >= 28 ? (durationDays / 30).round().clamp(1, 120) : null;

  /// "Valid for 1 month", "Valid for 3 months", "Valid for 1 year", "Valid for 10 days".
  String get validFor {
    final m = months;
    if (m == null)
      return 'Valid for $durationDays ${durationDays == 1 ? 'day' : 'days'}';
    if (durationDays >= 360 && m % 12 == 0)
      return 'Valid for ${m ~/ 12} ${m == 12 ? 'year' : 'years'}';
    return 'Valid for $m ${m == 1 ? 'month' : 'months'}';
  }

  /// "Monthly", "Quarterly", "Half-yearly", "Yearly" when the plan has no name of its own to show.
  String get cadence {
    switch (months) {
      case 1:
        return 'month';
      case 3:
        return '3 months';
      case 6:
        return '6 months';
      case 12:
        return 'year';
      case null:
        return '$durationDays days';
      default:
        return '$months months';
    }
  }

  /// When a membership started on [from] ends: calendar months, like the club's own app (14 Oct + 1 month = 14 Nov), less a day.
  DateTime endFrom(DateTime from) {
    final m = months;
    if (m == null) return from.add(Duration(days: durationDays - 1));
    var year = from.year + (from.month - 1 + m) ~/ 12;
    var month = (from.month - 1 + m) % 12 + 1;
    final last = DateTime(year, month + 1, 0).day;
    return DateTime(
      year,
      month,
      from.day > last ? last : from.day,
    ).subtract(const Duration(days: 1));
  }
}

/// A membership the player's phone number already has at the venue (`get_my_memberships_at`).
class ExistingMembership {
  const ExistingMembership({
    required this.id,
    required this.planName,
    this.endDate,
    this.autoRenew = false,
    this.slots = const [],
  });

  factory ExistingMembership.fromJson(
    Map<String, dynamic> json,
  ) => ExistingMembership(
    id: (json['membershipId'] as String?) ?? '',
    planName: (json['planName'] as String?) ?? 'Membership',
    endDate: DateTime.tryParse((json['endDate'] as String?) ?? ''),
    autoRenew: json['autoRenew'] == true,
    slots: [
      for (final s in (json['slots'] as List<dynamic>? ?? const []))
        () {
          final m = (s as Map).cast<String, dynamic>();
          return '${clockLabel(_clock(m['startTime']))} – ${clockLabel(_clock(m['endTime']))}';
        }(),
    ],
  );

  final String id;
  final String planName;
  final DateTime? endDate;
  final bool autoRenew;

  /// The time slots, such as "6:00 PM – 7:00 PM".
  final List<String> slots;
}

/// The pending membership made for a Pay & Enroll tap.
class EnrollStart {
  const EnrollStart({required this.membershipId, required this.amountInr});
  final String membershipId;
  final int amountInr;
}

/// "18:30:00" → minutes after midnight.
int _clock(Object? v) {
  final parts = ((v as String?) ?? '').split(':');
  if (parts.length < 2) return 0;
  return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
}

/// 1080 → "6:00 PM".
String clockLabel(int minutes) {
  final h = (minutes ~/ 60) % 24;
  final m = minutes % 60;
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:${m.toString().padLeft(2, '0')} ${h < 12 ? 'AM' : 'PM'}';
}
