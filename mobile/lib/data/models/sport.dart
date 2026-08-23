/// Presentation-only lookup (icon/description have no DB column, same as
/// the web app's `presentSport()` in features/sports-setup/constants.ts) —
/// keyed by the sport's stable `code` (uppercased `key`).
const String otherSportCode = 'OTHER';

const Map<String, ({String icon, String description})> _presentation = {
  'BADMINTON': (icon: '🏸', description: 'Indoor racket sport'),
  'PICKLEBALL': (icon: '🏓', description: 'Court-based paddle sport'),
  'CRICKET': (icon: '🏏', description: 'Bat-and-ball team sport'),
  'FOOTBALL': (icon: '⚽', description: 'Outdoor team sport'),
  'TENNIS': (icon: '🎾', description: 'Racket sport on a court'),
  'OTHER': (icon: '➕', description: 'A sport not listed here'),
};
const _defaultPresentation = (icon: '🏅', description: '');

/// The global sport catalog — mirrors `sports` (0001/0002 migrations).
class Sport {
  const Sport({
    required this.id,
    required this.name,
    required this.code,
    required this.icon,
    required this.description,
    required this.isActive,
  });

  final String id;
  final String name;
  final String code;
  final String icon;
  final String description;
  final bool isActive;

  factory Sport.fromJson(Map<String, dynamic> json) {
    final code = (json['key'] as String? ?? '').toUpperCase();
    final presentation = _presentation[code] ?? _defaultPresentation;
    return Sport(
      id: json['id'] as String,
      name: json['name'] as String,
      code: code,
      icon: presentation.icon,
      description: presentation.description,
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}

/// "This facility operates this sport" — mirrors `facility_sports`.
class FacilitySport {
  const FacilitySport({
    required this.id,
    required this.facilityId,
    required this.sportId,
    required this.enabled,
    this.customSportName,
  });

  final String id;
  final String facilityId;
  final String sportId;
  final bool enabled;
  final String? customSportName;

  factory FacilitySport.fromJson(Map<String, dynamic> json) {
    return FacilitySport(
      id: json['id'] as String,
      facilityId: json['facility_id'] as String,
      sportId: json['sport_id'] as String,
      enabled: json['is_active'] as bool? ?? true,
      customSportName: json['custom_sport_name'] as String?,
    );
  }
}