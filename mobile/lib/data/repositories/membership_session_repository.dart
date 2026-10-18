import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/errors/app_exception.dart';
import '../models/membership_session.dart';
import '../models/membership_session_dashboard.dart';

/// These RPCs raise 23514 with an already-polished, specific message for
/// every business-rule violation (capacity full, nothing to release, a
/// released slot already guest-booked, etc.) — surfaced verbatim rather
/// than collapsed into one generic string, since a real caller needs to
/// know exactly which rule was hit. Mirrors the web service's
/// `mapCapacityError` in supabase-membership-session.service.ts exactly.
AppException _mapCapacityError(PostgrestException error) {
  if (error.code == '23514') return AppException(AppErrorCode.membershipCapacityError, error.message);
  if (error.code == '23503') return AppException(AppErrorCode.invalidMembershipBatch);
  if (error.code == 'P0002') return AppException(AppErrorCode.membershipSessionNotFound);
  if (error.code == '42501') return AppException(AppErrorCode.unauthorized);
  return AppException(AppErrorCode.databaseError);
}

/// Mirrors src/services/membership-sessions/supabase-membership-session.service.ts
/// — same `create_membership_batch`/`update_membership_batch`/
/// `assign_batch_member`/`remove_batch_member`/`get_or_create_membership_session`/
/// `get_membership_session_capacity`/`book_membership_slot`/
/// `release_membership_capacity`/`restore_membership_capacity`/
/// `book_guest_slot`/`cancel_membership_slot_booking`/
/// `list_membership_sessions_for_date` RPCs, so a batch/session/booking
/// created on either client is immediately visible on both. See
/// supabase/migrations/0014_membership_sessions.sql for the authoritative
/// backend contract. Every write RPC locks the session row before reading
/// counts, so capacity math is never trusted from the client — this class
/// only ever forwards to the RPC, it never computes capacity itself (see
/// ../../features/membership_sessions/capacity.dart for the client-side
/// mirror used purely for optimistic UI, e.g. disabling buttons).
class MembershipSessionRepository {
  MembershipSessionRepository(this._client);

  final SupabaseClient _client;

