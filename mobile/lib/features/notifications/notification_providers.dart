import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/app_notification.dart';
import '../../data/repositories/notification_repository.dart';
import '../../data/services/supabase_provider.dart';
import '../authentication/session_controller.dart';

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return NotificationRepository(ref.watch(supabaseClientProvider));
});

/// The newest notifications for the signed-in person. Invalidate to refresh.
final notificationsProvider = FutureProvider.autoDispose<List<AppNotification>>((ref) async {
  if (ref.watch(sessionControllerProvider).user == null) return const [];
  return ref.watch(notificationRepositoryProvider).list();
});

/// The number on the bell. Refreshes every minute while the app is open in front (not while it is in the background), and whenever a
/// push arrives (see main.dart).
final unreadNotificationsProvider = StreamProvider.autoDispose<int>((ref) async* {
  final repo = ref.watch(notificationRepositoryProvider);
  final signedIn = ref.watch(sessionControllerProvider.select((s) => s.user != null));
  if (!signedIn) {
    yield 0;
    return;
  }
  while (true) {
    final life = WidgetsBinding.instance.lifecycleState;
    if (life == null || life == AppLifecycleState.resumed) {
      try {
        yield await repo.unreadCount();
      } catch (_) {
        yield 0;
      }
    }
    await Future<void>.delayed(const Duration(seconds: 60));
  }
});
