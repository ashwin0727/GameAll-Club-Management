import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_player/core/theme/app_theme.dart';
import 'package:gameall_player/features/auth/application/auth_providers.dart';
import 'package:gameall_player/features/auth/domain/player_profile.dart';
import 'package:gameall_player/features/notifications/application/notification_providers.dart';
import 'package:gameall_player/features/notifications/domain/player_notification.dart';
import 'package:gameall_player/features/notifications/presentation/notifications_ui.dart';

import '../support/fake_notifications.dart';

const _me = PlayerProfile(id: 'u1', fullName: 'Uma', phone: '8925643891');

Future<List<String>> _open(
  WidgetTester tester,
  FakeNotifications repo, {
  Size size = const Size(1280, 800),
  bool page = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final routes = <String>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        notificationRepositoryProvider.overrideWithValue(repo),
        currentPlayerProvider.overrideWithValue(_me),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Consumer(
          builder: (context, ref, _) {
            if (page) return NotificationsPage(onNavigate: routes.add);
            final count = ref.watch(unreadNotificationCountProvider);
            return Scaffold(
              body: Center(
                child: TextButton(
                  key: const ValueKey('bell'),
                  onPressed: () => openNotifications(context, onNavigate: routes.add),
                  child: Text('bell $count'),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return routes;
}

void main() {
  group('PlayerNotification', () {
    test('reads the server row and knows how long ago it was', () {
      final n = PlayerNotification.fromJson({
        'id': 'a',
        'kind': 'player_payment_failed',
        'title': 'Payment failed',
        'body': 'x',
        'data': {'route': '/my-membership'},
        'createdAt': DateTime.now().subtract(const Duration(minutes: 12)).toUtc().toIso8601String(),
        'readAt': null,
      });
      expect(n.isRead, isFalse);
      expect(n.isFailure, isTrue);
      expect(n.route, '/my-membership');
      expect(n.ago(DateTime.now()), '12 min ago');
      expect(n.markedRead().isRead, isTrue);
    });
  });

  group('on the web (a wide window)', () {
    testWidgets('the bell shows the unread count and opens a popup of the unread messages only', (tester) async {
      final repo = FakeNotifications([
        notif('a', title: 'Your game starts in 30 minutes', kind: 'player_booking_reminder'),
        notif('b', title: 'Payment failed', kind: 'player_payment_failed'),
        notif('c', title: 'Old read one', read: true),
      ]);
      await _open(tester, repo);
      expect(find.text('bell 2'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('bell')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('notif-popup')), findsOneWidget);
      expect(find.text('Your game starts in 30 minutes'), findsOneWidget);
      expect(find.text('Payment failed'), findsOneWidget);
      expect(find.text('Old read one'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping a message reads it: it leaves the list, the count drops, and its page opens', (tester) async {
      final repo = FakeNotifications([
        notif('a', title: 'First', route: '/bookings'),
        notif('b', title: 'Second', route: '/my-coaching'),
      ]);
      final routes = await _open(tester, repo);
      await tester.tap(find.byKey(const ValueKey('bell')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('notif-item-a')));
      await tester.pumpAndSettle();
      expect(routes, ['/bookings']);
      expect(repo.markCalls, [
        ['a'],
      ]);
      expect(find.text('bell 1'), findsOneWidget);
      // opening the popup again: the read one is gone
      await tester.tap(find.byKey(const ValueKey('bell')));
      await tester.pumpAndSettle();
      expect(find.text('First'), findsNothing);
      expect(find.text('Second'), findsOneWidget);
    });

    testWidgets('Mark all as read empties the popup', (tester) async {
      final repo = FakeNotifications([notif('a'), notif('b')]);
      await _open(tester, repo);
      await tester.tap(find.byKey(const ValueKey('bell')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('notif-mark-all')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('notif-empty')), findsOneWidget);
      expect(find.text('bell 0'), findsOneWidget);
      expect(repo.markCalls.last, isNull);
    });

    testWidgets('with nothing unread it says so', (tester) async {
      await _open(tester, FakeNotifications([notif('a', read: true)]));
      await tester.tap(find.byKey(const ValueKey('bell')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('notif-empty')), findsOneWidget);
    });
  });

  group('on a phone', () {
    testWidgets('the bell opens the Notifications page (no popup)', (tester) async {
      final routes = await _open(tester, FakeNotifications([notif('a')]), size: const Size(390, 844));
      await tester.tap(find.byKey(const ValueKey('bell')));
      await tester.pumpAndSettle();
      expect(routes, ['/notifications']);
      expect(find.byKey(const ValueKey('notif-popup')), findsNothing);
    });

    testWidgets('the page lists unread first and the read ones dimmed; tapping marks read and opens the page', (tester) async {
      final repo = FakeNotifications([
        notif('old', title: 'Read earlier', read: true, ago: const Duration(days: 2)),
        notif('new', title: 'Brand new', route: '/my-membership', ago: const Duration(minutes: 1)),
      ]);
      final routes = await _open(tester, repo, size: const Size(390, 844), page: true);
      expect(find.text('Brand new'), findsOneWidget);
      expect(find.text('Read earlier'), findsOneWidget);
      expect(find.byKey(const ValueKey('notif-dot-new')), findsOneWidget);
      expect(find.byKey(const ValueKey('notif-dot-old')), findsNothing);
      // unread is above the read one
      expect(tester.getTopLeft(find.text('Brand new')).dy, lessThan(tester.getTopLeft(find.text('Read earlier')).dy));
      await tester.tap(find.byKey(const ValueKey('notif-item-new')));
      await tester.pumpAndSettle();
      expect(repo.markCalls, [
        ['new'],
      ]);
      expect(routes, ['/my-membership']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('fits a small phone with large text', (tester) async {
      final repo = FakeNotifications([
        for (var i = 0; i < 6; i++) notif('n$i', title: 'A fairly long notification title number $i', body: 'And a body that is long enough to wrap onto a few lines on a small screen, number $i.'),
      ]);
      await _open(tester, repo, size: const Size(320, 640), page: true);
      expect(tester.takeException(), isNull);
    });
  });
}
