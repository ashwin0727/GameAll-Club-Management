import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/resilient.dart';
import '../domain/cancellation_quote.dart';
import '../domain/guest_booking.dart';

/// Where the Guest Booking page gets its data. The Supabase version is the real one; tests supply a fake.
abstract class GuestBookingsRepository {
  Future<GuestBookings> mine();

  /// What cancelling this booking now would do (hours left, % deducted, refund), or null when it is not the player's.
  Future<CancellationQuote?> cancellationQuote(String bookingId) async => null;

  /// Cancels the booking; the refund (if any) goes back to the original payment method through Razorpay.
  Future<CancellationOutcome> cancel(String bookingId) async =>
      throw const CancelException('Cancelling is not available right now.');
}

/// Something to tell the player in plain words ("This booking cannot be cancelled.").
class CancelException implements Exception {
  const CancelException(this.message);
  final String message;
  @override
  String toString() => message;
}

class SupabaseGuestBookingsRepository implements GuestBookingsRepository {
  SupabaseGuestBookingsRepository([SupabaseClient? client])
    : _injected = client;

  final SupabaseClient? _injected;

  SupabaseClient? get _client =>
      _injected ?? (AppConfig.isConfigured ? Supabase.instance.client : null);

  @override
  Future<GuestBookings> mine() async {
    final client = _client;
    if (client == null) return const GuestBookings();
    final result = await retryTransient(
      () => client.rpc('get_my_guest_bookings'),
    );
    return result is Map
        ? GuestBookings.fromJson(result.cast<String, dynamic>())
        : const GuestBookings();
  }

  Future<Map<String, dynamic>> _call(String action, String bookingId) async {
    final client = _client;
    if (client == null) {
      throw const CancelException('Please sign in first.');
    }
    try {
      final res = await client.functions.invoke(
        'cancel-player-booking',
        body: {'action': action, 'bookingId': bookingId},
      );
      final data = res.data;
      if (data is Map) return data.cast<String, dynamic>();
      throw const CancelException("We couldn't reach the club's system. Please try again.");
    } on FunctionException catch (e) {
      final d = e.details;
      final msg = d is Map ? d['error'] as String? : null;
      throw CancelException(msg ?? "We couldn't do that right now. Please try again.");
    }
  }

  @override
  Future<CancellationQuote?> cancellationQuote(String bookingId) async {
    final data = await _call('quote', bookingId);
    final q = data['quote'];
    return q is Map ? CancellationQuote.fromJson(q.cast<String, dynamic>()) : null;
  }

  @override
  Future<CancellationOutcome> cancel(String bookingId) async {
    final data = await _call('cancel', bookingId);
    final q = data['quote'];
    if (q is! Map) {
      throw const CancelException("We couldn't cancel this booking. Please try again.");
    }
    final refunds = data['refunds'];
    return CancellationOutcome(
      quote: CancellationQuote.fromJson(q.cast<String, dynamic>()),
      refundsSent: refunds is List ? refunds.length : 0,
    );
  }
}
