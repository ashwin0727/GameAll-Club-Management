import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/errors/app_exception.dart';
import '../models/booking.dart';

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

  Future<List<MemberSearchResult>> searchMembers(String query) async {
    final trimmed = query.trim();
    if (trimmed.length < 2) return [];
    try {
      final rows = await _client
          .from('profiles')
          .select('id, full_name, email')
          .eq('role', 'member')
          .or('full_name.ilike.%$trimmed%,email.ilike.%$trimmed%')
          .limit(10);
      return (rows as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map((r) => MemberSearchResult(id: r['id'] as String, fullName: r['full_name'] as String, email: r['email'] as String))
          .toList();
    } on PostgrestException catch (e) {
      throw mapSupabaseError(e);
    }
  }
}