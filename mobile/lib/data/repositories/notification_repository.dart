import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_notification.dart';

/// Notifications (migration 0161). Reads go straight to the table — row-level security shows only the signed-in person's own
/// rows. Marking read and registering a phone for push go through RPCs.
class NotificationRepository {
  NotificationRepository(this._client);

  final SupabaseClient _client;

  Future<List<AppNotification>> list({int limit = 50}) async {
    final rows = await _client
        .from('notifications')
        .select('id, kind, title, body, data, created_at, read_at')
        .order('created_at', ascending: false)
        .limit(limit);
    return (rows as List<dynamic>).map((r) => AppNotification.fromJson((r as Map).cast<String, dynamic>())).toList();
  }

  Future<int> unreadCount() async {
    final res = await _client.from('notifications').select('id').isFilter('read_at', null).count(CountOption.exact);
    return res.count;
  }

  /// Marks the given notifications read — or all of the person's, when [ids] is null.
  Future<void> markRead([List<String>? ids]) async {
    await _client.rpc('mark_notifications_read', params: {'p_ids': ids});
  }

  Future<void> registerDeviceToken(String token, {String platform = 'android'}) async {
    await _client.rpc('register_device_token', params: {'p_token': token, 'p_platform': platform});
  }

  Future<void> unregisterDeviceToken(String token) async {
    await _client.rpc('unregister_device_token', params: {'p_token': token});
  }
}
