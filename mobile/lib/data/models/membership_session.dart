/// Mirrors src/features/membership-sessions/types.ts — same shape. See
/// supabase/migrations/0014_membership_sessions.sql for the authoritative
/// backend contract this ports.
library;

/// The recurring template: which court, which sport, which days of week,
/// what time window, how many players (capacity). One row per batch — the
/// actual calendar occurrences are [MembershipSessionSlot]/`membership_sessions`.
class MembershipBatch {
  const MembershipBatch({
    required this.id,
    required this.facilityId,
    required this.planId,
    required this.facilitySportId,
    required this.courtId,
    required this.name,
    required this.daysOfWeek,
    required this.startTime,
    required this.endTime,
    required this.capacity,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String facilityId;
  final String planId;
  final String facilitySportId;
  final String courtId;
  final String name;

  /// 0=Sunday..6=Saturday, matching `extract(dow from timestamp)`.
  final List<int> daysOfWeek;

  /// "HH:MM:SS" (or "HH:MM"), as stored.
  final String startTime;
  final String endTime;
  final int capacity;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory MembershipBatch.fromJson(Map<String, dynamic> json) {
    return MembershipBatch(
      id: json['id'] as String,
      facilityId: json['facility_id'] as String,
      planId: json['plan_id'] as String,
      facilitySportId: json['facility_sport_id'] as String,
      courtId: json['court_id'] as String,
      name: json['name'] as String,
      daysOfWeek: (json['days_of_week'] as List<dynamic>? ?? const []).map((d) => (d as num).toInt()).toList(),
      startTime: json['start_time'] as String,
      endTime: json['end_time'] as String,
      capacity: (json['capacity'] as num).toInt(),
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}

class MembershipBatchInput {
  const MembershipBatchInput({
    required this.facilityId,
    required this.planId,
    required this.facilitySportId,
    required this.courtId,
    required this.name,
    required this.daysOfWeek,
    required this.startTime,
    required this.endTime,
    required this.capacity,
  });

  final String facilityId;
  final String planId;
  final String facilitySportId;
  final String courtId;
  final String name;
  final List<int> daysOfWeek;
  final String startTime;
  final String endTime;
  final int capacity;
}

/// Which member is eligible to book a batch's sessions — assignment, not
/// attendance.
class MembershipBatchMember {
  const MembershipBatchMember({
    required this.id,
    required this.batchId,
    required this.memberId,
    this.membershipId,
    required this.createdAt,
  });

  final String id;
  final String batchId;
  final String memberId;
  final String? membershipId;
  final DateTime createdAt;

  factory MembershipBatchMember.fromJson(Map<String, dynamic> json) {
    return MembershipBatchMember(
      id: json['id'] as String,
      batchId: json['batch_id'] as String,
      memberId: json['member_id'] as String,
      membershipId: json['membership_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

/// One row in the Owner Availability View — a batch's occurrence on a
/// specific date, whether or not it has been materialized into an actual
/// `membership_sessions` row yet ([sessionId] is null until the first
/// booking/release/restore against that date).
class MembershipSessionSlot {
  const MembershipSessionSlot({
    required this.batchId,
    this.sessionId,
    required this.batchName,
    required this.courtId,
    required this.courtName,
    required this.facilitySportId,
    required this.sportName,
    required this.sessionDate,
    required this.startTime,
    required this.endTime,
    required this.capacity,
    required this.releasedCapacity,
    required this.memberBookedCount,
    required this.guestBookedCount,
  });

  final String batchId;
  final String? sessionId;
  final String batchName;
  final String courtId;
  final String courtName;
  final String facilitySportId;
  final String sportName;
  /// ISO date (YYYY-MM-DD).
  final String sessionDate;
  final String startTime;
  final String endTime;
  final int capacity;
  final int releasedCapacity;
  final int memberBookedCount;
  final int guestBookedCount;

  /// [row] is one row from `list_membership_sessions_for_date`; [sessionDate]
  /// is passed separately because the RPC echoes back the queried date, not
  /// necessarily typed as a string by the client library.
  factory MembershipSessionSlot.fromJson(Map<String, dynamic> row) {
    return MembershipSessionSlot(
      batchId: row['batch_id'] as String,
      sessionId: row['session_id'] as String?,
      batchName: row['batch_name'] as String,
      courtId: row['court_id'] as String,
      courtName: row['court_name'] as String,
      facilitySportId: row['facility_sport_id'] as String,
      sportName: row['sport_name'] as String,
      sessionDate: row['session_date'] as String,
      startTime: row['start_time'] as String,
      endTime: row['end_time'] as String,
      capacity: (row['capacity'] as num).toInt(),
      releasedCapacity: (row['released_capacity'] as num).toInt(),
      memberBookedCount: (row['member_booked_count'] as num).toInt(),
      guestBookedCount: (row['guest_booked_count'] as num).toInt(),
    );
  }
}

/// Every count the capacity UI needs, derived live — never a maintained
/// counter. See ../../features/membership_sessions/capacity.dart for the
/// single source of truth that computes [unusedCapacity]/[guestAvailableCapacity].
class MembershipSessionCapacity {
  const MembershipSessionCapacity({
    required this.capacity,
    required this.releasedCapacity,
    required this.memberBookedCount,
    required this.guestBookedCount,
    required this.unusedCapacity,
    required this.guestAvailableCapacity,
  });

  final int capacity;
  final int releasedCapacity;
  final int memberBookedCount;
  final int guestBookedCount;
  final int unusedCapacity;
  final int guestAvailableCapacity;

  factory MembershipSessionCapacity.fromJson(Map<String, dynamic> json) {
    return MembershipSessionCapacity(
      capacity: (json['capacity'] as num).toInt(),
      releasedCapacity: (json['released_capacity'] as num).toInt(),
      memberBookedCount: (json['member_booked_count'] as num).toInt(),
      guestBookedCount: (json['guest_booked_count'] as num).toInt(),
      unusedCapacity: (json['unused_capacity'] as num).toInt(),
      guestAvailableCapacity: (json['guest_available_capacity'] as num).toInt(),
    );
  }
}

class MembershipSessionBooking {
  const MembershipSessionBooking({
    required this.id,
    required this.sessionId,
    required this.facilityId,
    required this.participantType,
    this.memberId,
    this.guestPlayerId,
    required this.status,
    required this.slotSource,
    this.amountMinor,
    required this.currency,
    required this.createdBy,
    required this.createdAt,
  });

  final String id;
  final String sessionId;
  final String facilityId;
  /// 'MEMBER' | 'GUEST'.
  final String participantType;
  final String? memberId;
  final String? guestPlayerId;
  /// 'CONFIRMED' | 'CANCELLED'.
  final String status;
  /// 'MEMBERSHIP' | 'RELEASED'.
  final String slotSource;
  final int? amountMinor;
  final String currency;
  final String createdBy;
  final DateTime createdAt;

  factory MembershipSessionBooking.fromJson(Map<String, dynamic> json) {
    return MembershipSessionBooking(
      id: json['id'] as String,
      sessionId: json['session_id'] as String,
      facilityId: json['facility_id'] as String,
      participantType: json['participant_type'] as String,
      memberId: json['member_id'] as String?,
      guestPlayerId: json['guest_player_id'] as String?,
      status: json['status'] as String,
      slotSource: json['slot_source'] as String,
      amountMinor: (json['amount_minor'] as num?)?.toInt(),
      currency: json['currency'] as String? ?? 'INR',
      createdBy: json['created_by'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}