import 'package:gameall_player/features/notifications/data/notification_repository.dart';
import 'package:gameall_player/features/notifications/domain/player_notification.dart';

/// A notification data source held in memory, for tests.
class FakeNotifications implements NotificationRepository {
  FakeNotifications(this.items);

  final List<PlayerNotification> items;
  final List<List<String>?> markCalls = [];
  final List<String> registered = [];

  @override
  Future<List<PlayerNotification>> list({bool unreadOnly = true}) async => [
    for (final n in items)
      if (!unreadOnly || !n.isRead) n,
  ];

  @override
  Future<int> unreadCount() async => items.where((n) => !n.isRead).length;

  @override
  Future<void> markRead([List<String>? ids]) async {
    markCalls.add(ids);
    for (var i = 0; i < items.length; i++) {
      if (ids == null || ids.contains(items[i].id)) items[i] = items[i].markedRead();
    }
  }

  @override
  Future<void> registerDeviceToken(String token) async => registered.add(token);

  @override
  Future<void> unregisterDeviceToken(String token) async => registered.remove(token);
}

PlayerNotification notif(
  String id, {
  String kind = 'player_payment_success',
  String title = 'Payment successful',
  String body = 'We received ₹400 for your Court 2 booking.',
  String? route = '/bookings',
  bool read = false,
  Duration ago = const Duration(minutes: 5),
}) => PlayerNotification(
  id: id,
  kind: kind,
  title: title,
  body: body,
  createdAt: DateTime.now().subtract(ago),
  readAt: read ? DateTime.now() : null,
  route: route,
);
