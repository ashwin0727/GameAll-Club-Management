/// Mirrors src/features/guests/types.ts — same shape.
enum GuestStatus { active, inactive }

GuestStatus _statusFromDb(String value) => value == 'INACTIVE' ? GuestStatus.inactive : GuestStatus.active;
String guestStatusToDb(GuestStatus status) => status == GuestStatus.inactive ? 'INACTIVE' : 'ACTIVE';

class GuestPlayer {
  const GuestPlayer({
    required this.id,
    required this.facilityId,
    required this.name,
    this.phone,
    this.email,
    this.notes,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String facilityId;
  final String name;
  final String? phone;
  final String? email;
  final String? notes;
  final GuestStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory GuestPlayer.fromJson(Map<String, dynamic> json) {
    return GuestPlayer(
      id: json['id'] as String,
      facilityId: json['facility_id'] as String,
      name: json['name'] as String,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      notes: json['notes'] as String?,
      status: _statusFromDb(json['status'] as String? ?? 'ACTIVE'),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}

class GuestInput {
  const GuestInput({required this.facilityId, required this.name, this.phone, this.email, this.notes});

  final String facilityId;
  final String name;
  final String? phone;
  final String? email;
  final String? notes;
}

class GuestSportPlayed {
  const GuestSportPlayed({required this.sportId, required this.sportName});

  final String sportId;
  final String sportName;
}

/// Everything on the Guest Profile screen — derived live from real
/// bookings, never a maintained counter.
class GuestStats {
  const GuestStats({
    required this.totalVisits,
    required this.totalBookings,
    this.lastVisit,
    required this.totalAmountMinor,
    required this.pendingAmountMinor,
    required this.sports,
  });

  final int totalVisits;
  final int totalBookings;
  final DateTime? lastVisit;
  final int totalAmountMinor;
  final int pendingAmountMinor;
  final List<GuestSportPlayed> sports;

  factory GuestStats.fromJson(Map<String, dynamic> json) {
    final sportsJson = (json['sports'] as List<dynamic>? ?? []);
    return GuestStats(
      totalVisits: (json['total_visits'] as num?)?.toInt() ?? 0,
      totalBookings: (json['total_bookings'] as num?)?.toInt() ?? 0,
      lastVisit: json['last_visit'] != null ? DateTime.parse(json['last_visit'] as String) : null,
      totalAmountMinor: (json['total_amount_minor'] as num?)?.toInt() ?? 0,
      pendingAmountMinor: (json['pending_amount_minor'] as num?)?.toInt() ?? 0,
      sports: sportsJson
          .cast<Map<String, dynamic>>()
          .map((s) => GuestSportPlayed(sportId: s['sportId'] as String, sportName: s['sportName'] as String))
          .toList(),
    );
  }
}