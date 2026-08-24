/// Mirrors src/features/memberships/types.ts — same shape.
library;

/// Matches the DB `membership_status` enum exactly (raw status, before the
/// date-derived display status in ../features/memberships/membership_status.dart
/// is applied).
enum MembershipStatus { active, expired, cancelled, pending }

MembershipStatus membershipStatusFromDb(String value) {
  switch (value) {
    case 'expired':
      return MembershipStatus.expired;
    case 'cancelled':
      return MembershipStatus.cancelled;
    case 'pending':
      return MembershipStatus.pending;
    case 'active':
    default:
      return MembershipStatus.active;
  }
}

String membershipStatusToDb(MembershipStatus status) {
  switch (status) {
    case MembershipStatus.expired:
      return 'expired';
    case MembershipStatus.cancelled:
      return 'cancelled';
    case MembershipStatus.pending:
      return 'pending';
    case MembershipStatus.active:
      return 'active';
  }
}

/// The derived, date-aware status shown in the UI — see
/// ../../features/memberships/membership_status.dart for how it's computed
/// from (raw [MembershipStatus], end date, now). Never re-derive this
/// inline in a widget. [noMembership] is returned when the member has never
/// been assigned a plan (a member is a facility customer record independent
/// of any membership).
enum MembershipDisplayStatus { active, expiringSoon, expired, cancelled, noMembership }

class MembershipPlan {
  const MembershipPlan({
    required this.id,
    required this.facilityId,
    required this.name,
    required this.priceInr,
    required this.durationDays,
    required this.features,
    required this.isActive,
    required this.createdAt,
  });

  final String id;
  final String facilityId;
  final String name;
  /// Whole rupees — never minor units. Format directly, do not divide by 100.
  final int priceInr;
  final int durationDays;
  final List<String> features;
  final bool isActive;
  final DateTime createdAt;

