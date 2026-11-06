import '../../../core/widgets/sport_icon.dart';
import 'venue.dart';

/// Everything the venue page shows (`get_public_venue`, migration 0174).
class VenueDetail {
  const VenueDetail({
    required this.id,
    required this.name,
    required this.city,
    this.area,
    this.address,
    this.phone,
    this.description,
    this.logoUrl,
    this.photos = const [],
    this.venueType,
    this.amenities = const Amenities(),
    this.locationVerified = false,
    this.locationUrl,
    this.courtCount = 0,
    this.minCourtPriceInr,
    this.sports = const [],
    this.courts = const [],
    this.opens,
    this.closes,
    this.open24h = false,
    this.plans = const [],
    this.programs = const [],
  });

  factory VenueDetail.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> map(Object? v) =>
        v is Map ? v.cast<String, dynamic>() : const {};
    List<Map<String, dynamic>> list(Object? v) => [
      for (final e in (v as List<dynamic>? ?? const [])) map(e),
    ];
    String? clean(Object? v) {
      final s = (v as String?)?.trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    final hours = map(json['hours']);
    final photos = [
      for (final p in (json['photos'] as List<dynamic>? ?? const []))
        if (p != null) p.toString(),
    ];
    final hero = clean(json['heroImageUrl']);
    return VenueDetail(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? 'Venue',
      city: (json['city'] as String?) ?? '',
      area: clean(json['area']),
      address: clean(json['address']),
      phone: clean(json['phone']),
      description: clean(json['description']),
      logoUrl: clean(json['logoUrl']),
      // approved photos; a venue with none yet falls back to its own hero picture
      photos: photos.isNotEmpty ? photos : [?hero],
      venueType: switch (json['venueType']) {
        'INDOOR' => VenueType.indoor,
        'OUTDOOR' => VenueType.outdoor,
        _ => null,
      },
      amenities: Amenities.fromJson(json['amenities']),
      locationVerified: json['locationVerified'] == true,
      locationUrl: clean(json['locationUrl']),
      courtCount: (json['courtCount'] as num?)?.toInt() ?? 0,
      minCourtPriceInr: () {
        final n = (json['minCourtPriceInr'] as num?)?.toInt();
        return (n == null || n <= 0) ? null : n;
      }(),
      sports: [
        for (final s in list(json['sports']))
          VenueSport(
            id: s['facilitySportId'] as String,
            name: (s['name'] as String?) ?? '',
          ),
      ],
      courts: [
        for (final c in list(json['courts']))
          VenueCourt(
            id: c['id'] as String,
            name: (c['name'] as String?) ?? '',
            sportId: c['facilitySportId'] as String?,
          ),
      ],
      opens: clean(hours['opens']),
      closes: clean(hours['closes']),
      open24h: hours['open24h'] == true,
      plans: [
        for (final p in list(map(json['memberships'])['plans']))
          VenuePlan(
            name: (p['name'] as String?) ?? '',
            priceInr: (p['priceInr'] as num?)?.toInt() ?? 0,
            durationDays: (p['durationDays'] as num?)?.toInt() ?? 30,
          ),
      ],
      programs: [
        for (final p in list(map(json['coaching'])['programs']))
          VenueProgram(
            name: (p['name'] as String?) ?? '',
            level: clean(p['level']),
            priceInr: (p['priceInr'] as num?)?.toInt(),
          ),
      ],
    );
  }

  final String id;
  final String name;
  final String city;
  final String? area;
  final String? address;
  final String? phone;
  final String? description;
  final String? logoUrl;

  /// Approved photos, cover first (or the venue's own hero picture when none is approved yet).
  final List<String> photos;
  final VenueType? venueType;
  final Amenities amenities;

  /// True once GameAll's admin has verified the venue's Google Maps location: the "Verified Venue" badge.
  final bool locationVerified;
  final String? locationUrl;
  final int courtCount;
  final int? minCourtPriceInr;
  final List<VenueSport> sports;
  final List<VenueCourt> courts;
  final String? opens;
  final String? closes;
  final bool open24h;
  final List<VenuePlan> plans;
  final List<VenueProgram> programs;

  /// "Iyyapanthangal, Chennai"
  String get place {
    final a = (area ?? '').trim();
    final show = a.isNotEmpty && a.toLowerCase() != city.trim().toLowerCase();
    return [if (show) a, city].where((p) => p.trim().isNotEmpty).join(', ');
  }

  /// "6:00 AM - 11:00 PM", "Open 24 hours", or null when the owner has not set hours.
  String? get hoursLabel {
    if (open24h && opens == null) return 'Open 24 hours';
    if (opens == null || closes == null) return null;
    return '${_clock12(opens!)} - ${_clock12(closes!)}';
  }

