import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import '../domain/player_notification.dart';

/// The player's notifications. The Supabase version is the real one (migration 0194); tests supply a fake.
abstract class NotificationRepository {
  /// Newest first. [unreadOnly] is the bell's list; false also lists the read ones of the last 30 days.
  Future<List<PlayerNotification>> list({bool unreadOnly = true});

  Future<int> unreadCount();

  /// Marks the given messages read, or all of them when [ids] is null.
  Future<void> markRead([List<String>? ids]);

  /// Lets the server reach this phone with a push message.
  Future<void> registerDeviceToken(String token);

  Future<void> unregisterDeviceToken(String token);
}

class SupabaseNotificationRepository implements NotificationRepository {
  SupabaseNotificationRepository([SupabaseClient? client]) : _injected = client;

  final SupabaseClient? _injected;

  SupabaseClient? get _client =>
      _injected ?? (AppConfig.isConfigured ? Supabase.instance.client : null);

  /// Migration 0194 not applied yet: no messages rather than an error.
  bool _missing(PostgrestException e) => e.code == 'PGRST202' || e.code == '42883';

  SupabaseClient? get _signedIn {
    final c = _client;
    return c == null || c.auth.currentUser == null ? null : c;
  }

  @override
  Future<List<PlayerNotification>> list({bool unreadOnly = true}) async {
    final client = _signedIn;
    if (client == null) return const [];
    try {
      final r = await client.rpc(
        'list_my_notifications',
        params: {'p_unread_only': unreadOnly, 'p_limit': 50},
      );
      return [
        for (final e in (r as List<dynamic>? ?? const []))
          if (e is Map) PlayerNotification.fromJson(e.cast<String, dynamic>()),
      ];
    } on PostgrestException catch (e) {
      if (_missing(e)) return const [];
      rethrow;
    }
  }

  @override
  Future<int> unreadCount() async {
    final client = _signedIn;
    if (client == null) return 0;
    try {
      final r = await client.rpc('count_my_unread_notifications');
      return (r as num?)?.toInt() ?? 0;
    } on PostgrestException catch (e) {
      if (_missing(e)) return 0;
      rethrow;
    }
  }

  @override
  Future<void> markRead([List<String>? ids]) async {
    final client = _signedIn;
    if (client == null) return;
    await client.rpc('mark_notifications_read', params: {'p_ids': ids});
  }

  @override
  Future<void> registerDeviceToken(String token) async {
    final client = _signedIn;
    if (client == null) return;
    await client.rpc('register_device_token', params: {'p_token': token, 'p_platform': 'android'});
  }

  @override
  Future<void> unregisterDeviceToken(String token) async {
    final client = _signedIn;
    if (client == null) return;
    await client.rpc('unregister_device_token', params: {'p_token': token});
  }
}
