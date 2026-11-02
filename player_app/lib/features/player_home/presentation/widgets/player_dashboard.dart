import 'package:flutter/material.dart';

import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/date_format.dart';
import '../../../../core/widgets/hover_scope.dart';
import '../../../../core/widgets/pressable.dart';
import '../../domain/player_dashboard_models.dart';
import '../../domain/player_home_models.dart';

/// The pieces of the signed-in player's Home page (the "after login" design): the three summary cards, the schedule
/// and quick actions. Everything is built from [PlayerHomeData], so a player with several memberships or enrolments sees all of the
/// active ones, and one with none sees a plain invitation to start.

/// A bordered panel with a title row, used by the schedule and quick actions.
class DashboardPanel extends StatelessWidget {
  const DashboardPanel({super.key, required this.title, required this.icon, required this.child, this.trailing});

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
        border: Border.all(color: p.border),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color.alphaBlend(AppColors.blue.withValues(alpha: p.isDark ? 0.07 : 0.03), p.surface), p.surface]),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 24, color: p.highlight),
              const SizedBox(width: 12),
              Expanded(child: Text(title, style: AppTextStyles.sectionHeading(p.primaryText).copyWith(fontSize: 18))),
              ?trailing,
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

/// "Welcome back, / Alex 👋 / Your play, training and bookings at a glance." with the player's initials.
class DashboardWelcome extends StatelessWidget {
  const DashboardWelcome({super.key, required this.data, this.large = true});

  final PlayerHomeData data;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final name = (data.fullName ?? '').trim();
    final words = name.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final initials = words.isEmpty ? '?' : (words.length == 1 ? words.first[0] : words.first[0] + words.last[0]).toUpperCase();
    final size = large ? 76.0 : 56.0;
    return Row(
      children: [
        Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, gradient: AppColors.brandGradient, border: Border.all(color: p.border, width: 2)),
          child: Text(initials, style: AppTextStyles.sectionHeading(Colors.white).copyWith(fontSize: large ? 26 : 20)),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Welcome back,', style: AppTextStyles.body(p.primaryText).copyWith(fontWeight: FontWeight.w600)),
              Text('${name.isEmpty ? 'there' : name} 👋', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.greeting(p.primaryText).copyWith(fontSize: large ? 34 : 24)),
              Text('Your play, training and bookings at a glance.', style: AppTextStyles.support(p.secondaryText)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Membership, Coaching and Guest Bookings: one card each. [vertical] stacks them (phone); otherwise they sit side by side.
class DashboardSummaryCards extends StatelessWidget {
  const DashboardSummaryCards({super.key, required this.data, required this.onNavigate, this.vertical = false});

  final PlayerHomeData data;
  final RouteCallback onNavigate;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _SummaryCard(
        key: const ValueKey('summary-membership'),
        title: 'Membership',
        icon: Icons.workspace_premium_outlined,
        tint: AppColors.blue,
        badge: data.memberships.isEmpty ? null : 'Active',
        lines: [for (final m in data.memberships) (m.subtitle, m.when)],
        emptyTitle: 'No active membership',
        emptyLine: 'Explore memberships near you',
        onTap: () => onNavigate(data.memberships.isEmpty ? AppRoutes.memberships : AppRoutes.myMembership),
      ),
      _SummaryCard(
        key: const ValueKey('summary-coaching'),
        title: 'Coaching',
        icon: Icons.school_outlined,
        tint: AppColors.violet,
        badge: data.coaching.isEmpty ? null : 'Enrolled',
        lines: [
          for (final c in data.coaching)
            (c.programName, c.nextSession == null ? c.venueName : '${friendlyDate(c.nextSession!, DateTime.now())}  ·  ${timeRange(c.nextSession!, c.nextSessionEnd ?? c.nextSession!)}'),
        ],
        emptyTitle: 'No active coaching',
        emptyLine: 'Find coaching near you',
        onTap: () => onNavigate(data.coaching.isEmpty ? AppRoutes.coaching : AppRoutes.myCoaching),
      ),
      _SummaryCard(
        key: const ValueKey('summary-guest'),
        title: 'Guest Bookings',
        icon: Icons.calendar_month_outlined,
        tint: AppColors.cyan,
        badge: data.guestBookings.count == 0 ? null : '${data.guestBookings.count}',
        lines: [
          if (data.guestBookings.nextStart != null)
            (
              'Upcoming bookings',
              'Next: ${shortDate(data.guestBookings.nextStart!)}  ·  ${time12(data.guestBookings.nextStart!)}',
            ),
        ],
        emptyTitle: 'No guest bookings',
        emptyLine: 'Book a court in seconds',
        onTap: () => onNavigate(data.guestBookings.count == 0 ? AppRoutes.guestBooking : AppRoutes.bookings),
      ),
    ];
    if (vertical) {
      return Column(children: [for (var i = 0; i < cards.length; i++) ...[if (i > 0) const SizedBox(height: 12), cards[i]]]);
    }
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (var i = 0; i < cards.length; i++) ...[if (i > 0) const SizedBox(width: 18), Expanded(child: cards[i])]]),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({super.key, required this.title, required this.icon, required this.tint, required this.badge, required this.lines, required this.emptyTitle, required this.emptyLine, required this.onTap});

