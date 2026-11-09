import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/pressable.dart';
import '../application/notification_providers.dart';
import '../domain/player_notification.dart';

/// The bell was pressed. On a wide window (the web) the unread messages drop down as a small popup, with no page of their own; on a
/// phone they open as a page.
void openNotifications(BuildContext context, {required void Function(String route) onNavigate}) {
  if (MediaQuery.sizeOf(context).width >= AppDimensions.desktopBreakpoint) {
    showNotificationsPopup(context, onNavigate: onNavigate);
  } else {
    onNavigate(AppRoutes.notifications);
  }
}

/// One message: an icon for what it is about, the title, the text and how long ago. An unread one is brighter with a dot.
class NotificationTile extends StatelessWidget {
  const NotificationTile({super.key, required this.notification, required this.onTap});

  final PlayerNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final n = notification;
    final tone = n.isFailure ? AppColors.danger : (n.isSuccess ? AppColors.success : p.highlight);
    return Pressable(
      key: ValueKey('notif-item-${n.id}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(shape: BoxShape.circle, color: tone.withValues(alpha: 0.14)),
              child: Icon(n.icon, size: 20, color: tone),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          n.title,
                          style: AppTextStyles.body(n.isRead ? p.secondaryText : p.primaryText).copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (!n.isRead)
                        Container(
                          key: ValueKey('notif-dot-${n.id}'),
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(left: 8),
                          decoration: BoxDecoration(shape: BoxShape.circle, color: p.highlight),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(n.body, style: AppTextStyles.support(n.isRead ? p.mutedText : p.secondaryText)),
                  const SizedBox(height: 5),
                  Text(n.ago(DateTime.now()), style: AppTextStyles.meta(p.mutedText)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      key: const ValueKey('notif-empty'),
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(shape: BoxShape.circle, color: p.isDark ? const Color(0xFF14213F) : p.secondaryBackground),
            child: Icon(Icons.notifications_none_rounded, color: p.highlight),
          ),
          const SizedBox(height: 12),
          Text("You're all caught up", style: AppTextStyles.body(p.primaryText).copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            'Booking reminders and payment updates will show up here.',
            textAlign: TextAlign.center,
            style: AppTextStyles.support(p.secondaryText),
          ),
        ],
      ),
    );
  }
}

/// The unread messages as a popup under the bell (wide window). Reading one (tapping it) takes it off the list.
Future<void> showNotificationsPopup(BuildContext context, {required void Function(String route) onNavigate}) {
  final width = MediaQuery.sizeOf(context).width;
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close notifications',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (dialog, _, _) => SafeArea(
      child: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: EdgeInsets.only(top: 78, right: AppDimensions.desktopSidePadding(width)),
          child: _NotificationsPopup(onNavigate: onNavigate),
        ),
      ),
    ),
    transitionBuilder: (context, animation, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, -0.03), end: Offset.zero).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
        child: child,
      ),
    ),
  );
}

class _NotificationsPopup extends ConsumerWidget {
  const _NotificationsPopup({required this.onNavigate});

  final void Function(String route) onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final state = ref.watch(notificationsControllerProvider);
    final controller = ref.read(notificationsControllerProvider.notifier);
    final maxHeight = (MediaQuery.sizeOf(context).height - 120).clamp(240.0, 560.0);
    return Material(
      key: const ValueKey('notif-popup'),
      color: Colors.transparent,
      child: Container(
        width: 400,
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: BoxDecoration(
          color: p.isDark ? const Color(0xFF10213B) : p.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: p.border),
          boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 10))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
              child: Row(
                children: [
                  Expanded(child: Text('Notifications', style: AppTextStyles.cardHeading(p.primaryText))),
                  if (state.unread.isNotEmpty)
                    TextButton(
                      key: const ValueKey('notif-mark-all'),
                      onPressed: controller.markAllRead,
                      child: const Text('Mark all as read'),
                    ),
                ],
              ),
            ),
            Divider(height: 1, color: p.border),
            Flexible(
              child: !state.loaded
                  ? const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
                  : state.unread.isEmpty
                  ? const _Empty()
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.all(6),
                      itemCount: state.unread.length,
                      separatorBuilder: (_, _) => Divider(height: 1, color: p.border.withValues(alpha: 0.5)),
                      itemBuilder: (context, i) {
                        final n = state.unread[i];
                        return NotificationTile(
                          notification: n,
                          onTap: () {
                            controller.markRead([n.id]);
                            Navigator.of(context).pop();
                            final route = n.route;
                            if (route != null && route.isNotEmpty) onNavigate(route);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The phone's Notifications page: the last 30 days, unread first (brighter, with a dot), the read ones dimmed.
class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key, required this.onNavigate});

  final void Function(String route) onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final async = ref.watch(allNotificationsProvider);
    final controller = ref.read(notificationsControllerProvider.notifier);
    final items = async.value ?? const <PlayerNotification>[];
    final sorted = [...items]..sort((a, b) {
      if (a.isRead != b.isRead) return a.isRead ? 1 : -1;
      return b.createdAt.compareTo(a.createdAt);
    });
    final anyUnread = items.any((n) => !n.isRead);

    Future<void> reload() async {
      ref.invalidate(allNotificationsProvider);
      await controller.refresh();
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Notifications', style: AppTextStyles.cardHeading(p.primaryText)),
        actions: [
          if (anyUnread)
            TextButton(
              key: const ValueKey('notif-mark-all'),
              onPressed: () async {
                await controller.markAllRead();
                ref.invalidate(allNotificationsProvider);
              },
              child: const Text('Mark all as read'),
            ),
        ],
      ),
      body: SafeArea(
        child: async.isLoading && !async.hasValue
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : RefreshIndicator(
                onRefresh: reload,
                child: sorted.isEmpty
                    ? ListView(children: const [SizedBox(height: 60), _Empty()])
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                        itemCount: sorted.length,
                        separatorBuilder: (_, _) => Divider(height: 1, color: p.border.withValues(alpha: 0.5)),
                        itemBuilder: (context, i) {
                          final n = sorted[i];
                          return NotificationTile(
                            notification: n,
                            onTap: () async {
                              final route = n.route;
                              if (!n.isRead) {
                                controller.markRead([n.id]);
                                ref.invalidate(allNotificationsProvider);
                              }
                              if (route != null && route.isNotEmpty) {
                                Navigator.of(context).maybePop();
                                onNavigate(route);
                              }
                            },
                          );
                        },
                      ),
              ),
      ),
    );
  }
}

/// Keeps the bell fresh: looks for new messages every 30 seconds while the app is open, and when it comes back to the front.
/// Placed once at the root of the app.
class NotificationPoller extends ConsumerStatefulWidget {
  const NotificationPoller({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<NotificationPoller> createState() => _NotificationPollerState();
}

class _NotificationPollerState extends ConsumerState<NotificationPoller> with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(notificationPollInterval, (_) => _look());
  }

  void _look() {
    if (mounted) ref.read(notificationsControllerProvider.notifier).refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _look();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