  factory MembershipPlan.fromJson(Map<String, dynamic> json) {
    return MembershipPlan(
      id: json['id'] as String,
      facilityId: json['facility_id'] as String,
      name: json['name'] as String,
      priceInr: (json['price_inr'] as num).toInt(),
      durationDays: (json['duration_days'] as num).toInt(),
      features: (json['features'] as List<dynamic>? ?? const []).cast<String>(),
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class MembershipPlanInput {
  const MembershipPlanInput({
    required this.facilityId,
    required this.name,
    required this.priceInr,
    required this.durationDays,
    this.features = const [],
  });

  final String facilityId;
  final String name;
  final int priceInr;
  final int durationDays;
  final List<String> features;
}

class Membership {
  const Membership({
    required this.id,
    required this.facilityId,
    required this.memberId,
    required this.planId,
    required this.planName,
    required this.status,
    required this.startDate,
    required this.endDate,
    required this.autoRenew,
    required this.createdAt,
  });

  final String id;
  final String facilityId;
  final String memberId;
  final String planId;
  final String planName;
  final MembershipStatus status;
  /// Date-only (no time-of-day component).
  final DateTime startDate;
  final DateTime endDate;
  final bool autoRenew;
  final DateTime createdAt;

  /// [planName] is supplied by the caller when the row doesn't carry it
  /// directly (e.g. a plain `memberships` table row joined separately),
  /// mirroring `toMembership(row, planName)` on the web.
  factory Membership.fromJson(Map<String, dynamic> json, {String? planName}) {
    return Membership(
      id: json['id'] as String,
      facilityId: json['facility_id'] as String,
      memberId: json['member_id'] as String,
      planId: json['plan_id'] as String,
      planName: planName ?? (json['plan_name'] as String? ?? ''),
      status: membershipStatusFromDb(json['status'] as String? ?? 'active'),
      startDate: DateTime.parse(json['start_date'] as String),
      endDate: DateTime.parse(json['end_date'] as String),
      autoRenew: json['auto_renew'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

/// One row per member, their most recent membership at this facility left
/// joined in — facility scoping comes from `search_facility_members`, never
/// from `profiles.role`. The membership-related fields are all nullable: a
/// member is a facility customer record that can exist with zero
/// memberships (see supabase/migrations/0013_facility_members.sql).
class FacilityMemberRow {
  const FacilityMemberRow({
    required this.memberId,
    required this.fullName,
    required this.phone,
    this.email,
    this.membershipId,
    this.planId,
    this.planName,
    this.startDate,
    this.endDate,
    this.status,
  });

  final String memberId;
  final String fullName;
  final String phone;
  final String? email;
  final String? membershipId;
  final String? planId;
  final String? planName;
  final DateTime? startDate;
  final DateTime? endDate;
  final MembershipStatus? status;

  FacilityMemberRow copyWith({String? fullName, String? phone, String? email}) {
    return FacilityMemberRow(
      memberId: memberId,
      fullName: fullName ?? this.fullName,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      membershipId: membershipId,
      planId: planId,
      planName: planName,
      startDate: startDate,
      endDate: endDate,
      status: status,
    );
  }

  factory FacilityMemberRow.fromJson(Map<String, dynamic> json) {
    return FacilityMemberRow(
      memberId: json['member_id'] as String,
      fullName: json['full_name'] as String,
      phone: json['phone'] as String,
      email: json['email'] as String?,
      membershipId: json['membership_id'] as String?,
      planId: json['plan_id'] as String?,
      planName: json['plan_name'] as String?,
      startDate: json['start_date'] != null ? DateTime.parse(json['start_date'] as String) : null,
      endDate: json['end_date'] != null ? DateTime.parse(json['end_date'] as String) : null,
      status: json['status'] != null ? membershipStatusFromDb(json['status'] as String) : null,
    );
  }
}

/// A Member is a facility CUSTOMER/PLAYER record — never a GameAll
/// authenticated user. It has no login, no password, and no Supabase Auth
/// account by default. [userId] exists only for a future, explicit "Invite
/// to GameAll" flow that links a member to a real login; normal member
/// creation always leaves it null. Mirrors src/features/members/types.ts.
class Member {
  const Member({
    required this.id,
    required this.facilityId,
    required this.fullName,
    required this.phone,
    this.email,
    this.dateOfBirth,
    this.gender,
    this.notes,
    this.status = 'ACTIVE',
    this.userId,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String facilityId;
  final String fullName;
  final String phone;
  final String? email;
  /// ISO date (YYYY-MM-DD) — no time-of-day component.
  final String? dateOfBirth;
  final String? gender;
  final String? notes;
  /// 'ACTIVE' | 'INACTIVE'.
  final String status;
  final String? userId;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Member.fromJson(Map<String, dynamic> json) {
    return Member(
      id: json['id'] as String,
      facilityId: json['facility_id'] as String,
      fullName: json['full_name'] as String,
      phone: json['phone'] as String,
      email: json['email'] as String?,
      dateOfBirth: json['date_of_birth'] as String?,
      gender: json['gender'] as String?,
      notes: json['notes'] as String?,
      status: json['status'] as String? ?? 'ACTIVE',
      userId: json['user_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}

/// Mirrors `MemberInput` on the web — the create/update payload for a
/// facility customer record. Name and mobile number are the only required
/// fields; a member needs no login and no email verification.
class MemberInput {
  const MemberInput({
    required this.facilityId,
    required this.fullName,
    required this.phone,
    this.email,
    this.dateOfBirth,
    this.gender,
    this.notes,
  });

  final String facilityId;
  final String fullName;
  final String phone;
  final String? email;
  /// ISO date (YYYY-MM-DD) — no time-of-day component.
  final String? dateOfBirth;
  final String? gender;
  final String? notes;
}

/// [startDate] is sent as an ISO date (YYYY-MM-DD) — see
/// `MembershipRepository.createMembership`. [paymentStatus] uses the DB
/// `payment_status` enum values ('created' | 'paid' | 'failed' | 'refunded');
/// the Assign Membership sheet only ever sends 'paid' or 'created'.
class CreateMembershipInput {
  const CreateMembershipInput({
    required this.memberId,
    required this.facilityId,
    required this.planId,
    required this.startDate,
    this.paymentStatus = 'created',
  });

  final String memberId;
  final String facilityId;
  final String planId;
  final DateTime startDate;
  final String paymentStatus;
}

class MemberSportPlayed {
  const MemberSportPlayed({required this.sportId, required this.sportName});

  final String sportId;
  final String sportName;
}

/// Everything on the Member Profile screen — derived live from real
/// bookings, never a maintained counter. Mirrors `get_member_stats`, same
/// shape as `get_guest_stats`.
class MemberStats {
  const MemberStats({
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
  final List<MemberSportPlayed> sports;

  factory MemberStats.fromJson(Map<String, dynamic> json) {
    final sportsJson = (json['sports'] as List<dynamic>? ?? const []);
    return MemberStats(
      totalVisits: (json['total_visits'] as num?)?.toInt() ?? 0,
      totalBookings: (json['total_bookings'] as num?)?.toInt() ?? 0,
      lastVisit: json['last_visit'] != null ? DateTime.parse(json['last_visit'] as String) : null,
      totalAmountMinor: (json['total_amount_minor'] as num?)?.toInt() ?? 0,
      pendingAmountMinor: (json['pending_amount_minor'] as num?)?.toInt() ?? 0,
      sports: sportsJson
          .cast<Map<String, dynamic>>()
          .map((s) => MemberSportPlayed(sportId: s['sportId'] as String, sportName: s['sportName'] as String))
          .toList(),
    );
  }
}