  /// "6 AM - 11 PM": the short form for a narrow tile.
  String? get hoursShort {
    if (open24h && opens == null) return '24 hours';
    if (opens == null || closes == null) return null;
    return '${_clock12(opens!, short: true)} - ${_clock12(closes!, short: true)}';
  }

  /// How many people can play at once, added up over the courts: 8 on a badminton, tennis or pickleball court (or any sport not listed
  /// below) and 15 on a cricket or football one.
  int get playerCapacity {
    final sportNames = {for (final s in sports) s.id: s.name};
    var total = 0;
    for (final court in courts) {
      final kind = sportKindOf(sportNames[court.sportId]);
      total += (kind == SportKind.cricket || kind == SportKind.football)
          ? 15
          : 8;
    }
    return total;
  }

  /// "50+ Players": the capacity rounded down to the ten below it (43 -> 40+, 39 -> 30+, 55 -> 50+), and never under 10+ (one badminton
  /// court holds 8 and still reads "10+"). Null when the venue has no courts open for booking.
  String? get playersLabel {
    final capacity = playerCapacity;
    if (capacity <= 0) return null;
    final rounded = (capacity ~/ 10) * 10;
    return '${rounded < 10 ? 10 : rounded}+ Players';
  }

  VenuePlan? get cheapestPlan => plans.isEmpty
      ? null
      : (plans.toList()..sort((a, b) => a.priceInr.compareTo(b.priceInr)))
            .first;

  int? get cheapestProgramPrice {
    final prices = [
      for (final p in programs)
        if (p.priceInr != null) p.priceInr!,
    ];
    return prices.isEmpty ? null : (prices..sort()).first;
  }

  bool get hasMemberships => plans.isNotEmpty;
  bool get hasCoaching => programs.isNotEmpty;
}

class VenueSport {
  const VenueSport({required this.id, required this.name});
  final String id;
  final String name;
}

class VenueCourt {
  const VenueCourt({required this.id, required this.name, this.sportId});
  final String id;
  final String name;
  final String? sportId;
}

class VenuePlan {
  const VenuePlan({
    required this.name,
    required this.priceInr,
    required this.durationDays,
  });
  final String name;
  final int priceInr;
  final int durationDays;

  /// "month" for a plan of about a month, "year", "week" or "N days".
  String get period {
    if (durationDays >= 28 && durationDays <= 31) return 'month';
    if (durationDays >= 360 && durationDays <= 370) return 'year';
    if (durationDays == 7) return 'week';
    if (durationDays == 1) return 'day';
    if (durationDays % 30 == 0) return '${durationDays ~/ 30} months';
    return '$durationDays days';
  }
}

class VenueProgram {
  const VenueProgram({required this.name, this.level, this.priceInr});
  final String name;
  final String? level;
  final int? priceInr;
}

/// One court's hourly slots on a day (`get_public_court_availability`).
class CourtSlots {
  const CourtSlots({
    required this.courtId,
    required this.courtName,
    required this.slots,
  });

  factory CourtSlots.fromJson(Map<String, dynamic> json) => CourtSlots(
    courtId: json['courtId'] as String,
    courtName: (json['courtName'] as String?) ?? '',
    slots: [
      for (final s in (json['slots'] as List<dynamic>? ?? const []))
        CourtSlot(
          start: DateTime.parse((s as Map)['startTime'] as String).toLocal(),
          end: DateTime.parse(s['endTime'] as String).toLocal(),
          available: s['available'] == true,
          priceMinor: (s['priceMinor'] as num?)?.toInt(),
        ),
    ],
  );

  final String courtId;
  final String courtName;
  final List<CourtSlot> slots;
}

class CourtSlot {
  const CourtSlot({
    required this.start,
    required this.end,
    required this.available,
    this.priceMinor,
  });
  final DateTime start;
  final DateTime end;
  final bool available;

  /// The price of the hour in paise (null when the venue has not set one).
  final int? priceMinor;

  @override
  bool operator ==(Object other) =>
      other is CourtSlot && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// What the availability call is asked: a venue, one of its sports and a day.
class AvailabilityQuery {
  const AvailabilityQuery(this.venueId, this.sportId, this.day);
  final String venueId;
  final String sportId;
  final DateTime day;

  String get dayKey =>
      '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is AvailabilityQuery &&
      other.venueId == venueId &&
      other.sportId == sportId &&
      other.dayKey == dayKey;

  @override
  int get hashCode => Object.hash(venueId, sportId, dayKey);
}

String _clock12(String hhmm, {bool short = false}) {
  final parts = hhmm.split(':');
  final h = int.tryParse(parts[0]) ?? 0;
  final m = parts.length > 1 ? parts[1] : '00';
  final hour = h % 12 == 0 ? 12 : h % 12;
  final suffix = h < 12 ? 'AM' : 'PM';
  return short && m == '00' ? '$hour $suffix' : '$hour:$m $suffix';
}
