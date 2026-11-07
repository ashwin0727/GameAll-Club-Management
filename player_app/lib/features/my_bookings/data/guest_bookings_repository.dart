import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import '../domain/guest_booking.dart';

/// Where the Guest Booking page gets its data. The Supabase version is the real one; tests supply a fake.
abstract class GuestBookingsRepository {
  Future<GuestBookings> mine();
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
    final result = await client.rpc('get_my_guest_bookings');
    return result is Map
        ? GuestBookings.fromJson(result.cast<String, dynamic>())
        : const GuestBookings();
  }
}
