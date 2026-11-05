/// Which list of venues a page shows: every bookable venue, only those that have created membership plans, or only those that have
/// created coaching programmes (see migration 0171, `list_public_venue_cards`).
enum VenueKind {
  venues('venues'),
  memberships('memberships'),
  coaching('coaching');

  const VenueKind(this.wire);

  /// The value the database function expects.
  final String wire;
}

/// Whether a venue is under a roof or in the open (the owner chooses one when they set the venue up).
enum VenueType { indoor, outdoor }

/// The five things a venue says it offers. Each is simply on or off.
class Amenities {
  const Amenities({this.parking = false, this.changingRooms = false, this.toilets = false, this.cafeteria = false, this.equipmentRental = false});

  factory Amenities.fromJson(Object? raw) {
    final m = raw is Map ? raw.cast<String, dynamic>() : const <String, dynamic>{};
    return Amenities(
      parking: m['parking'] == true,
      changingRooms: m['changingRooms'] == true,
      toilets: m['toilets'] == true,
      cafeteria: m['cafeteria'] == true,
      equipmentRental: m['equipmentRental'] == true,
    );
  }

  final bool parking;
  final bool changingRooms;
  final bool toilets;
  final bool cafeteria;
  final bool equipmentRental;

  /// The labels of the ones that are on, in a fixed order: "Free Parking", "Changing Rooms"...
  List<String> get labels => [
        if (parking) 'Free Parking',
        if (changingRooms) 'Changing Rooms',
        if (toilets) 'Toilets / Rest Room',
        if (cafeteria) 'Cafeteria',
        if (equipmentRental) 'Equipment Rental',
      ];
}

/// A venue a player can see: only what a visitor needs.
class Venue {
  const Venue({
    required this.id,
    required this.name,
    required this.city,
    this.state,
    this.area,
    this.logoUrl,
    this.heroImageUrl,
    this.sports = const [],
    this.surfaces = const [],
    this.venueType,
    this.amenities = const Amenities(),
    this.photos = const [],
    this.courtCount = 0,
    this.minCourtPriceInr,
    this.planNames = const [],
    this.planCount = 0,
    this.minPlanPriceInr,
    this.programNames = const [],
    this.programCount = 0,
    this.minProgramPriceInr,
  });

  factory Venue.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> group(String key) => json[key] is Map ? (json[key] as Map).cast<String, dynamic>() : const {};
    List<String> names(Object? raw) => [for (final s in (raw as List<dynamic>? ?? const [])) if (s != null) s.toString()];
    final memberships = group('memberships');
    final coaching = group('coaching');
    return Venue(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? 'Venue',
      city: (json['city'] as String?) ?? '',
      state: _clean(json['state'] as String?),
      area: _clean(json['area'] as String?),
      logoUrl: _clean(json['logoUrl'] as String?),
      heroImageUrl: _clean(json['heroImageUrl'] as String?),
      sports: names(json['sports']),
      surfaces: names(json['surfaces']),
      venueType: switch (json['venueType']) {
        'INDOOR' => VenueType.indoor,
        'OUTDOOR' => VenueType.outdoor,
        _ => null,
      },
      amenities: Amenities.fromJson(json['amenities']),
      photos: names(json['photos']),
      courtCount: (json['courtCount'] as num?)?.toInt() ?? 0,
      minCourtPriceInr: _price(json['minCourtPriceInr']),
      planNames: names(memberships['names']),
      planCount: (memberships['count'] as num?)?.toInt() ?? 0,
      minPlanPriceInr: _price(memberships['minPriceInr']),
      programNames: names(coaching['names']),
      programCount: (coaching['count'] as num?)?.toInt() ?? 0,
      minProgramPriceInr: _price(coaching['minPriceInr']),
    );
  }

  final String id;
  final String name;
  final String city;
  final String? state;
  final String? area;
  final String? logoUrl;

  /// The venue's own picture (the card's photo); null when the owner has not added one.
  final String? heroImageUrl;
  final List<String> sports;

  /// The surfaces of its courts, lower-cased ("turf", "wooden"...).
  final List<String> surfaces;

  /// Indoor or outdoor; null for a venue that was set up before the owner was asked.
  final VenueType? venueType;
  final Amenities amenities;

  /// Every photo the admin has approved, cover first (empty when none yet).
  final List<String> photos;
  final int courtCount;

  /// The cheapest court, per hour, in rupees.
  final int? minCourtPriceInr;

  final List<String> planNames;
  final int planCount;
  final int? minPlanPriceInr;

  final List<String> programNames;
  final int programCount;
  final int? minProgramPriceInr;

  /// True when any court is on turf (or grass).
  bool get hasTurf => surfaces.any((s) => s.contains('turf') || s.contains('grass'));

  /// "Indiranagar, Bangalore"
  String get place {
    // "Chennai, Chennai" is just "Chennai": the area is dropped when it repeats the city
    final a = (area ?? '').trim();
    final showArea = a.isNotEmpty && a.toLowerCase() != city.trim().toLowerCase();
    return [if (showArea) a, city].where((p) => p.trim().isNotEmpty).join(', ');
  }

  String get initials {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    return (words.length == 1 ? words.first.substring(0, 1) : words.first.substring(0, 1) + words[1].substring(0, 1)).toUpperCase();
  }

  /// The price a card for [kind] shows (rupees), or null when there is none.
  int? priceFor(VenueKind kind) => switch (kind) {
        VenueKind.venues => minCourtPriceInr,
        VenueKind.memberships => minPlanPriceInr,
        VenueKind.coaching => minProgramPriceInr,
      };

  /// The chips a card for [kind] shows: sports, plan names or programme names.
  List<String> chipsFor(VenueKind kind) => switch (kind) {
        VenueKind.venues => sports,
        VenueKind.memberships => planNames,
        VenueKind.coaching => programNames,
      };

  /// A price in rupees, or null when it is missing or 0 (a rate that was never set is not "free").
  static int? _price(Object? v) {
    final n = (v as num?)?.toInt();
    return (n == null || n <= 0) ? null : n;
  }

  static String? _clean(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
}

/// The two halves of a picked location such as "Bangalore, Karnataka".
({String city, String? state}) splitLocation(String label) {
  final parts = label.split(',');
  final city = parts.first.trim();
  final state = parts.length > 1 ? parts.sublist(1).join(',').trim() : null;
  return (city: city, state: (state == null || state.isEmpty) ? null : state);
}

/// Just the city of a picked location, for sentences ("No venues in Bangalore yet").
String cityOf(String label) => splitLocation(label).city;

/// "₹1,500", "₹1,50,000": rupees with Indian digit grouping.
String rupees(int amount) {
  final digits = amount.abs().toString();
  String grouped;
  if (digits.length <= 3) {
    grouped = digits;
  } else {
    final last3 = digits.substring(digits.length - 3);
    var rest = digits.substring(0, digits.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    grouped = '${parts.join(',')},$last3';
  }
  return '${amount < 0 ? '-' : ''}₹$grouped';
}
