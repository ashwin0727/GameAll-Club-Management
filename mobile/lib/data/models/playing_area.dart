/// Playing-area type label per sport — mirrors
/// features/courts-setup/constants.ts's PLAYING_AREA_LABEL.
String playingAreaLabelFor(String sportCode) {
  switch (sportCode) {
    case 'CRICKET':
    case 'FOOTBALL':
      return 'Turf';
    case 'OTHER':
      return 'Playing Area';
    default:
      return 'Court';
  }
}

/// Mirrors the `courts` table (serves as "playing areas" in the app layer
/// — see supabase/migrations/0002_onboarding_backend.sql for why the table
/// itself wasn't renamed).
class PlayingArea {
  const PlayingArea({
    required this.id,
    required this.facilityId,
    required this.facilitySportId,
    required this.sportId,
    required this.name,
    required this.areaType,
    required this.status,
    required this.bookingEnabled,
    required this.archived,
    required this.displayOrder,
  });

  final String id;
  final String facilityId;
  final String facilitySportId;
  final String sportId;
  final String name;
  final String areaType; // INDOOR | OUTDOOR
  final String status; // ACTIVE | INACTIVE
  final bool bookingEnabled;
  final bool archived;
  final int displayOrder;

  factory PlayingArea.fromJson(Map<String, dynamic> json) {
    return PlayingArea(
      id: json['id'] as String,
      facilityId: json['facility_id'] as String,
      facilitySportId: json['facility_sport_id'] as String,
      sportId: json['sport_id'] as String,
      name: json['name'] as String,
      areaType: json['area_type'] as String? ?? 'INDOOR',
      status: json['status'] as String? ?? 'ACTIVE',
      bookingEnabled: json['booking_enabled'] as bool? ?? true,
      archived: json['archived'] as bool? ?? false,
      displayOrder: json['display_order'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toInsertJson() {
    return {
      'id': id,
      'facility_id': facilityId,
      'facility_sport_id': facilitySportId,
      'sport_id': sportId,
      'name': name,
      'area_type': areaType,
      'status': status,
      'booking_enabled': bookingEnabled,
      'archived': archived,
      'display_order': displayOrder,
    };
  }
}