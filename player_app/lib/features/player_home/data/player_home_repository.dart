import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import '../domain/player_home_models.dart';

/// Where the Home page gets its data. The Supabase version is the real one; tests supply a fake.
abstract class PlayerHomeRepository {
  Future<PlayerHomeData> load();
}

/// Reads everything in one call to `get_my_player_home` (migration 0167): the caller's own name, enrolments, bookings and unread
/// notifications. Row-level security still applies: the function only ever looks at the signed-in player's records.
class SupabasePlayerHomeRepository implements PlayerHomeRepository {
  SupabasePlayerHomeRepository([SupabaseClient? client]) : _injected = client;

  final SupabaseClient? _injected;

  SupabaseClient? get _client {
    if (_injected != null) return _injected;
    if (!AppConfig.isConfigured) return null;
    return Supabase.instance.client;
  }

  @override
  Future<PlayerHomeData> load() async {
    final client = _client;
    final user = client?.auth.currentUser;
    // Not configured or not signed in: the page still opens, in its "new player" state.
    if (client == null || user == null) return const PlayerHomeData.guest();

    try {
      // The dashboard (migration 0169) finds the player's memberships, coaching and guest bookings at every club by their phone number.
      // Older databases only have get_my_player_home, which still answers the basics.
      Object? result;
      try {
        result = await client.rpc('get_player_dashboard');
      } on PostgrestException catch (e) {
        if (e.code != 'PGRST202' && e.code != '42883') rethrow;
        result = await client.rpc('get_my_player_home');
      }
      final data = PlayerHomeData.fromJson(
        (result as Map).cast<String, dynamic>(),
      );
      return data;
    } on PostgrestException catch (e) {
      // The database function is not installed yet (migration 0167): show the page without the personal parts rather than failing.
      if (e.code == 'PGRST202' || e.code == '42883') {
        return const PlayerHomeData.guest();
      }
      rethrow;
    }
  }
}
