import 'package:flutter/material.dart';

import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/date_format.dart';
import '../../../../core/widgets/pressable.dart';
import '../../domain/player_dashboard_models.dart';
import '../../domain/player_home_models.dart';

/// The pieces of the signed-in player's Home page (the "after login" design): the three summary cards, the schedule
/// and quick actions. Everything is built from [PlayerHomeData], so a player with several memberships or enrolments sees all of the
/// active ones, and one with none sees a plain invitation to start.

/// A bordered panel with a title row, used by the schedule and quick actions.
class DashboardPanel extends StatelessWidget {
  const DashboardPanel({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

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
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(
              AppColors.blue.withValues(alpha: p.isDark ? 0.07 : 0.03),
              p.surface,
            ),
            p.surface,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 24, color: p.highlight),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: AppTextStyles.sectionHeading(p.primaryText)
                      .copyWith(fontSize: 18),
                ),
              ),
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
    final words = name
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    final initials = words.isEmpty
        ? '?'
        : (words.length == 1 ? words.first[0] : words.first[0] + words.last[0])
              .toUpperCase();
    final size = large ? 76.0 : 56.0;
    return Row(
      children: [
        Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: AppColors.brandGradient,
            border: Border.all(color: p.border, width: 2),
          ),
          child: Text(
            initials,
            style: AppTextStyles.sectionHeading(Colors.white)
                .copyWith(fontSize: large ? 26 : 20),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Welcome back,',
                style: AppTextStyles.body(p.primaryText)
                    .copyWith(fontWeight: FontWeight.w600),
              ),
              // The wave is an icon from the bundled icon font, not the 👋 emoji: the web build downloads its emoji font late (or never,
              // on a slow or blocked network), so a refresh showed an empty box next to the name.
              Row(
                children: [
                  Flexible(
                    child: Text(
                      name.isEmpty ? 'there' : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.greeting(p.primaryText)
                          .copyWith(fontSize: large ? 34 : 24),
                    ),
                  ),
                  SizedBox(width: large ? 10 : 8),
                  Icon(
                    Icons.waving_hand_rounded,
                    key: const ValueKey('welcome-wave'),
                    size: large ? 30 : 22,
                    color: const Color(0xFFFFC857),
                  ),
                ],
              ),
              Text(
                'Your play, training and bookings at a glance.',
                style: AppTextStyles.support(p.secondaryText),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Membership, Coaching and Guest Bookings: one card each. [vertical] stacks them (phone); otherwise they sit side by side.
class DashboardSummaryCards extends StatelessWidget {
  const DashboardSummaryCards({
    super.key,
    required this.data,
    required this.onNavigate,
    this.vertical = false,
  });

  final PlayerHomeData data;
  final RouteCallback onNavigate;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    // an unpaid item is shown, but tagged instead of being called Active / Enrolled
    final membershipIncomplete = data.memberships.any(
      (m) => m.paymentIncomplete,
    );
    final coachingIncomplete = data.coaching.any((c) => c.paymentIncomplete);
    // Where each card goes: the player's own page once they have one, the search for it (the venues that offer it) until then.
    final hasMembership =
        data.hasActiveMembership || data.memberships.isNotEmpty;
    final hasCoaching = data.hasActiveCoaching || data.coaching.isNotEmpty;
    final hasGuest = data.hasBookingHistory || data.guestBookings.count > 0;
    final cards = [
      _SummaryCard(
        compact: vertical,
        key: const ValueKey('summary-membership'),
        title: 'Membership',
        icon: Icons.workspace_premium_outlined,
        tint: AppColors.blue,
        badge: !hasMembership
            ? null
            : (membershipIncomplete ? 'Payment Incomplete' : 'Active'),
        badgeWarning: membershipIncomplete,
        lines: [for (final m in data.memberships) (m.subtitle, m.when)],
        emptyTitle: 'No active membership',
        emptyLine: 'Explore memberships near you',
        onTap: () => onNavigate(
          !hasMembership ? AppRoutes.memberships : AppRoutes.myMembership,
        ),
      ),
      _SummaryCard(
        compact: vertical,
        key: const ValueKey('summary-coaching'),
        title: 'Coaching',
        icon: Icons.school_outlined,
        tint: AppColors.violet,
        badge: !hasCoaching
            ? null
            : (coachingIncomplete ? 'Payment Incomplete' : 'Enrolled'),
        badgeWarning: coachingIncomplete,
        lines: [
          for (final c in data.coaching)
            (
              c.programName,
              c.nextSession == null
                  ? c.venueName
                  : '${friendlyDate(c.nextSession!, DateTime.now())}  ·  ${timeRange(c.nextSession!, c.nextSessionEnd ?? c.nextSession!)}',
            ),
        ],
        emptyTitle: 'No active coaching',
        emptyLine: 'Find coaching near you',
        onTap: () => onNavigate(
          !hasCoaching ? AppRoutes.coaching : AppRoutes.myCoaching,
        ),
      ),
      _SummaryCard(
        compact: vertical,
        key: const ValueKey('summary-guest'),
        title: 'Guest Bookings',
        icon: Icons.calendar_month_outlined,
        tint: AppColors.cyan,
        badge: data.guestBookings.count == 0
            ? null
            : '${data.guestBookings.count}',
        lines: [
          if (data.guestBookings.nextStart != null)
            (
              'Upcoming bookings',
              'Next: ${shortDate(data.guestBookings.nextStart!)}  ·  ${time12(data.guestBookings.nextStart!)}',
            ),
        ],
        emptyTitle: 'No guest bookings',
        emptyLine: 'Book a court in seconds',
        onTap: () =>
            onNavigate(!hasGuest ? AppRoutes.guestBooking : AppRoutes.bookings),
      ),
    ];
    if (vertical) {
      return Column(
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            cards[i],
          ],
        ],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(width: 18),
            Expanded(child: cards[i]),
          ],
        ],
      ),
    );
  }
}

