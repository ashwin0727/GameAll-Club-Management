import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';

/// The five primary destinations. The app has more modules than a bottom bar
/// can hold legibly, so the rest live behind [AppTab.more] rather than being
/// crammed in — the same reason the design's own bar stops at five.
enum AppTab { home, bookings, memberships, more, profile }

const _tabs = <({AppTab tab, IconData icon, IconData activeIcon, String label, String? route})>[
  (tab: AppTab.home, icon: Icons.home_outlined, activeIcon: Icons.home_rounded, label: 'Home', route: AppRoutes.dashboard),
  (
    tab: AppTab.bookings,
    icon: Icons.calendar_month_outlined,
    activeIcon: Icons.calendar_month_rounded,
    label: 'Bookings',
    route: AppRoutes.bookings,
  ),
  (
    tab: AppTab.memberships,
    icon: Icons.workspace_premium_outlined,
    activeIcon: Icons.workspace_premium_rounded,
    label: 'Members',
    route: AppRoutes.memberships,
  ),
  (tab: AppTab.more, icon: Icons.grid_view_outlined, activeIcon: Icons.grid_view_rounded, label: 'More', route: null),
  (tab: AppTab.profile, icon: Icons.person_outline, activeIcon: Icons.person_rounded, label: 'Profile', route: AppRoutes.profile),
];

/// Everything that doesn't fit the bar, reached through "More".
const _moreDestinations = <({IconData icon, String label, String route})>[
  (icon: Icons.event_available_outlined, label: 'Guest Bookings', route: AppRoutes.guestBookings),
  (icon: Icons.groups_outlined, label: 'Guest Players', route: AppRoutes.guests),
  (icon: Icons.event_repeat_outlined, label: 'Membership Sessions', route: AppRoutes.membershipSessions),
  (icon: Icons.account_balance_wallet_outlined, label: 'Finance', route: AppRoutes.finance),
  (icon: Icons.currency_rupee, label: 'Refunds', route: AppRoutes.refunds),
];

/// Persistent bottom navigation, shown on every top-level destination.
///
/// Tabs use `go` rather than `push` so switching sections replaces the
/// location instead of stacking screens the owner then has to back out of.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({super.key, required this.current});

  final AppTab current;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      decoration: BoxDecoration(
        color: tokens.surface1,
        border: Border(top: BorderSide(color: tokens.borderColor)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, -4))],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final t in _tabs)
                _NavItem(
                  icon: t.tab == current ? t.activeIcon : t.icon,
                  label: t.label,
                  selected: t.tab == current,
                  onTap: () {
                    if (t.tab == current && t.tab != AppTab.more) return;
                    if (t.route == null) {
                      _showMore(context);
                    } else {
                      context.go(t.route!);
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  static void _showMore(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.sm),
              child: Text('More', style: Theme.of(sheetContext).textTheme.titleMedium),
            ),
            for (final d in _moreDestinations)
              ListTile(
                leading: Icon(d.icon),
                title: Text(d.label),
                onTap: () {
                  Navigator.pop(sheetContext);
                  context.go(d.route);
                },
              ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.icon, required this.label, required this.selected, required this.onTap});

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                color: selected ? tokens.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Icon(icon, size: 21, color: selected ? tokens.onPrimary : tokens.textSecondary),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? tokens.textPrimary : tokens.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}