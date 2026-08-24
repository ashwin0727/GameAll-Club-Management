import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/errors/app_exception.dart';
import '../models/booking.dart';
import '../models/guest.dart';

/// Mirrors src/services/guests/supabase-guest.service.ts — same
/// `find_or_create_guest`/`update_guest`/`get_guest_stats` RPCs, so a guest
/// created/updated on either client is immediately visible on both.
class GuestRepository {
  GuestRepository(this._client);

  final SupabaseClient _client;

  Future<List<GuestPlayer>> searchGuests(String facilityId, String query) async {
    final trimmed = query.trim();
    if (trimmed.length < 2) return [];
    try {
      final rows = await _client
          .from('guest_players')
          .select()
          .eq('facility_id', facilityId)
          .or('name.ilike.%$trimmed%,phone.ilike.%$trimmed%')
          .order('name', ascending: true)
          .limit(20);
      return (rows as List<dynamic>).cast<Map<String, dynamic>>().map(GuestPlayer.fromJson).toList();
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<List<GuestPlayer>> listGuests(String facilityId, {GuestStatus? status, int limit = 50, int offset = 0}) async {
    try {
      var query = _client.from('guest_players').select().eq('facility_id', facilityId);
      if (status != null) query = query.eq('status', guestStatusToDb(status));
      final rows = await query.order('updated_at', ascending: false).range(offset, offset + limit - 1);
      return (rows as List<dynamic>).cast<Map<String, dynamic>>().map(GuestPlayer.fromJson).toList();
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<GuestPlayer?> getGuest(String guestId) async {
    try {
      final row = await _client.from('guest_players').select().eq('id', guestId).maybeSingle();
      return row == null ? null : GuestPlayer.fromJson(row);
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// The single write path for both "search existing" and "create new" in
  /// the Booking → Guest flow — matches by normalized phone within the
  /// facility and returns the existing profile untouched if found.
  Future<GuestPlayer> findOrCreateGuest(GuestInput input) async {
    try {
      final row = await _client.rpc(
        'find_or_create_guest',
        params: {
          'p_facility_id': input.facilityId,
          'p_name': input.name,
          'p_phone': input.phone,
          'p_email': input.email,
          'p_notes': input.notes,
        },
      );
      return GuestPlayer.fromJson(row as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e, invalid: AppErrorCode.invalidGuest);
    }
  }

  Future<GuestPlayer> updateGuest(
    String guestId, {
    required String name,
    String? phone,
    String? email,
    String? notes,
    GuestStatus? status,
  }) async {
    try {
      final row = await _client.rpc(
        'update_guest',
        params: {
          'p_guest_id': guestId,
          'p_name': name,
          'p_phone': phone,
          'p_email': email,
          'p_notes': notes,
          'p_status': status != null ? guestStatusToDb(status) : null,
        },
      );
      return GuestPlayer.fromJson(row as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e, invalid: AppErrorCode.invalidGuest, notFound: AppErrorCode.guestNotFound);
    }
  }

  Future<GuestStats> getGuestStats(String guestId) async {
    try {
      final rows = await _client.rpc('get_guest_stats', params: {'p_guest_id': guestId});
      final list = rows as List<dynamic>;
      if (list.isEmpty) {
        return const GuestStats(totalVisits: 0, totalBookings: 0, totalAmountMinor: 0, pendingAmountMinor: 0, sports: []);
      }
      return GuestStats.fromJson(list.first as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// Paginated, most recent first — never loads unlimited history.
  Future<List<Booking>> getGuestBookings(String guestId, {int limit = 20, int offset = 0}) async {
    try {
      final rows = await _client
          .from('bookings')
          .select()
          .eq('guest_player_id', guestId)
          .order('start_time', ascending: false)
          .range(offset, offset + limit - 1);
      return (rows as List<dynamic>).cast<Map<String, dynamic>>().map(Booking.fromJson).toList();
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    }
  }
}