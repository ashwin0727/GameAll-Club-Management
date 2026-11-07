import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import '../domain/coaching_detail.dart';

/// Where the My Coaching page gets its data. The Supabase version is the real one; tests supply a fake.
abstract class CoachingDetailRepository {
  /// The signed-in player's active (or paused) coaching enrolments, the one that started first on top (empty when there are none).
  Future<List<CoachingDetail>> mine();
}

class SupabaseCoachingDetailRepository implements CoachingDetailRepository {
  SupabaseCoachingDetailRepository([SupabaseClient? client])
    : _injected = client;

  final SupabaseClient? _injected;

  SupabaseClient? get _client =>
      _injected ?? (AppConfig.isConfigured ? Supabase.instance.client : null);

  @override
  Future<List<CoachingDetail>> mine() async {
    final client = _client;
    if (client == null) return const [];
    final result = await client.rpc('get_my_coaching_details');
    return [
      for (final e in (result as List<dynamic>? ?? const []))
        if (e is Map) CoachingDetail.fromJson(e.cast<String, dynamic>()),
    ];
  }
}