/// One of the three service cards on Home (Membership, Coaching, Guest Bookings): a soft tinted panel with an icon tile, the title and
/// its live status ("Active", "Payment Incomplete", a count), what the player has (or an invitation to start), and an arrow.
/// There is no outline: depth comes from the tint, a faint top highlight and a soft shadow, so every card has the same quiet edge.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    super.key,
    required this.title,
    required this.icon,
    required this.tint,
    required this.badge,
    this.badgeWarning = false,
    required this.lines,
    required this.emptyTitle,
    required this.emptyLine,
    required this.onTap,
    this.compact = false,
  });

  final String title;
  final IconData icon;
  final Color tint;
  final String? badge;

  /// The tag is a warning (amber), not a status (green): "Payment Incomplete".
  final bool badgeWarning;

  /// (heading, detail) per active item. Two are shown; the rest are counted.
  final List<(String, String)> lines;
  final String emptyTitle;
  final String emptyLine;
  final VoidCallback onTap;

  /// Phone: a tighter card (smaller icon, one item and its detail, less padding) so the three cards take little room.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tone = badgeWarning ? AppColors.warning : AppColors.success;
    final toneText = badgeWarning
        ? (p.isDark ? AppColors.warning : const Color(0xFF9A5B00))
        : (p.isDark ? AppColors.success : const Color(0xFF138A5B));
    const radius = BorderRadius.all(Radius.circular(22));
    final shown = lines.take(compact ? 1 : 2).toList();
    final more = lines.length - shown.length;

    final chip = badge == null
        ? null
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: tone.withValues(alpha: p.isDark ? 0.16 : 0.12),
            ),
            child: Text(
              badge!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.meta(toneText).copyWith(
                fontSize: 12,
                fontWeight: badgeWarning ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          );

    return Semantics(
      button: true,
      label: title,
      child: ExcludeSemantics(
        child: Pressable(
          onTap: onTap,
          borderRadius: radius,
          child: Container(
            constraints: BoxConstraints(minHeight: compact ? 0 : 92),
            padding: compact
                ? const EdgeInsets.fromLTRB(14, 12, 8, 12)
                : const EdgeInsets.fromLTRB(16, 16, 12, 16),
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.alphaBlend(
                    tint.withValues(alpha: p.isDark ? 0.20 : 0.10),
                    p.surface,
                  ),
                  Color.alphaBlend(
                    tint.withValues(alpha: p.isDark ? 0.05 : 0.02),
                    p.surface,
                  ),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: p.isDark ? 0.32 : 0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            // a 1 px light edge on the top only: it reads as a soft highlight, not an outline
            foregroundDecoration: BoxDecoration(
              borderRadius: radius,
              border: Border(
                top: BorderSide(
                  color: Colors.white.withValues(alpha: p.isDark ? 0.07 : 0.5),
                ),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: compact ? 42 : 50,
                  height: compact ? 42 : 50,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [tint, Color.lerp(tint, Colors.black, 0.25)!],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: tint.withValues(alpha: 0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(icon, size: compact ? 22 : 26, color: Colors.white),
                ),
                SizedBox(width: compact ? 12 : 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            title,
                            style: AppTextStyles.cardHeading(p.primaryText)
                                .copyWith(fontSize: 17),
                          ),
                          ?chip,
                          if (compact && more > 0)
                            Text(
                              '+$more more',
                              style: AppTextStyles.meta(p.highlight),
                            ),
                        ],
                      ),
                      SizedBox(height: compact ? 3 : 6),
                      if (shown.isEmpty) ...[
                        Text(
                          emptyTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.body(
                            p.primaryText,
                          ).copyWith(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          emptyLine,
                          maxLines: compact ? 1 : 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.support(p.secondaryText),
                        ),
                      ] else
                        for (var i = 0; i < shown.length; i++) ...[
                          if (i > 0) const SizedBox(height: 8),
                          Text(
                            shown[i].$1,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.body(p.primaryText).copyWith(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            shown[i].$2,
                            maxLines: compact ? 1 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.support(p.secondaryText),
                          ),
                        ],
                      if (more > 0 && !compact) ...[
                        const SizedBox(height: 6),
                        Text(
                          '+$more more',
                          style: AppTextStyles.meta(p.highlight),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.chevron_right_rounded,
                  color: p.secondaryText,
                  size: 26,
                ),
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
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Nothing scheduled in the next 7 days.',
                key: const ValueKey('schedule-empty'),
                style: AppTextStyles.body(p.secondaryText),
              ),
            )
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
    final dayShort = (day == 'Today' || day == 'Tomorrow')
        ? day
        : shortDate(item.startTime).split(',').first;
    final where = [
      ?item.courtName,
      item.venueName,
    ].where((s) => s.isNotEmpty).join('  ·  ');
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: AppColors.success.withValues(alpha: 0.16),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.4)),
      ),
      child: Text(
        item.statusLabel,
        style: AppTextStyles.meta(
          p.isDark ? AppColors.success : const Color(0xFF138A5B),
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, box) {
        // A narrow card (a phone) drops the separate date column: the date joins the time line and the status goes underneath.
        final compact = box.maxWidth < 420;
        final icon = Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(_kindIcon(item.kind), color: color, size: 22),
        );
        return Container(
          padding: const EdgeInsets.fromLTRB(0, 10, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: p.isDark ? p.background.withValues(alpha: 0.35) : p.elevated,
            border: Border.all(color: p.border),
          ),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 40,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              if (!compact)
                SizedBox(
                  width: 82,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dayShort,
                        style: AppTextStyles.body(p.primaryText)
                            .copyWith(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        shortDate(item.startTime),
                        style: AppTextStyles.meta(p.secondaryText),
                      ),
                    ],
                  ),
                ),
              icon,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body(p.primaryText)
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      compact
                          ? '$dayShort  ·  ${timeRange(item.startTime, item.endTime)}'
                          : timeRange(item.startTime, item.endTime),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.meta(p.secondaryText),
                    ),
                    if (where.isNotEmpty)
                      Text(
                        where,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.meta(p.mutedText),
                      ),
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
