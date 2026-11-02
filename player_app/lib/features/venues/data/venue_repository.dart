import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import '../domain/venue.dart';

/// Where the venue list comes from. The Supabase version is the real one; tests supply a fake.
abstract class VenueRepository {
  /// The venues for a picked location such as "Bangalore, Karnataka" (empty when there are none).
  Future<List<Venue>> listForLocation(String location);
}

/// Calls the public `list_public_venues` database function (migration 0168). It needs no sign-in: anyone can look at venues.
class SupabaseVenueRepository implements VenueRepository {
  SupabaseVenueRepository([SupabaseClient? client]) : _injected = client;

  final SupabaseClient? _injected;

  SupabaseClient? get _client =>
      _injected ?? (AppConfig.isConfigured ? Supabase.instance.client : null);

  @override
  Future<List<Venue>> listForLocation(String location) async {
    final client = _client;
    if (client == null) return const [];
    final place = splitLocation(location);
    try {
      final result = await client.rpc(
        'list_public_venues',
        params: {'p_city': place.city, 'p_state': place.state},
      );
      return [
        for (final v in (result as List<dynamic>))
          Venue.fromJson((v as Map).cast<String, dynamic>()),
      ];
    } on PostgrestException catch (e) {
      // The function is not installed yet (migration 0168): the same as "no venues", rather than an error page.
      if (e.code == 'PGRST202' || e.code == '42883') return const [];
      rethrow;
    }
  }
}