  final String title;
  final IconData icon;
  final Color tint;
  final String? badge;

  /// (heading, detail) per active item. Two are shown; the rest are counted.
  final List<(String, String)> lines;
  final String emptyTitle;
  final String emptyLine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final radius = BorderRadius.circular(AppDimensions.cardRadius);
    final shown = lines.take(2).toList();
    final more = lines.length - shown.length;
    return Semantics(
      button: true,
      label: title,
      child: ExcludeSemantics(
        child: Pressable(
          onTap: onTap,
          borderRadius: radius,
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: Color.lerp(p.border, tint, 0.45)!),
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color.alphaBlend(tint.withValues(alpha: p.isDark ? 0.30 : 0.12), p.surface), Color.alphaBlend(tint.withValues(alpha: p.isDark ? 0.08 : 0.03), p.surface)]),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 42, color: p.isDark ? Colors.white : tint),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(child: Text(title, style: AppTextStyles.cardHeading(p.primaryText).copyWith(fontSize: 17))),
                          if (badge != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), color: AppColors.success.withValues(alpha: 0.18), border: Border.all(color: AppColors.success.withValues(alpha: 0.5))),
                              child: Text(badge!, style: AppTextStyles.meta(p.isDark ? AppColors.success : const Color(0xFF138A5B))),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (shown.isEmpty) ...[
                        Text(emptyTitle, style: AppTextStyles.body(p.primaryText).copyWith(fontWeight: FontWeight.w600)),
                        Text(emptyLine, style: AppTextStyles.support(p.secondaryText)),
                      ] else
                        for (var i = 0; i < shown.length; i++) ...[
                          if (i > 0) const SizedBox(height: 8),
                          Text(shown[i].$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.body(p.primaryText).copyWith(fontWeight: FontWeight.w600)),
                          Text(shown[i].$2, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTextStyles.support(p.secondaryText)),
                        ],
                      if (more > 0) ...[
                        const SizedBox(height: 8),
                        Text('+$more more', style: AppTextStyles.meta(p.highlight)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded, color: p.secondaryText, size: 26),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Color _kindColor(ScheduleKind k) => switch (k) {
      ScheduleKind.membership => AppColors.violet,
      ScheduleKind.coaching => AppColors.blue,
      ScheduleKind.guest => AppColors.cyan,
    };

IconData _kindIcon(ScheduleKind k) => switch (k) {
      ScheduleKind.membership => Icons.workspace_premium_outlined,
      ScheduleKind.coaching => Icons.school_outlined,
      ScheduleKind.guest => Icons.calendar_month_outlined,
    };

/// "Your Schedule": the next seven days.
class ScheduleCard extends StatelessWidget {
  const ScheduleCard({super.key, required this.items, this.now});

  final List<ScheduleItem> items;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final clock = now ?? DateTime.now();
    return DashboardPanel(
      title: 'Your Schedule',
      icon: Icons.calendar_month_outlined,
      child: items.isEmpty
          ? Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('Nothing scheduled in the next 7 days.', key: const ValueKey('schedule-empty'), style: AppTextStyles.body(p.secondaryText)))
          : Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  _ScheduleRow(item: items[i], now: clock),
                ],
              ],
            ),
    );
  }
}

