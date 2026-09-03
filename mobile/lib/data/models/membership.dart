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

// ═══════════════════════════════════════════════════════════════════════════
// Full Create Membership page (web Phase 4) — a self-contained membership
// with its own name / type / duration / fee / GST / time slot, written via
// the `create_membership_full` RPC. Mirrors src/features/memberships/types.ts.
// ═══════════════════════════════════════════════════════════════════════════

/// Matches the `membership_type` check constraint on `memberships`
/// (0028_membership_creation_form.sql).
enum MembershipType { individual, family, corporate }

String membershipTypeToDb(MembershipType type) {
  switch (type) {
    case MembershipType.individual:
      return 'INDIVIDUAL';
    case MembershipType.family:
      return 'FAMILY';
    case MembershipType.corporate:
      return 'CORPORATE';
  }
}

MembershipType membershipTypeFromDb(String? value) {
  switch ((value ?? '').toUpperCase()) {
    case 'FAMILY':
      return MembershipType.family;
    case 'CORPORATE':
      return MembershipType.corporate;
    default:
      return MembershipType.individual;
  }
}

String membershipTypeLabel(MembershipType type) {
  switch (type) {
    case MembershipType.individual:
      return 'Individual';
    case MembershipType.family:
      return 'Family';
    case MembershipType.corporate:
      return 'Corporate';
  }
}

/// `p_payment_mode` on `create_membership_full` — PAID collects now, PENDING
/// collects later, FREE skips the payment row entirely.
enum MembershipPaymentMode { paid, pending, free }

String membershipPaymentModeToDb(MembershipPaymentMode mode) {
  switch (mode) {
    case MembershipPaymentMode.paid:
      return 'PAID';
    case MembershipPaymentMode.pending:
      return 'PENDING';
    case MembershipPaymentMode.free:
      return 'FREE';
  }
}

/// The full Create Membership payload. [startDate] is sent as an ISO date
/// (YYYY-MM-DD); [timeSlotStart]/[timeSlotEnd] as 'HH:mm' (24h) or null.
class CreateMembershipFullInput {
  const CreateMembershipFullInput({
    required this.facilityId,
    required this.fullName,
    required this.phone,
    this.email,
    this.dateOfBirth,
    this.gender,
    this.address,
    this.name,
    required this.membershipType,
    required this.maxFamilyMembers,
    required this.startDate,
    required this.durationDays,
    this.batchId,
    this.newBatch,
    this.description,
    required this.membershipFeeInr,
    required this.registrationFeeInr,
    required this.gstPercent,
    required this.paymentMode,
    this.paymentMethods = const [],
    this.paymentReference,
    this.recurring = false,
    this.referralMemberId,
    this.discoverySource,
    this.notes,
  });

  final String facilityId;
  final String fullName;
  final String phone;
  final String? email;
  final String? dateOfBirth;
  final String? gender;
  final String? address;
  final String? name;
  final MembershipType membershipType;
  final int maxFamilyMembers;
  final DateTime startDate;
  final int durationDays;

  /// The reserved court slot: an existing `membership_batches` id to join, or
  /// [newBatch] to create one. Mutually exclusive; both null = no slot.
  final String? batchId;

  /// `{courtId, facilitySportId, daysOfWeek, startTime, endTime, capacity}` —
  /// exactly the keys `create_membership_full`'s `p_new_batch` destructures.
  final Map<String, dynamic>? newBatch;
  final String? description;
  final int membershipFeeInr;
  final int registrationFeeInr;
  final double gstPercent;
  final MembershipPaymentMode paymentMode;
  final List<String> paymentMethods;
  final String? paymentReference;
  final bool recurring;
  final String? referralMemberId;
  final String? discoverySource;
  final String? notes;
}

/// Razorpay-hosted UPI AutoPay mandate authorisation — returned by the
/// `create-membership-subscription` Edge Function. [shortUrl] is the page
/// the member opens to approve the recurring mandate.
class MembershipSubscriptionInfo {
  const MembershipSubscriptionInfo({required this.subscriptionId, required this.shortUrl, required this.keyId});

  final String subscriptionId;
  final String? shortUrl;
  final String keyId;

