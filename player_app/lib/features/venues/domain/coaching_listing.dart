import 'venue.dart';

/// The coach shown on a programme's card.
class ListedCoach {
  const ListedCoach({
    required this.name,
    this.avatarUrl,
    this.certifications,
    this.specialization,
    this.rating,
    this.experienceYears,
  });

  factory ListedCoach.fromJson(Map<String, dynamic> json) => ListedCoach(
    name: (json['name'] as String?)?.trim().isNotEmpty == true
        ? (json['name'] as String).trim()
        : 'Coach',
    avatarUrl: _clean(json['avatarUrl'] as String?),
    certifications: _clean(json['certifications'] as String?),
    specialization: _clean(json['specialization'] as String?),
    rating: (json['rating'] as num?)?.toDouble(),
    experienceYears: (json['experienceYears'] as num?)?.toDouble(),
  );

  final String name;
  final String? avatarUrl;
  final String? certifications;
  final String? specialization;

  /// Set by the club's staff; null until they do.
  final double? rating;
  final double? experienceYears;

  /// "BWF Level 1 Certified": the certification, or else the specialisation.
  String? get headline => certifications ?? specialization;

  /// "5+ Years Experience": whole years, only once there is at least one.
  String? get experienceLabel {
    final y = experienceYears?.floor() ?? 0;
    return y >= 1 ? '$y+ Years Experience' : null;
  }

  /// "4.9", or null when no rating has been set (or it is 0).
  String? get ratingLabel =>
      (rating == null || rating! <= 0) ? null : rating!.toStringAsFixed(1);

  String get initials {
    final words = name
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return 'C';
    final skip = words.first.toLowerCase() == 'coach' && words.length > 1;
    final use = skip ? words.sublist(1) : words;
    return (use.length == 1
            ? use.first.substring(0, 1)
            : use.first.substring(0, 1) + use[1].substring(0, 1))
        .toUpperCase();
  }
}

/// One batch of a programme: the time of day and the weekdays (0 = Sunday ... 6 = Saturday).
class ListedBatch {
  const ListedBatch({required this.startHour, required this.days});

  factory ListedBatch.fromJson(Map<String, dynamic> json) {
    final t = (json['startTime'] as String?)?.split(':');
    final h = t == null ? 0 : (int.tryParse(t.first) ?? 0);
    final m = t == null || t.length < 2 ? 0 : (int.tryParse(t[1]) ?? 0);
    return ListedBatch(
      startHour: h + m / 60,
      days: {
        for (final d in (json['daysOfWeek'] as List<dynamic>? ?? const []))
          if (d is num) d.toInt(),
      },
    );
  }

  final double startHour;
  final Set<int> days;
}

/// A coaching programme on the Coaching page: the programme, the venue that runs it and the coach who takes it.
class CoachingListing {
  const CoachingListing({
    required this.programId,
    required this.name,
    required this.venueId,
    required this.venueName,
    this.venueArea,
    this.venueCity = '',
    this.venueImage,
    this.venueVerified = false,
    this.level = 'All Levels',
    this.description,
    this.sport,
    this.programType = 'GROUP',
    this.feeType = 'ONE_TIME',
    this.priceInr,
    this.maxCapacity,
    this.batches = const [],
    this.coach,
  });

