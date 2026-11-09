import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/gameall_buttons.dart';
import '../../my_bookings/application/guest_bookings_providers.dart';
import '../../my_bookings/domain/guest_booking.dart';
import '../../player_home/application/player_home_controller.dart';
import '../application/profile_providers.dart';
import 'profile_widgets.dart';

/// Activity & History: what the player has done on GameAll: the four totals, recent court bookings, active memberships and coaching,
/// and where tournaments are.
class ActivityHistoryPage extends ConsumerWidget {
  const ActivityHistoryPage({super.key, required this.onNavigate});

  /// Opens a route (the shell's own), after closing this page.
  final void Function(String route) onNavigate;

  void _go(BuildContext context, String route) {
    Navigator.of(context).pop();
    onNavigate(route);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final stats = ref.watch(profileStatsProvider).value;
    final bookingsAsync = ref.watch(myGuestBookingsProvider);
    final home = ref.watch(playerHomeProvider).value;

    final all = <GuestBooking>[
      ...?bookingsAsync.value?.upcoming,
      ...?bookingsAsync.value?.completed,
      ...?bookingsAsync.value?.cancelled,
    ]..sort((a, b) => b.start.compareTo(a.start));
    final recent = all.take(8).toList();

    Widget tile(IconData icon, String value, String label, String route) =>
        Expanded(
          child: ProfilePanel(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            child: InkWell(
              key: ValueKey('ah-$label'),
              onTap: () => _go(context, route),
              borderRadius: BorderRadius.circular(12),
              child: Column(
                children: [
                  Icon(icon, color: p.highlight),
                  const SizedBox(height: 6),
                  Text(value, style: AppTextStyles.cardHeading(p.primaryText)),
                  Text(label, style: AppTextStyles.support(p.secondaryText)),
                ],
              ),
            ),
          ),
        );

    String n(int? v) => v == null ? '—' : '$v';

    return ProfileSubPage(
      title: 'Activity & History',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Row(
            children: [
              tile(
                Icons.calendar_month_outlined,
                n(stats?.bookings),
                'Bookings',
                AppRoutes.bookings,
              ),
              const SizedBox(width: 10),
              tile(
                Icons.workspace_premium_outlined,
                n(stats?.memberships),
                'Memberships',
                AppRoutes.myMembership,
              ),
              const SizedBox(width: 10),
              tile(
                Icons.school_outlined,
                n(stats?.coaching),
                'Coaching',
                AppRoutes.myCoaching,
              ),
            ],
          ),
          ProfileColumns(
            left: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ProfileSectionTitle('Recent bookings'),
                if (bookingsAsync.isLoading && !bookingsAsync.hasValue)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 30),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (recent.isEmpty)
                  const ProfileEmpty(
                    'No bookings yet. Book a court and it will show up here.',
                    icon: Icons.calendar_month_outlined,
                  )
                else
                  ProfilePanel(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        for (var i = 0; i < recent.length; i++) ...[
                          if (i > 0) const ProfileDivider(),
                          _BookingLine(
                            booking: recent[i],
                            onTap: () => _go(context, AppRoutes.bookings),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
            right: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (home != null &&
                    (home.memberships.isNotEmpty ||
                        home.coaching.isNotEmpty)) ...[
                  const ProfileSectionTitle('Active memberships & coaching'),
                  ProfilePanel(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        for (final m in home.memberships)
                          ProfileMenuRow(
                            icon: Icons.workspace_premium_outlined,
                            title: m.subtitle,
                            subtitle: m.when,
                            onTap: () => _go(context, AppRoutes.myMembership),
                          ),
                        if (home.memberships.isNotEmpty &&
                            home.coaching.isNotEmpty)
                          const ProfileDivider(),
                        for (final c in home.coaching)
                          ProfileMenuRow(
                            icon: Icons.school_outlined,
                            title: c.programName,
                            subtitle: c.venueName,
                            onTap: () => _go(context, AppRoutes.myCoaching),
                          ),
                      ],
                    ),
                  ),
                ],
                const ProfileSectionTitle('Tournaments & stats'),
                ProfilePanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.emoji_events_outlined, color: p.highlight),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Tournaments are played in the GameAll Tournaments app, with their own fixtures, results and player stats.',
                              style: AppTextStyles.support(p.secondaryText),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      GameAllButton.secondary(
                        key: const ValueKey('ah-tournaments'),
                        label: 'Open Tournaments',
                        icon: Icons.arrow_forward_rounded,
                        onPressed: () => _go(context, AppRoutes.tournaments),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BookingLine extends StatelessWidget {
  const _BookingLine({required this.booking, required this.onTap});

  final GuestBooking booking;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final b = booking;
    final cancelled = b.status.toLowerCase().contains('cancel');
    final upcoming = !cancelled && b.end.isAfter(DateTime.now());
    final tone = cancelled
        ? AppColors.danger
        : (upcoming ? AppColors.cyan : AppColors.success);
    final label = cancelled
        ? 'Cancelled'
        : (upcoming ? 'Upcoming' : 'Completed');
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    b.venue.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.cardHeading(p.primaryText)
                        .copyWith(fontSize: 15),
                  ),
                  Text(
                    '${shortDate(b.start)}  ·  ${timeRange(b.start, b.end)}'
                    '${b.sport == null ? '' : '  ·  ${b.sport}'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.support(p.secondaryText),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: tone.withValues(alpha: 0.16),
              ),
              child: Text(
                label,
                style: AppTextStyles.meta(tone).copyWith(fontSize: 11.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
