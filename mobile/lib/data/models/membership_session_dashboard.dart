/// Membership Sessions dashboard models (Phase 9) — mirrors
/// src/features/membership-sessions/types.ts.
library;

class MembershipSessionsSummary {
  const MembershipSessionsSummary({
    required this.totalSessions,
    required this.activeSessions,
    required this.todaysSessions,
    required this.guestSlotsReleased,
    required this.avgUtilizationPct,
  });

  final int totalSessions;
  final int activeSessions;
  final int todaysSessions;
  final int guestSlotsReleased;
  final int avgUtilizationPct;

  factory MembershipSessionsSummary.fromJson(Map<String, dynamic> j) => MembershipSessionsSummary(
        totalSessions: (j['totalSessions'] as num?)?.toInt() ?? 0,
        activeSessions: (j['activeSessions'] as num?)?.toInt() ?? 0,
        todaysSessions: (j['todaysSessions'] as num?)?.toInt() ?? 0,
        guestSlotsReleased: (j['guestSlotsReleased'] as num?)?.toInt() ?? 0,
        avgUtilizationPct: (j['avgUtilizationPct'] as num?)?.toInt() ?? 0,
      );
}

enum MembershipSessionStatus { active, paused, full }

MembershipSessionStatus membershipSessionStatusFromDb(String v) {
  switch (v) {
    case 'full':
      return MembershipSessionStatus.full;
    case 'paused':
      return MembershipSessionStatus.paused;
    default:
      return MembershipSessionStatus.active;
  }
}

class MembershipSessionListRow {
  const MembershipSessionListRow({
    required this.batchId,
    required this.name,
    required this.courtId,
    required this.courtName,
    required this.facilitySportId,
    required this.sportName,
    required this.daysOfWeek,
    required this.startTime,
    required this.endTime,
    required this.capacity,
    required this.rosterCount,
    required this.releasedToday,
    required this.guestBookedToday,
    required this.utilizationPct,
    required this.status,
    required this.isActive,
  });

  final String batchId;
  final String name;
  final String courtId;
  final String courtName;
  final String facilitySportId;
  final String sportName;
  final List<int> daysOfWeek;
  final String startTime;
  final String endTime;
  final int capacity;
  final int rosterCount;
  final int releasedToday;
  final int guestBookedToday;
  final int utilizationPct;
  final MembershipSessionStatus status;
  final bool isActive;

  factory MembershipSessionListRow.fromJson(Map<String, dynamic> j) => MembershipSessionListRow(
        batchId: j['batch_id'] as String,
        name: j['name'] as String? ?? 'Session',
        courtId: j['court_id'] as String,
        courtName: j['court_name'] as String? ?? '',
        facilitySportId: j['facility_sport_id'] as String,
        sportName: j['sport_name'] as String? ?? '',
        daysOfWeek: ((j['days_of_week'] as List<dynamic>?) ?? const []).map((d) => (d as num).toInt()).toList(),
        startTime: j['start_time'] as String? ?? '',
        endTime: j['end_time'] as String? ?? '',
        capacity: (j['capacity'] as num?)?.toInt() ?? 0,
        rosterCount: (j['roster_count'] as num?)?.toInt() ?? 0,
        releasedToday: (j['released_today'] as num?)?.toInt() ?? 0,
        guestBookedToday: (j['guest_booked_today'] as num?)?.toInt() ?? 0,
        utilizationPct: (j['utilization_pct'] as num?)?.toInt() ?? 0,
        status: membershipSessionStatusFromDb(j['status'] as String? ?? 'active'),
        isActive: j['is_active'] as bool? ?? true,
      );
}

class MembershipSessionDetail {
  const MembershipSessionDetail({
    required this.batchId,
    required this.facilityId,
    required this.name,
    required this.courtName,
    required this.sportName,
    this.planName,
    required this.daysOfWeek,
    required this.startTime,
    required this.endTime,
    required this.capacity,
    required this.isActive,
    this.createdByName,
    required this.createdAt,
    required this.updatedAt,
    required this.rosterCount,
    required this.guestsBookedToday,
    required this.releasedToday,
    required this.availableToRelease,
    required this.runsToday,
    this.nextOccurrenceDate,
  });

