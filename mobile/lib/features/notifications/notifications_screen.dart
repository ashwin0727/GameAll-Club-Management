import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/app_notification.dart';
import '../../shared/widgets/states.dart';
import 'notification_providers.dart';
import 'push_service.dart';

IconData _iconFor(String kind) {
  if (kind.startsWith('guest_booking')) return Icons.event_available_outlined;
  if (kind.startsWith('membership')) return Icons.card_membership_outlined;
  if (kind.startsWith('coaching')) return Icons.school_outlined;
  if (kind == 'monthly_report') return Icons.insights_outlined;
  return Icons.notifications_none_rounded;
}

bool _isProblem(String kind) => kind.contains('failed') || kind.contains('not_renewed');

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'Just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  if (d.inDays < 7) return '${d.inDays} d ago';
  return '${t.day}/${t.month}/${t.year}';
}

/// The person's notifications, newest first. Opening one marks it read and goes to the screen it is about.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(notificationsProvider);
    ref.invalidate(unreadNotificationsProvider);
    await ref.read(notificationsProvider.future);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(notificationsProvider);
    final hasUnread = items.maybeWhen(data: (l) => l.any((n) => !n.isRead), orElse: () => false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (hasUnread)
            TextButton(
              onPressed: () async {
                await ref.read(notificationRepositoryProvider).markRead();
                await _refresh(ref);
              },
              child: const Text('Mark all read'),
            ),
        ],
      ),
      body: SafeArea(
        child: items.when(
          loading: () => const LoadingView(),
          error: (e, _) => ErrorView(message: 'Could not load notifications.', onRetry: () => ref.invalidate(notificationsProvider)),
          data: (list) => list.isEmpty
              ? const EmptyStateView(
                  icon: Icons.notifications_none_rounded,
                  title: 'No notifications yet',
                  message: 'Bookings starting soon, new memberships, payments and monthly reports will show up here.',
                )
              : RefreshIndicator(
                  onRefresh: () => _refresh(ref),
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => Divider(height: 1, color: context.tokens.borderColor),
                    itemBuilder: (context, i) => _Tile(
                      n: list[i],
                      onTap: () async {
                        final n = list[i];
                        if (!n.isRead) {
                          await ref.read(notificationRepositoryProvider).markRead([n.id]);
                          ref.invalidate(notificationsProvider);
                          ref.invalidate(unreadNotificationsProvider);
                        }
                        if (context.mounted) context.push(notificationTarget(n.kind));
                      },
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.n, required this.onTap});

  final AppNotification n;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final accent = _isProblem(n.kind) ? tokens.destructive : tokens.primary;
    return InkWell(
      onTap: onTap,
      child: Container(
        color: n.isRead ? null : tokens.primary.withValues(alpha: 0.06),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Icon(_iconFor(n.kind), color: accent, size: 20),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(n.title,
                            style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: n.isRead ? FontWeight.w500 : FontWeight.w700)),
                      ),
                      Text(_ago(n.createdAt), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: tokens.textSecondary)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(n.body, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: tokens.textSecondary)),
                ],
              ),
            ),
            if (!n.isRead)
              Padding(
                padding: const EdgeInsets.only(left: AppSpacing.sm, top: 6),
                child: Container(width: 8, height: 8, decoration: BoxDecoration(color: tokens.primary, shape: BoxShape.circle)),
              ),
          ],
        ),
      ),
    );
  }
}