  factory CoachingListing.fromJson(Map<String, dynamic> json) {
    final venue = json['venue'] is Map
        ? (json['venue'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final coach = json['coach'] is Map
        ? (json['coach'] as Map).cast<String, dynamic>()
        : null;
    final minor = (json['priceMinor'] as num?)?.toInt() ?? 0;
    return CoachingListing(
      programId: (json['programId'] as String?) ?? '',
      name: (json['name'] as String?) ?? 'Program',
      venueId: (venue['id'] as String?) ?? '',
      venueName: (venue['name'] as String?) ?? 'Venue',
      venueArea: _clean(venue['area'] as String?),
      venueCity: (venue['city'] as String?) ?? '',
      venueImage: _clean(venue['heroImageUrl'] as String?),
      venueVerified: venue['verified'] == true,
      level: _clean(json['level'] as String?) ?? 'All Levels',
      description: _clean(json['description'] as String?),
      sport: _clean(json['sport'] as String?),
      programType: (json['programType'] as String?) ?? 'GROUP',
      feeType: (json['feeType'] as String?) ?? 'ONE_TIME',
      priceInr: minor > 0 ? (minor / 100).round() : null,
      maxCapacity: (json['maxCapacity'] as num?)?.toInt(),
      batches: [
        for (final b in (json['batches'] as List<dynamic>? ?? const []))
          if (b is Map) ListedBatch.fromJson(b.cast<String, dynamic>()),
      ],
      coach: coach == null ? null : ListedCoach.fromJson(coach),
    );
  }

  /// A programme read from the older venue list (before migration 0179 is installed): only a name and the venue's lowest price.
  factory CoachingListing.fromVenueCard(Venue v, String programName) =>
      CoachingListing(
        programId: '${v.id}:$programName',
        name: programName,
        venueId: v.id,
        venueName: v.name,
        venueArea: v.area,
        venueCity: v.city,
        venueImage: v.heroImageUrl,
        venueVerified: v.photos.isNotEmpty,
        sport: v.sports.isEmpty ? null : v.sports.first,
        priceInr: v.minProgramPriceInr,
      );

  /// A programme read from a venue's own enrolment answer (`get_public_coaching_enroll`, migration 0176), which has the description,
  /// the level, the batches and each batch's coach. Used until migration 0179 (the one-call list) is installed.
  factory CoachingListing.fromEnrollProgram(
    Venue v,
    Map<String, dynamic> program,
  ) {
    final batches = [
      for (final b in (program['batches'] as List<dynamic>? ?? const []))
        if (b is Map) b.cast<String, dynamic>(),
    ];
    Map<String, dynamic>? coach;
    for (final b in batches) {
      if (b['coach'] is Map) {
        coach = (b['coach'] as Map).cast<String, dynamic>();
        break;
      }
    }
    var capacity = 0;
    for (final b in batches) {
      final c = (b['capacity'] as num?)?.toInt() ?? 0;
      if (c > capacity) capacity = c;
    }
    final base = (program['baseMinor'] as num?)?.toInt() ?? 0;
    final off = (program['discountMinor'] as num?)?.toInt() ?? 0;
    final minor = base - off > 0 ? base - off : 0;
    return CoachingListing(
      programId: (program['id'] as String?) ?? '${v.id}:program',
      name: (program['name'] as String?) ?? 'Program',
      venueId: v.id,
      venueName: v.name,
      venueArea: v.area,
      venueCity: v.city,
      venueImage: v.heroImageUrl,
      venueVerified: v.photos.isNotEmpty,
      level: _clean(program['level'] as String?) ?? 'All Levels',
      description: _clean(program['description'] as String?),
      sport:
          _clean(program['sportName'] as String?) ??
          (v.sports.isEmpty ? null : v.sports.first),
      programType: (program['programType'] as String?) ?? 'GROUP',
      feeType: (program['feeType'] as String?) ?? 'ONE_TIME',
      priceInr: minor > 0 ? (minor / 100).round() : v.minProgramPriceInr,
      maxCapacity: capacity > 0 ? capacity : null,
      batches: [for (final b in batches) ListedBatch.fromJson(b)],
      coach: coach == null ? null : ListedCoach.fromJson(coach),
    );
  }

  final String programId;
  final String name;
  final String venueId;
  final String venueName;
  final String? venueArea;
  final String venueCity;
  final String? venueImage;
  final bool venueVerified;
  final String level;
  final String? description;
  final String? sport;

  /// GROUP, ONE_ON_ONE or TRIAL.
  final String programType;

  /// ONE_TIME or MONTHLY.
  final String feeType;
  final int? priceInr;
  final int? maxCapacity;
  final List<ListedBatch> batches;
  final ListedCoach? coach;

  bool get isMonthly => feeType == 'MONTHLY';

  /// "Group Batch", "Individual" or "Trial".
  String get typeLabel => switch (programType) {
    'ONE_ON_ONE' => 'Individual',
    'TRIAL' => 'Trial',
    _ => 'Group Batch',
  };

  /// "Indiranagar, Bengaluru"
  String get venuePlace {
    final a = (venueArea ?? '').trim();
    final show =
        a.isNotEmpty && a.toLowerCase() != venueCity.trim().toLowerCase();
    return [
      if (show) a,
      venueCity,
    ].where((p) => p.trim().isNotEmpty).join(', ');
  }

  /// "Badminton – Beginner Program": the sport in front, unless the programme's own name already says it.
  String get title {
    final s = sport;
    if (s == null || name.toLowerCase().contains(s.toLowerCase())) return name;
    return '$s – $name';
  }
}

String? _clean(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