  factory MembershipSubscriptionInfo.fromJson(Map<String, dynamic> json) {
    return MembershipSubscriptionInfo(
      subscriptionId: json['subscriptionId'] as String,
      shortUrl: json['shortUrl'] as String?,
      keyId: json['keyId'] as String? ?? '',
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Memberships list page (web `list_memberships` / `get_membership_page_summary`).
// ─────────────────────────────────────────────────────────────────────────

/// The payment-driven status the list shows — distinct from the raw
/// [MembershipStatus] enum. Mirrors the web `MembershipListStatus`.
enum MembershipListStatus { paymentIncomplete, active, inactive }

MembershipListStatus membershipListStatusFromDb(String value) {
  switch (value) {
    case 'payment_incomplete':
      return MembershipListStatus.paymentIncomplete;
    case 'inactive':
      return MembershipListStatus.inactive;
    case 'active':
    default:
      return MembershipListStatus.active;
  }
}

String? membershipListStatusToDb(MembershipListStatus? value) {
  switch (value) {
    case null:
      return null;
    case MembershipListStatus.paymentIncomplete:
      return 'payment_incomplete';
    case MembershipListStatus.active:
      return 'active';
    case MembershipListStatus.inactive:
      return 'inactive';
  }
}

enum MembershipListSort { oldest, nextPayment, name }

String membershipListSortToDb(MembershipListSort sort) {
  switch (sort) {
    case MembershipListSort.oldest:
      return 'oldest';
    case MembershipListSort.nextPayment:
      return 'next_payment';
    case MembershipListSort.name:
      return 'name';
  }
}

/// The batch/time-slot a membership is enrolled in, when there is one.
/// [batchId] / [facilitySportId] are present on `get_membership_detail`'s slot
/// object (migration 0038) — the Edit form needs them to pre-select the batch.
class MembershipSlot {
  const MembershipSlot({
    required this.name,
    required this.daysOfWeek,
    required this.startTime,
    required this.endTime,
    this.courtName,
    this.batchId,
    this.facilitySportId,
  });

  final String name;
  final List<int> daysOfWeek;
  final String startTime;
  final String endTime;
  final String? courtName;
  final String? batchId;
  final String? facilitySportId;
}

class MembershipListRow {
  const MembershipListRow({
    required this.membershipId,
    required this.memberId,
    required this.memberName,
    required this.memberPhone,
    this.memberEmail,
    this.planId,
    required this.planName,
    required this.monthlyPriceInr,
    required this.status,
    required this.startDate,
    required this.endDate,
    this.slot,
  });

  final String membershipId;
  final String memberId;
  final String memberName;
  final String memberPhone;
  final String? memberEmail;
  final String? planId;
  final String planName;
  final int monthlyPriceInr;
  final MembershipListStatus status;
  final DateTime startDate;

  /// The date the paid period runs out — shown as "Next Payment Date".
  final DateTime endDate;
  final MembershipSlot? slot;

  factory MembershipListRow.fromJson(Map<String, dynamic> json) {
    final batchName = json['batch_name'] as String?;
    return MembershipListRow(
      membershipId: json['membership_id'] as String,
      memberId: json['member_id'] as String,
      memberName: json['member_name'] as String,
      memberPhone: json['member_phone'] as String? ?? '',
      memberEmail: json['member_email'] as String?,
      planId: json['plan_id'] as String?,
      planName: json['plan_name'] as String? ?? 'Membership',
      monthlyPriceInr: (json['monthly_price_inr'] as num?)?.toInt() ?? 0,
      status: membershipListStatusFromDb(json['display_status'] as String? ?? 'active'),
      startDate: DateTime.parse(json['start_date'] as String),
      endDate: DateTime.parse(json['end_date'] as String),
      slot: batchName == null
          ? null
          : MembershipSlot(
              name: batchName,
              daysOfWeek: ((json['batch_days'] as List<dynamic>?) ?? const []).map((d) => (d as num).toInt()).toList(),
              startTime: json['batch_start'] as String? ?? '',
              endTime: json['batch_end'] as String? ?? '',
              courtName: json['batch_court'] as String?,
            ),
    );
  }
}

class MembershipListParams {
  const MembershipListParams({
    this.search,
    this.status,
    this.planId,
    this.sort = MembershipListSort.oldest,
    required this.page,
    this.perPage = 10,
  });

  final String? search;
  final MembershipListStatus? status;
  final String? planId;
  final MembershipListSort sort;
  final int page;
  final int perPage;
}

class MembershipListResult {
  const MembershipListResult({required this.rows, required this.totalCount});

  final List<MembershipListRow> rows;
  final int totalCount;
}

/// The four KPI values on top of the Memberships page — mirrors
/// `get_membership_page_summary` plus the web's percent-change math.
class MembershipPageSummary {
  const MembershipPageSummary({
    required this.totalMembers,
    this.totalMembersChangePct,
    required this.activeMembers,
    required this.activePctOfTotal,
    required this.paymentIncompleteMembers,
    required this.revenueInr,
    this.revenueChangePct,
  });

  final int totalMembers;
  final double? totalMembersChangePct;
  final int activeMembers;
  final double activePctOfTotal;
  final int paymentIncompleteMembers;
  final int revenueInr;
  final double? revenueChangePct;

  factory MembershipPageSummary.fromJson(Map<String, dynamic> json) {
    double? pctChange(num current, num before) => before == 0 ? null : ((current - before) / before) * 100;
    final totalMembers = (json['total_members'] as num?)?.toInt() ?? 0;
    final prev = (json['total_members_prev'] as num?)?.toInt() ?? 0;
    final revenue = (json['revenue_inr'] as num?)?.toInt() ?? 0;
    final revenuePrev = (json['revenue_prev_inr'] as num?)?.toInt() ?? 0;
    final active = (json['active_members'] as num?)?.toInt() ?? 0;
    return MembershipPageSummary(
      totalMembers: totalMembers,
      totalMembersChangePct: pctChange(totalMembers, prev),
      activeMembers: active,
      activePctOfTotal: totalMembers == 0 ? 0 : (active / totalMembers) * 100,
      paymentIncompleteMembers: (json['payment_incomplete_members'] as num?)?.toInt() ?? 0,
      revenueInr: revenue,
      revenueChangePct: pctChange(revenue, revenuePrev),
    );
  }
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
// ─────────────────────────────────────────────────────────────────────────
// Membership Details screen — one `get_membership_detail` jsonb document.
// Mirrors the web `MembershipDetail`.
// ─────────────────────────────────────────────────────────────────────────

class MembershipTimelineEvent {
  const MembershipTimelineEvent({required this.label, required this.actor, required this.at});

  final String label;
  final String actor;
  final DateTime at;

  factory MembershipTimelineEvent.fromJson(Map<String, dynamic> j) => MembershipTimelineEvent(
        label: j['label'] as String,
        actor: j['actor'] as String? ?? '',
        at: DateTime.parse(j['at'] as String),
      );
}

class MembershipDetailMember {
  const MembershipDetailMember({
    required this.id,
    required this.fullName,
    required this.phone,
    this.email,
    this.dateOfBirth,
    this.gender,
    this.address,
    required this.status,
    required this.memberSince,
  });

  final String id;
  final String fullName;
  final String phone;
  final String? email;
  final String? dateOfBirth;
  final String? gender;
  final String? address;
  final String status;
  final DateTime memberSince;

  factory MembershipDetailMember.fromJson(Map<String, dynamic> j) => MembershipDetailMember(
        id: j['id'] as String,
        fullName: j['fullName'] as String,
        phone: j['phone'] as String? ?? '',
        email: j['email'] as String?,
        dateOfBirth: j['dateOfBirth'] as String?,
        gender: j['gender'] as String?,
        address: j['address'] as String?,
        status: j['status'] as String? ?? 'ACTIVE',
        memberSince: DateTime.parse(j['memberSince'] as String),
      );
}

class MembershipDetailMembership {
  const MembershipDetailMembership({
    required this.name,
    required this.membershipType,
    required this.rawStatus,
    required this.startDate,
    required this.endDate,
    this.durationDays,
    required this.maxFamilyMembers,
    this.description,
    required this.membershipFeeInr,
    required this.registrationFeeInr,
    required this.gstPercent,
    required this.totalAmountInr,
    required this.monthlyPriceInr,
    required this.autoRenew,
    required this.createdAt,
  });

  final String name;
  final String membershipType;
  final String rawStatus;
  final DateTime startDate;
  final DateTime endDate;
  final int? durationDays;
  final int maxFamilyMembers;
  final String? description;
  final int membershipFeeInr;
  final int registrationFeeInr;
  final num gstPercent;
  final int totalAmountInr;
  final int monthlyPriceInr;
  final bool autoRenew;
  final DateTime createdAt;

  int get gstAmountInr {
    final v = totalAmountInr - membershipFeeInr - registrationFeeInr;
    return v > 0 ? v : 0;
  }

  factory MembershipDetailMembership.fromJson(Map<String, dynamic> j) => MembershipDetailMembership(
        name: j['name'] as String? ?? 'Membership',
        membershipType: j['membershipType'] as String? ?? 'INDIVIDUAL',
        rawStatus: j['rawStatus'] as String? ?? 'active',
        startDate: DateTime.parse(j['startDate'] as String),
        endDate: DateTime.parse(j['endDate'] as String),
        durationDays: (j['durationDays'] as num?)?.toInt(),
        maxFamilyMembers: (j['maxFamilyMembers'] as num?)?.toInt() ?? 1,
        description: j['description'] as String?,
        membershipFeeInr: (j['membershipFeeInr'] as num?)?.toInt() ?? 0,
        registrationFeeInr: (j['registrationFeeInr'] as num?)?.toInt() ?? 0,
        gstPercent: (j['gstPercent'] as num?) ?? 0,
        totalAmountInr: (j['totalAmountInr'] as num?)?.toInt() ?? 0,
        monthlyPriceInr: (j['monthlyPriceInr'] as num?)?.toInt() ?? 0,
        autoRenew: j['autoRenew'] as bool? ?? false,
        createdAt: DateTime.parse(j['createdAt'] as String),
      );
}

class MembershipDetailPayment {
  const MembershipDetailPayment({
    required this.amountInr,
    required this.status,
    required this.settled,
    this.method,
    this.paidAt,
    required this.createdAt,
    this.transactionId,
  });

  final int amountInr;
  final String status;

  /// A real settlement (gateway charge or an owner "record payment"
  /// confirmation) — `status = 'paid'` alone is not enough.
  final bool settled;
  final String? method;
  final DateTime? paidAt;
  final DateTime createdAt;
  final String? transactionId;

  factory MembershipDetailPayment.fromJson(Map<String, dynamic> j) => MembershipDetailPayment(
        amountInr: (j['amountInr'] as num?)?.toInt() ?? 0,
        status: j['status'] as String? ?? 'created',
        settled: j['settled'] as bool? ?? (j['paidAt'] != null),
        method: j['method'] as String?,
        paidAt: j['paidAt'] != null ? DateTime.parse(j['paidAt'] as String) : null,
        createdAt: DateTime.parse(j['createdAt'] as String),
        transactionId: j['transactionId'] as String?,
      );
}

class MembershipDetail {
  const MembershipDetail({
    required this.membershipId,
    required this.facilityId,
    required this.displayStatus,
    required this.member,
    required this.membership,
    this.payment,
    this.referralName,
    this.referralMemberId,
    this.createdByName,
    this.discoverySource,
    this.paymentReference,
    this.notes,
    this.slot,
    required this.timeline,
  });

  final String membershipId;
  final String facilityId;
  final MembershipListStatus displayStatus;
  final MembershipDetailMember member;
  final MembershipDetailMembership membership;
  final MembershipDetailPayment? payment;
  final String? referralName;
  final String? referralMemberId;
  final String? createdByName;
  final String? discoverySource;
  final String? paymentReference;
  final String? notes;
  final MembershipSlot? slot;
  final List<MembershipTimelineEvent> timeline;

  factory MembershipDetail.fromJson(Map<String, dynamic> j) {
    final slotJson = j['slot'] as Map<String, dynamic>?;
    final paymentJson = j['payment'] as Map<String, dynamic>?;
    return MembershipDetail(
      membershipId: j['membershipId'] as String,
      facilityId: j['facilityId'] as String,
      displayStatus: membershipListStatusFromDb(j['displayStatus'] as String? ?? 'active'),
      member: MembershipDetailMember.fromJson(j['member'] as Map<String, dynamic>),
      membership: MembershipDetailMembership.fromJson(j['membership'] as Map<String, dynamic>),
      payment: paymentJson == null ? null : MembershipDetailPayment.fromJson(paymentJson),
      referralName: j['referralName'] as String?,
      referralMemberId: j['referralMemberId'] as String?,
      createdByName: j['createdByName'] as String?,
      discoverySource: j['discoverySource'] as String?,
      paymentReference: j['paymentReference'] as String?,
      notes: j['notes'] as String?,
      slot: slotJson == null
          ? null
          : MembershipSlot(
              name: 'Time slot',
              daysOfWeek: ((slotJson['daysOfWeek'] as List<dynamic>?) ?? const []).map((d) => (d as num).toInt()).toList(),
              startTime: slotJson['startTime'] as String? ?? '',
              endTime: slotJson['endTime'] as String? ?? '',
              courtName: slotJson['courtName'] as String?,
              batchId: slotJson['batchId'] as String?,
              facilitySportId: slotJson['facilitySportId'] as String?,
            ),
      timeline: ((j['timeline'] as List<dynamic>?) ?? const [])
          .map((e) => MembershipTimelineEvent.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// One session batch a new member can be assigned to — a row of
/// `list_assignable_batches` (migration 0027). [spare] is `capacity -
/// enrolledCount` floored at 0; the picker disables a batch at 0 spare unless
/// it is the member's current one (edit mode). Mirrors `AssignableBatch` in
/// src/features/memberships/types.ts.
class AssignableBatch {
  const AssignableBatch({
    required this.batchId,
    required this.name,
    required this.planId,
    required this.courtId,
    required this.courtName,
    required this.facilitySportId,
    required this.sportName,
    required this.daysOfWeek,
    required this.startTime,
    required this.endTime,
    required this.capacity,
    required this.enrolledCount,
    required this.spare,
  });

  final String batchId;
  final String name;
  final String? planId;
  final String courtId;
  final String courtName;
  final String facilitySportId;
  final String sportName;
  final List<int> daysOfWeek;
  final String startTime;
  final String endTime;
  final int capacity;
  final int enrolledCount;
  final int spare;

  factory AssignableBatch.fromJson(Map<String, dynamic> json) {
    return AssignableBatch(
      batchId: json['batch_id'] as String,
      name: json['name'] as String? ?? 'Batch',
      planId: json['plan_id'] as String?,
      courtId: json['court_id'] as String,
      courtName: json['court_name'] as String? ?? '',
      facilitySportId: json['facility_sport_id'] as String,
      sportName: json['sport_name'] as String? ?? '',
      daysOfWeek: ((json['days_of_week'] as List<dynamic>?) ?? const [])
          .map((d) => (d as num).toInt())
          .toList(),
      startTime: json['start_time'] as String? ?? '',
      endTime: json['end_time'] as String? ?? '',
      capacity: (json['capacity'] as num?)?.toInt() ?? 0,
      enrolledCount: (json['enrolled_count'] as num?)?.toInt() ?? 0,
      spare: (json['spare'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Bucket granularity for `get_membership_revenue_timeseries` (migration 0026).
enum MembershipRevenueGranularity {
  day,
  month,
  year;

  String toJson() => name;
}

/// One bucket of membership revenue received. [amountInr] is whole rupees (the
/// RPC sums `payments.amount_inr` directly), not minor units. Mirrors
/// `MembershipRevenuePoint` in src/features/memberships/types.ts.
class MembershipRevenuePoint {
  const MembershipRevenuePoint({
    required this.bucket,
    required this.amountInr,
    required this.paymentCount,
  });

  /// `yyyy-MM-dd` bucket start (Postgres `date`).
  final String bucket;
  final int amountInr;
  final int paymentCount;

  factory MembershipRevenuePoint.fromJson(Map<String, dynamic> json) {
    return MembershipRevenuePoint(
      bucket: json['bucket'] as String,
      amountInr: (json['amount_inr'] as num).toInt(),
      paymentCount: (json['payment_count'] as num).toInt(),
    );
  }
}
