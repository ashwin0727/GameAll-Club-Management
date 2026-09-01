import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/errors/app_exception.dart';
import '../models/booking.dart';
import '../models/guest_booking_dashboard.dart';

/// Mirrors src/services/bookings/supabase-booking.service.ts — same
/// `create_booking` RPC (validates operating hours + captures price
/// server-side; the bookings table's own exclusion constraint rejects a
/// double-booked slot atomically).
class BookingRepository {
  BookingRepository(this._client);

  final SupabaseClient _client;

  Future<List<Booking>> getBookingsForCourtOnDate(String courtId, DateTime date) async {
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    try {
      final rows = await _client
          .from('bookings')
          .select()
          .eq('court_id', courtId)
          .inFilter('status', ['pending', 'confirmed'])
          .gte('start_time', dayStart.toIso8601String())
          .lt('start_time', dayEnd.toIso8601String())
          .order('start_time', ascending: true);
      return (rows as List<dynamic>).cast<Map<String, dynamic>>().map(Booking.fromJson).toList();
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// All bookings (any status) for a facility within [from, to) — one query
  /// for the whole day's operations view, instead of one query per court.
  Future<List<Booking>> getBookingsForFacility(String facilityId, DateTime from, DateTime to) async {
    try {
      final rows = await _client
          .from('bookings')
          .select()
          .eq('facility_id', facilityId)
          .gte('start_time', from.toIso8601String())
          .lt('start_time', to.toIso8601String())
          .order('start_time', ascending: true);
      return (rows as List<dynamic>).cast<Map<String, dynamic>>().map(Booking.fromJson).toList();
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<Booking> createBooking(NewBookingInput input) async {
    try {
      final row = await _client.rpc(
        'create_booking',
        params: {
          'p_facility_id': input.facilityId,
          'p_court_id': input.courtId,
          'p_start_time': input.startTime.toIso8601String(),
          'p_end_time': input.endTime.toIso8601String(),
          'p_customer_type': customerTypeToDb(input.customerType),
          'p_member_id': input.memberId,
          'p_guest_name': input.guestName,
          'p_guest_phone': input.guestPhone,
          'p_notes': input.notes,
          'p_payment_status': paymentStatusToDb(input.paymentStatus),
          'p_guest_player_id': input.guestPlayerId,
          'p_party_size': input.partySize,
          'p_payment_method': input.paymentMethod,
        },
      );
      return Booking.fromJson(row as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e, notFound: AppErrorCode.courtNotFound, invalid: AppErrorCode.invalidBooking);
    }
  }

  Future<Booking> rescheduleBooking(RescheduleBookingInput input) async {
    try {
      final row = await _client.rpc(
        'reschedule_booking',
        params: {
          'p_booking_id': input.bookingId,
          'p_new_court_id': input.courtId,
          'p_new_start_time': input.startTime.toIso8601String(),
          'p_new_end_time': input.endTime.toIso8601String(),
        },
      );
      return Booking.fromJson(row as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e, notFound: AppErrorCode.bookingNotFound, invalid: AppErrorCode.invalidBooking);
    }
  }

  Future<void> cancelBooking(String bookingId, {String? reason}) async {
    try {
      final row = await _client
          .from('bookings')
          .update({'status': 'cancelled', 'cancellation_reason': reason})
          .eq('id', bookingId)
          .select('id')
          .maybeSingle();
      if (row == null) throw AppException(AppErrorCode.bookingNotFound);
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// Facility-scoped, ACTIVE-members-only search for the Booking → Member
  /// picker — calls the `search_members` RPC. Unlike the old `profiles`
  /// query this replaces (which searched every member on the platform by
  /// `role = 'member'`, a concept that no longer exists), this is scoped to
  /// one facility, matching `SupabaseBookingService.searchMembers` on the web.
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

  Future<GuestBookingsSummary> getGuestBookingsSummary(String facilityId, String from, String to) async {
    try {
      final data = await _client.rpc('get_guest_bookings_summary', params: {
        'p_facility_id': facilityId,
        'p_from': from,
        'p_to': to,
      });
      return GuestBookingsSummary.fromJson((data as Map).cast<String, dynamic>());
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<({List<GuestBookingRow> rows, int totalCount})> listGuestBookings(
    String facilityId, {
    String? search,
    String? facilitySportId,
    String? courtId,
    String? status,
    String? paymentStatus,
    String? from,
    String? to,
    int limit = 10,
    int offset = 0,
  }) async {
    try {
      final rows = await _client.rpc('list_guest_bookings_admin', params: {
        'p_facility_id': facilityId,
        'p_search': search,
        'p_facility_sport_id': facilitySportId,
        'p_court_id': courtId,
        'p_status': status,
        'p_payment_status': paymentStatus,
        'p_from': from,
        'p_to': to,
        'p_limit': limit,
        'p_offset': offset,
      });
      final list = (rows as List<dynamic>).cast<Map<String, dynamic>>();
      final total = list.isEmpty ? 0 : (list.first['total_count'] as num?)?.toInt() ?? 0;
      return (rows: list.map(GuestBookingRow.fromJson).toList(), totalCount: total);
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<Booking?> getBooking(String bookingId) async {
    try {
      final row = await _client.from('bookings').select().eq('id', bookingId).maybeSingle();
      return row == null ? null : Booking.fromJson(row);
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<Booking> updateGuestBooking(
    String bookingId, {
    required String guestName,
    String? guestPhone,
    required int partySize,
    String? notes,
  }) async {
    try {
      final row = await _client.rpc('update_guest_booking', params: {
        'p_booking_id': bookingId,
        'p_guest_name': guestName,
        'p_guest_phone': guestPhone,
        'p_party_size': partySize,
        'p_notes': notes,
      });
      return Booking.fromJson(row as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e, notFound: AppErrorCode.bookingNotFound, invalid: AppErrorCode.invalidBooking);
    }
  }

  Future<Booking> completeGuestBooking(String bookingId) async {
    try {
      final row = await _client.rpc('complete_guest_booking', params: {'p_booking_id': bookingId});
      return Booking.fromJson(row as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e, notFound: AppErrorCode.bookingNotFound, invalid: AppErrorCode.invalidBooking);
    }
  }

  Future<Booking> recordGuestBookingPayment(String bookingId, String method, int amountMinor) async {
    try {
      final row = await _client.rpc('record_guest_booking_payment', params: {
        'p_booking_id': bookingId,
        'p_method': method,
        'p_amount_minor': amountMinor,
      });
      return Booking.fromJson(row as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e, notFound: AppErrorCode.bookingNotFound, invalid: AppErrorCode.invalidBooking);
    }
  }

  Future<Booking> duplicateGuestBooking(String bookingId, DateTime newStart, DateTime newEnd) async {
    try {
      final row = await _client.rpc('duplicate_guest_booking', params: {
        'p_booking_id': bookingId,
        'p_new_start': newStart.toIso8601String(),
        'p_new_end': newEnd.toIso8601String(),
      });
      return Booking.fromJson(row as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e, notFound: AppErrorCode.bookingNotFound, invalid: AppErrorCode.invalidBooking);
    }
  }

  Future<void> deleteGuestBooking(String bookingId) async {
    try {
      await _client.rpc('delete_guest_booking', params: {'p_booking_id': bookingId});
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e, notFound: AppErrorCode.bookingNotFound, invalid: AppErrorCode.invalidBooking);
    }
  }

  Future<void> sendBookingReceipt(String bookingId, String email) async {
    final FunctionResponse res;
    try {
      res = await _client.functions.invoke('send-booking-receipt', body: {'bookingId': bookingId, 'email': email});
    } on FunctionsHttpException catch (e) {
      final d = e.details;
      throw AppException(AppErrorCode.databaseError, d is Map && d['error'] is String ? d['error'] as String : 'Could not send the receipt.');
    } on FunctionException {
      throw AppException(AppErrorCode.databaseError, 'Could not send the receipt.');
    }
    final data = res.data;
    if (data is! Map || data['sent'] != true) {
      throw AppException(AppErrorCode.databaseError, 'Could not send the receipt email.');
    }
  }
}