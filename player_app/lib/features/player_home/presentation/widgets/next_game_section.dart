import 'package:flutter/material.dart';

import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/date_format.dart';
import '../../../../core/widgets/gameall_buttons.dart';
import '../../../../core/widgets/hover_scope.dart';
import '../../../../core/widgets/pressable.dart';
import '../../../../core/widgets/sport_icon.dart';
import '../../domain/player_home_models.dart';

/// "Your Next Game": the nearest confirmed booking, or an invitation to book.
class NextGameSection extends StatelessWidget {
  const NextGameSection({
    super.key,
    required this.next,
    required this.onNavigate,
    this.now,
  });

  final NextGame next;
  final RouteCallback onNavigate;

  /// For tests; the real clock otherwise.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Your Next Game',
                style: AppTextStyles.sectionHeading(p.primaryText),
              ),
            ),
            if (next.kind == NextGameKind.upcoming)
              Pressable(
                onTap: () => onNavigate(AppRoutes.bookings),
                borderRadius: BorderRadius.circular(12),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Center(
                      child: HoverText(
                        next.moreCount > 0
                            ? 'View All (${next.moreCount + 1})'
                            : 'View All',
                        style: AppTextStyles.button(p.highlight),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        switch (next.kind) {
          NextGameKind.upcoming => _BookingCard(
            booking: next.booking!,
            now: now ?? DateTime.now(),
            onTap: () => onNavigate(AppRoutes.bookings),
          ),
          NextGameKind.readyForNext => _InviteCard(
            key: const ValueKey('next-game-ready'),
            title: 'Ready for your next game?',
            message: 'Pick a court and a time that suits you.',
            onBook: () => onNavigate(AppRoutes.guestBooking),
          ),
          NextGameKind.empty => _InviteCard(
            key: const ValueKey('next-game-empty'),
            title: 'No bookings yet.',
            message: 'Find a court and get your game started.',
            onBook: () => onNavigate(AppRoutes.guestBooking),
          ),
        },
      ],
    );
  }
}

class _BookingCard extends StatelessWidget {
  const _BookingCard({
    required this.booking,
    required this.now,
    required this.onTap,
  });

  final UpcomingBooking booking;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final detail = [
      if (booking.sportName != null) booking.sportName!,
      if (booking.courtName != null) booking.courtName!,
    ].join(' · ');
    return Semantics(
      container: true,
      label:
          '${booking.venueName}, ${friendlyDate(booking.startTime, now)}, ${timeRange(booking.startTime, booking.endTime)}',
      child: Material(
        color: p.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppDimensions.cardBorderRadius,
          side: BorderSide(color: p.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _Thumb(url: booking.venueLogoUrl),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              booking.venueName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.cardHeading(p.primaryText),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const _StatusChip(label: 'Confirmed'),
                        ],
                      ),
                      if (detail.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.support(p.secondaryText),
                        ),
                      ],
                      const SizedBox(height: 6),
                      _IconLine(
                        icon: Icons.calendar_today_rounded,
                        text:
                            friendlyDate(booking.startTime, now) == 'Today' ||
                                friendlyDate(booking.startTime, now) ==
                                    'Tomorrow'
                            ? '${friendlyDate(booking.startTime, now)} · ${shortDate(booking.startTime)}'
                            : shortDate(booking.startTime),
                      ),
                      const SizedBox(height: 2),
                      _IconLine(
                        icon: Icons.schedule_rounded,
                        text: timeRange(booking.startTime, booking.endTime),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IconLine extends StatelessWidget {
  const _IconLine({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      children: [
        Icon(icon, size: 14, color: p.secondaryText),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.support(p.secondaryText),
          ),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: AppTextStyles.meta(AppColors.success)),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fallback = Container(
      color: p.elevated,
      alignment: Alignment.center,
      child: CorkIcon(color: p.highlight, size: 28),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 76,
        height: 76,
        child: url == null || url!.isEmpty
            ? fallback
            : Image.network(
                url!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

class _InviteCard extends StatelessWidget {
  const _InviteCard({
    super.key,
    required this.title,
    required this.message,
    required this.onBook,
  });

  final String title;
  final String message;
  final VoidCallback onBook;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppDimensions.cardBorderRadius,
        border: Border.all(color: p.border),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: p.elevated,
            ),
            child: CorkIcon(color: p.highlight, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.cardHeading(p.primaryText)),
                const SizedBox(height: 2),
                Text(message, style: AppTextStyles.support(p.secondaryText)),
                const SizedBox(height: 12),
                GameAllButton.gradient(
                  label: 'Book a Court',
                  icon: Icons.arrow_forward_rounded,
                  onPressed: onBook,
                  height: 44,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