  Future<List<MembershipBatch>> getFacilityBatches(String facilityId) async {
    try {
      final rows = await _client
          .from('membership_batches')
          .select()
          .eq('facility_id', facilityId)
          .order('start_time', ascending: true);
      return (rows as List<dynamic>).cast<Map<String, dynamic>>().map(MembershipBatch.fromJson).toList();
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<MembershipBatch> createBatch(MembershipBatchInput input) async {
    try {
      final row = await _client.rpc(
        'create_membership_batch',
        params: {
          'p_facility_id': input.facilityId,
          'p_plan_id': input.planId,
          'p_facility_sport_id': input.facilitySportId,
          'p_court_id': input.courtId,
          'p_name': input.name,
          'p_days_of_week': input.daysOfWeek,
          'p_start_time': input.startTime,
          'p_end_time': input.endTime,
          'p_capacity': input.capacity,
        },
      );
      return MembershipBatch.fromJson(row as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      throw _mapCapacityError(e);
    }
  }

  /// Any field left null keeps its current value — fetches the existing row
  /// first since `update_membership_batch` requires every field (unlike
  /// `create_membership_batch`'s all-required signature), mirroring the web
  /// service's PATCH-merge semantics.
  Future<MembershipBatch> updateBatch(
    String batchId, {
    String? name,
    String? courtId,
    List<int>? daysOfWeek,
    String? startTime,
    String? endTime,
    int? capacity,
    bool? isActive,
  }) async {
    final Map<String, dynamic>? existing;
    try {
      existing = await _client.from('membership_batches').select().eq('id', batchId).maybeSingle();
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    }
    if (existing == null) throw AppException(AppErrorCode.membershipBatchNotFound);

    try {
      final row = await _client.rpc(
        'update_membership_batch',
        params: {
          'p_batch_id': batchId,
          'p_name': name ?? existing['name'],
          'p_court_id': courtId ?? existing['court_id'],
          'p_days_of_week': daysOfWeek ?? existing['days_of_week'],
          'p_start_time': startTime ?? existing['start_time'],
          'p_end_time': endTime ?? existing['end_time'],
          'p_capacity': capacity ?? existing['capacity'],
          'p_is_active': isActive ?? existing['is_active'],
        },
      );
      return MembershipBatch.fromJson(row as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      throw _mapCapacityError(e);
    }
  }

  Future<List<MembershipBatchMember>> getBatchMembers(String batchId) async {
    try {
      final rows = await _client
          .from('membership_batch_members')
          .select()
          .eq('batch_id', batchId)
          .order('created_at', ascending: true);
      return (rows as List<dynamic>).cast<Map<String, dynamic>>().map(MembershipBatchMember.fromJson).toList();
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<MembershipBatchMember> assignBatchMember(String batchId, String memberId, {String? membershipId}) async {
    try {
      final row = await _client.rpc(
        'assign_batch_member',
        params: {'p_batch_id': batchId, 'p_member_id': memberId, 'p_membership_id': membershipId},
      );
      return MembershipBatchMember.fromJson(row as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      throw _mapCapacityError(e);
    }
  }

  Future<void> removeBatchMember(String batchId, String memberId) async {
    try {
      await _client.rpc('remove_batch_member', params: {'p_batch_id': batchId, 'p_member_id': memberId});
    } on PostgrestException catch (e) {
      throw _mapCapacityError(e);
    }
  }

  /// The Owner Availability View's single read — every batch scheduled on
  /// this date, materialized or not.
  Future<List<MembershipSessionSlot>> listSessionsForDate(String facilityId, String date) async {
    try {
      final rows = await _client.rpc(
        'list_membership_sessions_for_date',
        params: {'p_facility_id': facilityId, 'p_date': date},
      );
      return (rows as List<dynamic>).cast<Map<String, dynamic>>().map(MembershipSessionSlot.fromJson).toList();
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// Materializes the session occurrence row if it doesn't exist yet —
  /// needed before release/restore on a date nobody has booked against.
  /// Returns the session id.
  Future<String> getOrCreateSession(String batchId, String sessionDate) async {
    try {
      final row = await _client.rpc(
        'get_or_create_membership_session',
        params: {'p_batch_id': batchId, 'p_session_date': sessionDate},
      );
      return (row as Map<String, dynamic>)['id'] as String;
    } on PostgrestException catch (e) {
      throw _mapCapacityError(e);
    }
  }

  Future<MembershipSessionCapacity> getSessionCapacity(String sessionId) async {
    try {
      final rows = await _client.rpc('get_membership_session_capacity', params: {'p_session_id': sessionId});
      final list = (rows as List<dynamic>).cast<Map<String, dynamic>>();
      if (list.isEmpty) throw AppException(AppErrorCode.membershipSessionNotFound);
      return MembershipSessionCapacity.fromJson(list.first);
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<MembershipSessionBooking> bookMembershipSlot(String batchId, String sessionDate, String memberId) async {
    try {
      final row = await _client.rpc(
        'book_membership_slot',
        params: {'p_batch_id': batchId, 'p_session_date': sessionDate, 'p_member_id': memberId},
      );
      return MembershipSessionBooking.fromJson(row as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      throw _mapCapacityError(e);
    }
  }

  Future<void> releaseCapacity(String sessionId, int count) async {
    try {
      await _client.rpc('release_membership_capacity', params: {'p_session_id': sessionId, 'p_count': count});
    } on PostgrestException catch (e) {
      throw _mapCapacityError(e);
    }
  }

  Future<void> restoreCapacity(String sessionId, int count) async {
    try {
      await _client.rpc('restore_membership_capacity', params: {'p_session_id': sessionId, 'p_count': count});
    } on PostgrestException catch (e) {
      throw _mapCapacityError(e);
    }
  }

  /// A guest consumes ONLY released capacity — computes price via the
  /// existing `resolve_booking_price` RPC server-side, no second pricing
  /// engine on this client either.
  Future<MembershipSessionBooking> bookGuestSlot(String batchId, String sessionDate, String guestPlayerId) async {
    try {
      final row = await _client.rpc(
        'book_guest_slot',
        params: {'p_batch_id': batchId, 'p_session_date': sessionDate, 'p_guest_player_id': guestPlayerId},
      );
      return MembershipSessionBooking.fromJson(row as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      throw _mapCapacityError(e);
    }
  }

  Future<void> cancelSlotBooking(String bookingId) async {
    try {
      await _client.rpc('cancel_membership_slot_booking', params: {'p_booking_id': bookingId});
    } on PostgrestException catch (e) {
      throw _mapCapacityError(e);
    }
  }

  // ---------------------------------------------------------------------------
  // Membership Sessions dashboard (0036) — mirrors
  // src/services/membership-sessions/supabase-membership-session.service.ts.
  // ---------------------------------------------------------------------------

  Future<MembershipSessionsSummary> getSessionsSummary(String facilityId) async {
    try {
      final data = await _client.rpc('get_membership_sessions_summary', params: {'p_facility_id': facilityId});
      return MembershipSessionsSummary.fromJson((data as Map).cast<String, dynamic>());
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<({List<MembershipSessionListRow> rows, int totalCount})> listSessionsAdmin(
    String facilityId, {
    String? search,
    String? facilitySportId,
    String? courtId,
    String? status,
    int? day,
    int limit = 10,
    int offset = 0,
  }) async {
    try {
      final rows = await _client.rpc('list_membership_sessions_admin', params: {
        'p_facility_id': facilityId,
        'p_search': search,
        'p_facility_sport_id': facilitySportId,
        'p_court_id': courtId,
        'p_status': status,
        'p_day': day,
        'p_limit': limit,
        'p_offset': offset,
      });
      final list = (rows as List<dynamic>).cast<Map<String, dynamic>>();
      final total = list.isEmpty ? 0 : (list.first['total_count'] as num?)?.toInt() ?? 0;
      return (rows: list.map(MembershipSessionListRow.fromJson).toList(), totalCount: total);
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<MembershipSessionDetail> getSessionDetail(String batchId) async {
    try {
      final data = await _client.rpc('get_membership_session_detail', params: {'p_batch_id': batchId});
      return MembershipSessionDetail.fromJson((data as Map).cast<String, dynamic>());
    } on PostgrestException catch (e) {
      throw _mapCapacityError(e);
    }
  }

  Future<List<MembershipSessionMemberRow>> getSessionMembers(String batchId) async {
    try {
      final rows = await _client.rpc('list_membership_session_members', params: {'p_batch_id': batchId});
      return (rows as List<dynamic>).cast<Map<String, dynamic>>().map(MembershipSessionMemberRow.fromJson).toList();
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> setSessionNotes(String batchId, String notes) async {
    try {
      await _client.rpc('set_membership_batch_notes', params: {'p_batch_id': batchId, 'p_notes': notes});
    } on PostgrestException catch (e) {
      throw _mapCapacityError(e);
    }
  }

  Future<List<MembershipSessionOccurrence>> listOccurrences(String batchId, {int days = 30}) async {
    try {
      final rows = await _client.rpc(
        'list_membership_session_occurrences',
        params: {'p_batch_id': batchId, 'p_days': days},
      );
      return (rows as List<dynamic>).cast<Map<String, dynamic>>().map(MembershipSessionOccurrence.fromJson).toList();
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<List<MembershipSessionBookingRow>> listSessionBookings(String batchId, {int limit = 50}) async {
    try {
      final rows = await _client.rpc(
        'list_membership_session_bookings',
        params: {'p_batch_id': batchId, 'p_limit': limit},
      );
      return (rows as List<dynamic>).cast<Map<String, dynamic>>().map(MembershipSessionBookingRow.fromJson).toList();
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<List<MembershipSessionActivity>> listSessionActivity(String batchId, {int limit = 50}) async {
    try {
      final rows = await _client.rpc(
        'list_membership_session_activity',
        params: {'p_batch_id': batchId, 'p_limit': limit},
      );
      return (rows as List<dynamic>).cast<Map<String, dynamic>>().map(MembershipSessionActivity.fromJson).toList();
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> blockDate(String batchId, String date, {String? reason}) async {
    try {
      await _client.rpc(
        'block_membership_batch_date',
        params: {'p_batch_id': batchId, 'p_date': date, 'p_reason': reason},
      );
    } on PostgrestException catch (e) {
      throw _mapCapacityError(e);
    }
  }

  Future<void> unblockDate(String batchId, String date) async {
    try {
      await _client.rpc('unblock_membership_batch_date', params: {'p_batch_id': batchId, 'p_date': date});
    } on PostgrestException catch (e) {
      throw _mapCapacityError(e);
    }
  }

  Future<MembershipBatch> duplicateSession(String batchId, {String? newName}) async {
    try {
      final row = await _client.rpc(
        'duplicate_membership_batch',
        params: {'p_batch_id': batchId, 'p_new_name': newName},
      );
      return MembershipBatch.fromJson(row as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      throw _mapCapacityError(e);
    }
  }
}