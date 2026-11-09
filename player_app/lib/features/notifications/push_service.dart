import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../core/routing/app_routes.dart';
import 'data/notification_repository.dart';

/// Phone push notifications through Firebase Cloud Messaging (the Android app; the web shows the bell's popup instead).
///
///  - asks for permission (Android 13+),
///  - registers this phone's token against the signed-in player, so the server can reach it,
///  - shows messages that arrive while the app is open (Firebase draws them itself only when the app is closed),
///  - opens the right page when a notification is tapped.
///
/// Best effort: a phone without Google services, or a build without the Firebase file (android/app/google-services.json), simply has
/// no push; the in-app list keeps working.
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  static const _channelId = 'gameall_player_default';
  final _local = FlutterLocalNotificationsPlugin();

  NotificationRepository? _repo;
  void Function(String route)? _open;
  String? _pendingRoute;
  String? _token;
  bool _ready = false;
  StreamSubscription<String>? _refreshSub;

  /// Called when a message arrives while the app is open (the bell refreshes).
  void Function()? onIncoming;

  /// The shell hands over how to open a page. A tap that launched the app is kept until then.
  void setOpener(void Function(String route)? open) {
    _open = open;
    final waiting = _pendingRoute;
    if (open != null && waiting != null) {
      _pendingRoute = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => open(waiting));
    }
  }

  void _goTo(String? route) {
    final r = (route == null || route.isEmpty) ? AppRoutes.notifications : route;
    final open = _open;
    if (open == null) {
      _pendingRoute = r;
    } else {
      open(r);
    }
  }

  /// Once, at start-up (not on the web).
  Future<void> init() async {
    if (kIsWeb || _ready) return;
    try {
      await Firebase.initializeApp();
      await _local.initialize(
        settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
        onDidReceiveNotificationResponse: (r) => _goTo(r.payload),
      );
      await _local
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              _channelId,
              'GameAll notifications',
              description: 'Booking reminders and payment updates',
              importance: Importance.high,
            ),
          );
      FirebaseMessaging.onMessage.listen(_onForeground);
      FirebaseMessaging.onMessageOpenedApp.listen((m) {
        onIncoming?.call();
        _goTo(m.data['route'] as String?);
      });
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _goTo(initial.data['route'] as String?);
      _ready = true;
    } catch (e) {
      debugPrint('Push notifications unavailable: $e');
    }
  }

  /// A player signed in: ask permission and register this phone for them.
  Future<void> onSignedIn(NotificationRepository repo) async {
    _repo = repo;
    if (kIsWeb || !_ready) return;
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

  /// The player signed out: stop sending this phone their messages.
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
    onIncoming?.call();
    final n = m.notification;
    if (n == null) return;
    await _local.show(
      id: m.hashCode & 0x7fffffff,
      title: n.title,
      body: n.body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(_channelId, 'GameAll notifications', importance: Importance.high, priority: Priority.high),
      ),
      payload: m.data['route'] as String?,
    );
  }
}