  final String batchId;
  final String facilityId;
  final String name;
  final String courtName;
  final String sportName;
  final String? planName;
  final List<int> daysOfWeek;
  final String startTime;
  final String endTime;
  final int capacity;
  final bool isActive;
  final String? createdByName;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int rosterCount;
  final int guestsBookedToday;
  final int releasedToday;
  final int availableToRelease;
  final bool runsToday;
  final DateTime? nextOccurrenceDate;

  factory MembershipSessionDetail.fromJson(Map<String, dynamic> j) => MembershipSessionDetail(
        batchId: j['batchId'] as String,
        facilityId: j['facilityId'] as String,
        name: j['name'] as String? ?? 'Session',
        courtName: j['courtName'] as String? ?? '',
        sportName: j['sportName'] as String? ?? '',
        planName: j['planName'] as String?,
        daysOfWeek: ((j['daysOfWeek'] as List<dynamic>?) ?? const []).map((d) => (d as num).toInt()).toList(),
        startTime: j['startTime'] as String? ?? '',
        endTime: j['endTime'] as String? ?? '',
        capacity: (j['capacity'] as num?)?.toInt() ?? 0,
        isActive: j['isActive'] as bool? ?? true,
        createdByName: j['createdByName'] as String?,
        createdAt: DateTime.parse(j['createdAt'] as String),
        updatedAt: DateTime.parse(j['updatedAt'] as String),
        rosterCount: (j['rosterCount'] as num?)?.toInt() ?? 0,
        guestsBookedToday: (j['guestsBookedToday'] as num?)?.toInt() ?? 0,
        releasedToday: (j['releasedToday'] as num?)?.toInt() ?? 0,
        availableToRelease: (j['availableToRelease'] as num?)?.toInt() ?? 0,
        runsToday: j['runsToday'] as bool? ?? false,
        nextOccurrenceDate: j['nextOccurrenceDate'] != null ? DateTime.parse(j['nextOccurrenceDate'] as String) : null,
      );
}

class MembershipSessionOccurrence {
  const MembershipSessionOccurrence({
    required this.occurrenceDate,
    required this.isBlocked,
    this.blockReason,
    required this.materialized,
    required this.memberCount,
    required this.guestCount,
    required this.releasedCapacity,
  });

  final DateTime occurrenceDate;
  final bool isBlocked;
  final String? blockReason;
  final bool materialized;
  final int memberCount;
  final int guestCount;
  final int releasedCapacity;

  factory MembershipSessionOccurrence.fromJson(Map<String, dynamic> j) => MembershipSessionOccurrence(
        occurrenceDate: DateTime.parse(j['occurrence_date'] as String),
        isBlocked: j['is_blocked'] as bool? ?? false,
        blockReason: j['block_reason'] as String?,
        materialized: j['materialized'] as bool? ?? false,
        memberCount: (j['member_count'] as num?)?.toInt() ?? 0,
        guestCount: (j['guest_count'] as num?)?.toInt() ?? 0,
        releasedCapacity: (j['released_capacity'] as num?)?.toInt() ?? 0,
      );
}

class MembershipSessionBookingRow {
  const MembershipSessionBookingRow({
    required this.bookingId,
    required this.sessionDate,
    required this.participantType,
    required this.participantName,
    required this.slotSource,
    required this.status,
    this.amountMinor,
    required this.createdAt,
  });

  final String bookingId;
  final DateTime sessionDate;
  final String participantType;
  final String participantName;
  final String slotSource;
  final String status;
  final int? amountMinor;
  final DateTime createdAt;

  factory MembershipSessionBookingRow.fromJson(Map<String, dynamic> j) => MembershipSessionBookingRow(
        bookingId: j['booking_id'] as String,
        sessionDate: DateTime.parse(j['session_date'] as String),
        participantType: j['participant_type'] as String? ?? 'GUEST',
        participantName: j['participant_name'] as String? ?? 'Guest',
        slotSource: j['slot_source'] as String? ?? 'RELEASED',
        status: j['status'] as String? ?? 'CONFIRMED',
        amountMinor: (j['amount_minor'] as num?)?.toInt(),
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}

class MembershipSessionActivity {
  const MembershipSessionActivity({required this.kind, this.actor, required this.detail, required this.at});

  final String kind;
  final String? actor;
  final String detail;
  final DateTime at;

  factory MembershipSessionActivity.fromJson(Map<String, dynamic> j) => MembershipSessionActivity(
        kind: j['kind'] as String? ?? '',
        actor: j['actor'] as String?,
        detail: j['detail'] as String? ?? '',
        at: DateTime.parse(j['at'] as String),
      );
}