class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow({required this.item, required this.now});
  final ScheduleItem item;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = _kindColor(item.kind);
    final day = friendlyDate(item.startTime, now);
    final dayShort = (day == 'Today' || day == 'Tomorrow') ? day : shortDate(item.startTime).split(',').first;
    final where = [?item.courtName, item.venueName].where((s) => s.isNotEmpty).join('  ·  ');
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), color: AppColors.success.withValues(alpha: 0.16), border: Border.all(color: AppColors.success.withValues(alpha: 0.4))),
      child: Text(item.statusLabel, style: AppTextStyles.meta(p.isDark ? AppColors.success : const Color(0xFF138A5B))),
    );
    return LayoutBuilder(
      builder: (context, box) {
        // A narrow card (a phone) drops the separate date column: the date joins the time line and the status goes underneath.
        final compact = box.maxWidth < 420;
        final icon = Container(width: 40, height: 40, decoration: BoxDecoration(color: color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(12)), child: Icon(_kindIcon(item.kind), color: color, size: 22));
        return Container(
          padding: const EdgeInsets.fromLTRB(0, 10, 12, 10),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: p.isDark ? p.background.withValues(alpha: 0.35) : p.elevated, border: Border.all(color: p.border)),
          child: Row(
            children: [
              Container(width: 3, height: 40, margin: const EdgeInsets.only(right: 12), decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
              if (!compact)
                SizedBox(
                  width: 82,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(dayShort, style: AppTextStyles.body(p.primaryText).copyWith(fontWeight: FontWeight.w600)),
                      Text(shortDate(item.startTime), style: AppTextStyles.meta(p.secondaryText)),
                    ],
                  ),
                ),
              icon,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.body(p.primaryText).copyWith(fontWeight: FontWeight.w600)),
                    Text(compact ? '$dayShort  ·  ${timeRange(item.startTime, item.endTime)}' : timeRange(item.startTime, item.endTime), maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTextStyles.meta(p.secondaryText)),
                    if (where.isNotEmpty) Text(where, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.meta(p.mutedText)),
                    if (compact) ...[const SizedBox(height: 6), pill],
                  ],
                ),
              ),
              if (!compact) ...[const SizedBox(width: 8), pill],
            ],
          ),
        );
      },
    );
  }
}

/// "Quick Actions": five shortcuts.
class QuickActionsCard extends StatelessWidget {
  const QuickActionsCard({super.key, required this.onNavigate});

  final RouteCallback onNavigate;

  @override
  Widget build(BuildContext context) {
    final actions = [
      ('Book a Court', Icons.calendar_month_outlined, AppRoutes.guestBooking, AppColors.cyan),
      ('View Membership', Icons.workspace_premium_outlined, AppRoutes.myMembership, AppColors.violet),
      ('My Coaching', Icons.school_outlined, AppRoutes.myCoaching, AppColors.blue),
      ('Tournaments', Icons.emoji_events_outlined, AppRoutes.tournaments, AppColors.purple),
      ('My Activity', Icons.bar_chart_rounded, AppRoutes.bookings, AppColors.cyan),
    ];
    return DashboardPanel(
      title: 'Quick Actions',
      icon: Icons.bolt_rounded,
      child: LayoutBuilder(
        builder: (context, box) {
          final cols = box.maxWidth >= 460 ? 5 : 3;
          const gap = 10.0;
          final w = (box.maxWidth - gap * (cols - 1)) / cols;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [for (final a in actions) SizedBox(width: w, child: _QuickAction(label: a.$1, icon: a.$2, color: a.$4, onTap: () => onNavigate(a.$3)))],
          );
        },
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.label, required this.icon, required this.color, required this.onTap});
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final radius = BorderRadius.circular(14);
    return Semantics(
      button: true,
      label: label,
      child: ExcludeSemantics(
        child: Pressable(
          onTap: onTap,
          borderRadius: radius,
          child: Container(
            height: 92,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(borderRadius: radius, border: Border.all(color: Color.lerp(p.border, color, 0.35)!), color: p.isDark ? p.background.withValues(alpha: 0.35) : p.elevated),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 28),
                const SizedBox(height: 8),
                HoverText(label, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTextStyles.meta(p.primaryText).copyWith(fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
