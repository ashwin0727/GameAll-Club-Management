/// A venue a player can see: only what a visitor needs (see migration 0168, `list_public_venues`).
class Venue {
  const Venue({
    required this.id,
    required this.name,
    required this.city,
    this.state,
    this.area,
    this.logoUrl,
    this.sports = const [],
    this.courtCount = 0,
  });

  factory Venue.fromJson(Map<String, dynamic> json) => Venue(
    id: json['id'] as String,
    name: (json['name'] as String?) ?? 'Venue',
    city: (json['city'] as String?) ?? '',
    state: _clean(json['state'] as String?),
    area: _clean(json['area'] as String?),
    logoUrl: _clean(json['logoUrl'] as String?),
    sports: [
      for (final s in (json['sports'] as List<dynamic>? ?? const []))
        if (s != null) s.toString(),
    ],
    courtCount: (json['courtCount'] as num?)?.toInt() ?? 0,
  );

  final String id;
  final String name;
  final String city;
  final String? state;
  final String? area;
  final String? logoUrl;
  final List<String> sports;
  final int courtCount;

  /// "Indiranagar, Bangalore"
  String get place =>
      [?area, city].where((p) => p.trim().isNotEmpty).join(', ');

  String get initials {
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return '?';
    return (words.length == 1
            ? words.first.substring(0, 1)
            : words.first.substring(0, 1) + words[1].substring(0, 1))
        .toUpperCase();
  }

  static String? _clean(String? v) =>
      (v == null || v.trim().isEmpty) ? null : v.trim();
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
