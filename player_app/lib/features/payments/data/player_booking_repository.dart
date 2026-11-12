import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';

/// Something the player can be told, in words: "Sorry, this court is no longer available."
class BookingException implements Exception {
  const BookingException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Makes the booking behind Guest Booking's "Book Now" for the signed-in player. Tests supply a fake.
abstract class PlayerBookingRepository {
  /// Books [courtId] from [start] to [end] and returns the booking's id. The name and the verified phone come from the player's own
  /// account on the server, never from the app.
  Future<String> create({
    required String facilityId,
    required String courtId,
    required DateTime start,
    required DateTime end,
    int partySize = 1,

    /// 'ADVANCE' (pay 50% now) or 'FULL': how the player chose to pay.
    String? paymentOption,
  });
}

class SupabasePlayerBookingRepository implements PlayerBookingRepository {
  SupabasePlayerBookingRepository([SupabaseClient? client])
    : _injected = client;

  final SupabaseClient? _injected;

  SupabaseClient? get _client =>
      _injected ?? (AppConfig.isConfigured ? Supabase.instance.client : null);

  @override
  Future<String> create({
    required String facilityId,
    required String courtId,
    required DateTime start,
    required DateTime end,
    int partySize = 1,
    String? paymentOption,
  }) async {
    final client = _client;
    if (client == null) throw const BookingException('Please sign in to book.');
    try {
      final res = await client.functions.invoke(
        'create-player-booking',
        body: {
          'facilityId': facilityId,
          'courtId': courtId,
          'startTime': start.toUtc().toIso8601String(),
          'endTime': end.toUtc().toIso8601String(),
          'partySize': partySize,
          'paymentOption': ?paymentOption,
        },
      );
      final data = res.data;
      final id = data is Map ? data['bookingId'] as String? : null;
      if (id == null || id.isEmpty) {
        throw const BookingException(
          "We couldn't make your booking. Please try again.",
        );
      }
      return id;
    } on FunctionException catch (e) {
      final details = e.details;
      final msg = details is Map ? details['error'] as String? : null;
      throw BookingException(
        msg ?? "We couldn't make your booking. Please try again.",
      );
    }
  }
}
