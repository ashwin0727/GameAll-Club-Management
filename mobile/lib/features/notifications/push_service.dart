import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../core/routing/app_routes.dart';
import '../../data/repositories/notification_repository.dart';

/// The screen a notification points at, from its kind (set by the database — see migration 0161).
String notificationTarget(String kind) {
  if (kind.startsWith('guest_booking')) return AppRoutes.guestBookings;
  if (kind.startsWith('membership')) return AppRoutes.memberships;
  if (kind.startsWith('coaching')) return AppRoutes.coachingStudents;
  if (kind == 'monthly_report') return AppRoutes.reports;
  return AppRoutes.notifications;
}

/// Phone push notifications through Firebase Cloud Messaging.
///
///  • asks for permission (Android 13+),
///  • registers this phone's token against the signed-in person so the server can reach it,
///  • shows messages that arrive while the app is open (Firebase only draws them itself when the app is closed),
///  • opens the right screen when a notification is tapped.
///
/// Everything is best-effort: a phone without Google services, or a build without Firebase set up, just has no push — the
/// in-app notification list keeps working.
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  static const _channelId = 'gameall_default';
  final _local = FlutterLocalNotificationsPlugin();

  NotificationRepository? _repo;
  void Function(String route)? _open;
  void Function()? _onIncoming;
  String? _token;
  bool _ready = false;
  StreamSubscription<String>? _refreshSub;

  /// Call once at start-up. [open] navigates to an app route; [onIncoming] refreshes the unread badge.
  Future<void> init({required void Function(String route) open, required void Function() onIncoming}) async {
    _open = open;
    _onIncoming = onIncoming;
    if (_ready) return;
    try {
      await Firebase.initializeApp();
      await _local.initialize(
        settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
        onDidReceiveNotificationResponse: (r) {
          final route = r.payload;
          if (route != null && route.isNotEmpty) _open?.call(route);
        },
      );
      await _local
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(const AndroidNotificationChannel(
            _channelId,
            'GameAll notifications',
            description: 'Bookings, memberships, coaching and payments',
            importance: Importance.high,
          ));

      FirebaseMessaging.onMessage.listen(_onForeground);
      FirebaseMessaging.onMessageOpenedApp.listen((m) => _openFor(m));
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _openFor(initial);
      _ready = true;
      // First launch: ask now, so the person decides before anything is waiting for them. Android only shows its dialog
      // while the answer is still undecided.
      await FirebaseMessaging.instance.requestPermission();
    } catch (e) {
      debugPrint('Push notifications unavailable: $e');
    }
  }

  /// A person signed in: ask permission and register this phone for them.
  Future<void> onSignedIn(NotificationRepository repo) async {
    _repo = repo;
    if (!_ready) return;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        _token = token;
        await repo.registerDeviceToken(token);
      }
      _refreshSub ??= FirebaseMessaging.instance.onTokenRefresh.listen((t) async {
        _token = t;
        try {
          await _repo?.registerDeviceToken(t);
        } catch (_) {}
      });
    } catch (e) {
      debugPrint('Could not register for push: $e');
    }
  }

  /// The person signed out: stop sending this phone their messages.
  Future<void> onSignedOut() async {
    final token = _token;
    final repo = _repo;
    _token = null;
    _repo = null;
    if (token == null || repo == null) return;
    try {
      await repo.unregisterDeviceToken(token);
    } catch (_) {}
  }

  Future<void> _onForeground(RemoteMessage m) async {
    _onIncoming?.call();
    final n = m.notification;
    if (n == null) return;
    final kind = m.data['kind'] as String? ?? '';
    await _local.show(
      id: m.hashCode & 0x7fffffff,
      title: n.title,
      body: n.body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(_channelId, 'GameAll notifications', importance: Importance.high, priority: Priority.high),
      ),
      payload: notificationTarget(kind),
    );
  }

  void _openFor(RemoteMessage m) {
    _onIncoming?.call();
    _open?.call(notificationTarget(m.data['kind'] as String? ?? ''));
  }
}
