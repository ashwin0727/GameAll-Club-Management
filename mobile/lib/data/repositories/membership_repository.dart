import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/errors/app_exception.dart';
import '../models/booking.dart';
import '../models/membership.dart';

String _dateOnly(DateTime d) {
  final year = d.year.toString().padLeft(4, '0');
  final month = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

/// Thrown when the facility already has a member with this phone number —
/// carries the existing id so the caller can offer "View Existing Member"
/// instead of a dead-end error. Mirrors the web
/// `MemberAlreadyExistsError extends ServiceError`.
class MemberAlreadyExistsException implements Exception {
  MemberAlreadyExistsException(this.existingMemberId);

  final String existingMemberId;
}

/// Mirrors src/services/memberships/supabase-membership.service.ts — same
/// `search_facility_members`/`create_member`/`update_member`/`search_members`/
/// `create_membership`/`cancel_membership`/`get_member_stats` RPCs, so a
/// member/membership created/updated on either client is immediately
/// visible on both. A member is a facility CUSTOMER/PLAYER record — no
/// login, no password, no Supabase Auth account — so every write here goes
/// directly against `members` via RLS (`members_write_managers`), exactly
/// like `GuestRepository` already does for guest players. Never routes
/// through Supabase Auth or an HTTP API.
class MembershipRepository {
  MembershipRepository(this._client);

  final SupabaseClient _client;

  /// One row per member, their most recent membership at this facility.
  /// Facility scoping comes from the memberships relationship inside the
  /// RPC, never from `profiles.role`.
  Future<List<FacilityMemberRow>> searchFacilityMembers(
    String facilityId, {
    String? query,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final rows = await _client.rpc(
        'search_facility_members',
        params: {
          'p_facility_id': facilityId,
          'p_query': query?.trim().isNotEmpty == true ? query!.trim() : null,
          'p_limit': limit,
          'p_offset': offset,
        },
      );
      return (rows as List<dynamic>).cast<Map<String, dynamic>>().map(FacilityMemberRow.fromJson).toList();
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<Member?> getMember(String memberId) async {
    try {
      final row = await _client.from('members').select().eq('id', memberId).maybeSingle();
      return row == null ? null : Member.fromJson(row);
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// The single write path for adding a new facility customer record — never
  /// a Supabase Auth account. Pre-checks by (facility, phone), matching the
  /// web service's `createMember`, so a duplicate surfaces as
  /// [MemberAlreadyExistsException] with the existing member's id instead of
  /// a bare unique-violation the UI can't act on.
  Future<Member> createMember(MemberInput input) async {
    final phone = input.phone.trim();
    try {
      final existing = await _client
          .from('members')
          .select('id')
          .eq('facility_id', input.facilityId)
          .eq('phone', phone)
          .maybeSingle();
      if (existing != null) {
        throw MemberAlreadyExistsException(existing['id'] as String);
      }

      final row = await _client.rpc(
        'create_member',
        params: {
          'p_facility_id': input.facilityId,
          'p_full_name': input.fullName,
          'p_phone': phone,
          'p_email': input.email,
          'p_date_of_birth': input.dateOfBirth,
          'p_gender': input.gender,
          'p_notes': input.notes,
        },
      );
      return Member.fromJson(row as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e, duplicate: AppErrorCode.memberAlreadyExists, invalid: AppErrorCode.invalidMember);
    }
  }

  /// Updates a member's facility customer record. Any field left null keeps
  /// its current value — mirrors the web service's PATCH-merge semantics by
  /// fetching the existing row first, matching `update_member`'s signature
  /// (which requires every field, unlike `create_member`'s optional ones).
  Future<Member> updateMember(
    String memberId, {
    String? fullName,
    String? phone,
    String? email,
    String? dateOfBirth,
    String? gender,
    String? notes,
    String? status,
  }) async {
    try {
      final existing = await getMember(memberId);
      if (existing == null) throw AppException(AppErrorCode.memberNotFound);

      final row = await _client.rpc(
        'update_member',
        params: {
          'p_member_id': memberId,
          'p_full_name': fullName ?? existing.fullName,
          'p_phone': (phone ?? existing.phone).trim(),
          'p_email': email ?? existing.email,
          'p_date_of_birth': dateOfBirth ?? existing.dateOfBirth,
          'p_gender': gender ?? existing.gender,
          'p_notes': notes ?? existing.notes,
          'p_status': status ?? existing.status,
        },
      );
      return Member.fromJson(row as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      throw mapSupabaseError(
        e,
        duplicate: AppErrorCode.memberAlreadyExists,
        invalid: AppErrorCode.invalidMember,
        notFound: AppErrorCode.memberNotFound,
      );
    }
  }

  /// Powers the Booking → Member picker — facility-scoped, ACTIVE members
  /// only, unlike the old broken `profiles`-based search this replaces
  /// (which searched every member on the platform). A member doesn't need
  /// an active membership to be searchable/bookable.
  Future<List<MemberSearchResult>> searchMembers(String facilityId, String query) async {
    final trimmed = query.trim();
    if (trimmed.length < 2) return [];
    try {
      final rows = await _client.rpc('search_members', params: {'p_facility_id': facilityId, 'p_query': trimmed});
      return (rows as List<dynamic>).cast<Map<String, dynamic>>().map(MemberSearchResult.fromJson).toList();
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<List<MembershipPlan>> getFacilityPlans(String facilityId, {bool activeOnly = false}) async {
    try {
      var query = _client.from('membership_plans').select().eq('facility_id', facilityId);
      if (activeOnly) query = query.eq('is_active', true);
      final rows = await query.order('price_inr', ascending: true);
      return (rows as List<dynamic>).cast<Map<String, dynamic>>().map(MembershipPlan.fromJson).toList();
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<MembershipPlan> createPlan(MembershipPlanInput input) async {
    try {
      final row = await _client
          .from('membership_plans')
          .insert({
            'facility_id': input.facilityId,
            'name': input.name,
            'price_inr': input.priceInr,
            'duration_days': input.durationDays,
            'features': input.features,
          })
          .select()
          .single();
      return MembershipPlan.fromJson(row);
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e, invalid: AppErrorCode.invalidMembership);
    }
  }

  Future<MembershipPlan> updatePlan(
    String planId, {
    String? name,
    int? priceInr,
    int? durationDays,
    List<String>? features,
    bool? isActive,
  }) async {
    final update = <String, dynamic>{};
    if (name != null) update['name'] = name;
    if (priceInr != null) update['price_inr'] = priceInr;
    if (durationDays != null) update['duration_days'] = durationDays;
    if (features != null) update['features'] = features;
    if (isActive != null) update['is_active'] = isActive;
    try {
      final row = await _client.from('membership_plans').update(update).eq('id', planId).select().maybeSingle();
      if (row == null) throw AppException(AppErrorCode.membershipPlanNotFound);
      return MembershipPlan.fromJson(row);
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e, notFound: AppErrorCode.membershipPlanNotFound);
    }
  }

  /// The single write path for both "assign a plan" and "renew" — renewal
  /// is just calling this again with a new start date. Always inserts a new
  /// row, never updates, so membership history is preserved.
  Future<Membership> createMembership(CreateMembershipInput input) async {
    try {
      final row =
          await _client.rpc(
                'create_membership',
                params: {
                  'p_member_id': input.memberId,
                  'p_facility_id': input.facilityId,
                  'p_plan_id': input.planId,
                  'p_start_date': _dateOnly(input.startDate),
                  'p_payment_status': input.paymentStatus,
                },
              )
              as Map<String, dynamic>;

      final plan = await _client.from('membership_plans').select('name').eq('id', row['plan_id'] as String).maybeSingle();
      return Membership.fromJson(row, planName: plan?['name'] as String?);
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e, notFound: AppErrorCode.membershipPlanNotFound, invalid: AppErrorCode.invalidMembership);
    }
  }

  Future<Membership> cancelMembership(String membershipId) async {
    try {
      final row = await _client.rpc('cancel_membership', params: {'p_membership_id': membershipId}) as Map<String, dynamic>?;
      if (row == null) throw AppException(AppErrorCode.membershipNotFound);
      final plan = await _client.from('membership_plans').select('name').eq('id', row['plan_id'] as String).maybeSingle();
      return Membership.fromJson(row, planName: plan?['name'] as String?);
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e, notFound: AppErrorCode.membershipNotFound);
    }
  }

  /// The full Create Membership page write path — a self-contained
  /// membership (its own name / type / duration / fee / GST / time slot),
  /// not a plan assignment. Mirrors `createMembershipFull` in
  /// src/services/memberships/supabase-membership.service.ts: one RPC that
  /// gets-or-creates the member, inserts the membership, computes the charge
  /// total, and records the payment. See
  /// supabase/migrations/0028_membership_creation_form.sql.
  Future<Membership> createMembershipFull(CreateMembershipFullInput input) async {
    try {
      final row =
          await _client.rpc(
                'create_membership_full',
                params: {
                  'p_facility_id': input.facilityId,
                  'p_full_name': input.fullName,
                  'p_phone': input.phone,
                  'p_email': input.email,
                  'p_date_of_birth': input.dateOfBirth,
                  'p_gender': input.gender,
                  'p_address': input.address,
                  'p_name': input.name,
                  'p_membership_type': membershipTypeToDb(input.membershipType),
                  'p_max_family_members': input.maxFamilyMembers,
                  'p_start_date': _dateOnly(input.startDate),
                  'p_duration_days': input.durationDays,
                  'p_time_slot_start': input.timeSlotStart,
                  'p_time_slot_end': input.timeSlotEnd,
                  'p_description': input.description,
                  'p_membership_fee_inr': input.membershipFeeInr,
                  'p_registration_fee_inr': input.registrationFeeInr,
                  'p_gst_percent': input.gstPercent,
                  'p_payment_mode': membershipPaymentModeToDb(input.paymentMode),
                  'p_payment_methods': input.paymentMethods.isEmpty ? null : input.paymentMethods.join(', '),
                  'p_payment_reference': input.paymentReference,
                  'p_referral_member_id': input.referralMemberId,
                  'p_discovery_source': input.discoverySource,
                  'p_notes': input.notes,
                  'p_monthly_price_inr': input.membershipFeeInr,
                },
              )
              as Map<String, dynamic>;
      return Membership.fromJson(row, planName: row['name'] as String? ?? 'Membership');
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e, invalid: AppErrorCode.invalidMembership);
    }
  }

  /// Generates a Razorpay UPI AutoPay mandate for a recurring membership —
  /// invokes the `create-membership-subscription` Edge Function (the only
  /// place the Razorpay secret exists). Mirrors the web service's
  /// `createMembershipSubscription`. Same error mapping as
  /// [PaymentRepository.createPaymentOrder].
  Future<MembershipSubscriptionInfo> createMembershipSubscription(String membershipId) async {
    final FunctionResponse response;
    try {
      response = await _client.functions.invoke(
        'create-membership-subscription',
        body: {'membershipId': membershipId},
      );
    } on FunctionsHttpException catch (e) {
      final details = e.details;
      if (details is Map && details['error'] is String) {
        throw AppException(AppErrorCode.paymentGatewayError, details['error'] as String);
      }
      throw AppException(AppErrorCode.paymentGatewayError);
    } on FunctionException {
      throw AppException(AppErrorCode.paymentGatewayError);
    }
    final data = response.data;
    if (data is! Map || data['error'] != null) throw AppException(AppErrorCode.paymentGatewayError);
    return MembershipSubscriptionInfo.fromJson(data.cast<String, dynamic>());
  }

  /// The Memberships page list — every membership at the facility (not one
  /// row per member), filtered / sorted / paginated server-side. Mirrors
  /// `listMemberships` on the web; the plan is optional and the row falls
  /// back to the membership's own name / fee / time slot.
  Future<MembershipListResult> listMemberships(String facilityId, MembershipListParams params) async {
    try {
      final rows = await _client.rpc(
        'list_memberships',
        params: {
          'p_facility_id': facilityId,
          'p_search': params.search?.trim().isNotEmpty == true ? params.search!.trim() : null,
          'p_status': membershipListStatusToDb(params.status),
          'p_plan_id': params.planId,
          'p_sort': membershipListSortToDb(params.sort),
          'p_limit': params.perPage,
          'p_offset': (params.page - 1) * params.perPage,
        },
      );
      final list = (rows as List<dynamic>).cast<Map<String, dynamic>>();
      return MembershipListResult(
        rows: list.map(MembershipListRow.fromJson).toList(),
        totalCount: list.isEmpty ? 0 : (list.first['total_count'] as num?)?.toInt() ?? 0,
      );
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// The five KPI values above the Memberships list. Mirrors
  /// `getMembershipPageSummary` on the web, including the percent-change math.
  Future<MembershipPageSummary> getMembershipPageSummary(String facilityId) async {
    try {
      final rows = await _client.rpc('get_membership_page_summary', params: {'p_facility_id': facilityId});
      final list = (rows as List<dynamic>).cast<Map<String, dynamic>>();
      return MembershipPageSummary.fromJson(list.isEmpty ? const {} : list.first);
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<MemberStats> getMemberStats(String memberId, String facilityId) async {
    try {
      final rows = await _client.rpc('get_member_stats', params: {'p_member_id': memberId, 'p_facility_id': facilityId});
      final list = rows as List<dynamic>;
      if (list.isEmpty) {
        return const MemberStats(totalVisits: 0, totalBookings: 0, totalAmountMinor: 0, pendingAmountMinor: 0, sports: []);
      }
      return MemberStats.fromJson(list.first as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// Every membership a member has held at this facility, most recent first
  /// — never overwritten by renewal, so this is what proves renewal history
  /// is preserved.
  Future<List<Membership>> getMembershipHistory(String memberId, String facilityId) async {
    try {
      final rows = await _client
          .from('memberships')
          .select('*, membership_plans(name)')
          .eq('member_id', memberId)
          .eq('facility_id', facilityId)
          .order('start_date', ascending: false);
      return (rows as List<dynamic>).cast<Map<String, dynamic>>().map((row) {
        final planName = (row['membership_plans'] as Map<String, dynamic>?)?['name'] as String?;
        return Membership.fromJson(row, planName: planName);
      }).toList();
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// Paginated, most recent first — never loads unlimited history.
  Future<List<Booking>> getMemberBookings(String memberId, String facilityId, {int limit = 20, int offset = 0}) async {
    try {
      final rows = await _client
          .from('bookings')
          .select()
          .eq('member_id', memberId)
          .eq('facility_id', facilityId)
          .order('start_time', ascending: false)
          .range(offset, offset + limit - 1);
      return (rows as List<dynamic>).cast<Map<String, dynamic>>().map(Booking.fromJson).toList();
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    }
  }
}