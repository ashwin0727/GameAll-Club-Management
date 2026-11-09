import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../data/notification_repository.dart';
import '../domain/player_notification.dart';

/// The notification data source. Tests override this with a fake.
final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) => SupabaseNotificationRepository(),
);

/// The bell: the messages not read yet (newest first) and how many there are.
class NotificationsState {
  const NotificationsState({this.unread = const [], this.total = 0, this.loaded = false});

  final List<PlayerNotification> unread;

  /// The unread count for the badge (can be more than the list shows).
  final int total;
  final bool loaded;
}

/// How often the bell looks for new messages while the app is open (a push message refreshes it at once).
const notificationPollInterval = Duration(seconds: 30);

class NotificationsController extends Notifier<NotificationsState> {
  @override
  NotificationsState build() {
    final player = ref.watch(currentPlayerProvider);
    if (player == null) return const NotificationsState(loaded: true);
    Future.microtask(refresh);
    return const NotificationsState();
  }

  Future<void> refresh() async {
    if (ref.read(currentPlayerProvider) == null) return;
    try {
      final repo = ref.read(notificationRepositoryProvider);
      final results = await Future.wait([repo.list(), repo.unreadCount()]);
      state = NotificationsState(
        unread: results[0] as List<PlayerNotification>,
        total: results[1] as int,
        loaded: true,
      );
    } catch (_) {
      // keep what is shown; the next look tries again
      if (!state.loaded) state = const NotificationsState(loaded: true);
    }
  }

  /// A read message leaves the list at once (the server is told in the background).
  Future<void> markRead(List<String> ids) async {
    if (ids.isEmpty) return;
    final gone = ids.toSet();
    final remaining = [for (final n in state.unread) if (!gone.contains(n.id)) n];
    state = NotificationsState(
      unread: remaining,
      total: (state.total - (state.unread.length - remaining.length)).clamp(0, 1 << 30),
      loaded: true,
    );
    try {
      await ref.read(notificationRepositoryProvider).markRead(ids);
    } catch (_) {
      await refresh();
    }
  }

  Future<void> markAllRead() async {
    state = const NotificationsState(loaded: true);
    try {
      await ref.read(notificationRepositoryProvider).markRead();
    } catch (_) {
      await refresh();
    }
  }
}

final notificationsControllerProvider = NotifierProvider<NotificationsController, NotificationsState>(
  NotificationsController.new,
);

/// The number on the bell.
final unreadNotificationCountProvider = Provider<int>(
  (ref) => ref.watch(notificationsControllerProvider).total,
);

/// Everything of the last 30 days, read or not (the phone page lists these; the web popup lists only the unread).
final allNotificationsProvider = FutureProvider.autoDispose<List<PlayerNotification>>((ref) async {
  if (ref.watch(currentPlayerProvider) == null) return const [];
  return ref.read(notificationRepositoryProvider).list(unreadOnly: false);
});
