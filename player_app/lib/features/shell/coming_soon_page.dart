import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimensions.dart';
import '../../core/theme/app_text_styles.dart';
import '../player_home/application/player_home_controller.dart';
import '../venues/domain/venue.dart';
import '../venues/presentation/location_aware_body.dart';
import '../venues/presentation/section_scaffold.dart';

/// A page for a part of the Player app that is not built yet. Every Home shortcut leads somewhere real, and says so plainly.
class ComingSoonPage extends StatelessWidget {
  const ComingSoonPage({
    super.key,
    required this.title,
    required this.icon,
    required this.message,
    this.embedded = false,
    this.locationBased = false,
  });

  final String title;
  final IconData icon;
  final String message;

  /// True when shown as a tab (no back button), false when pushed as its own page.
  final bool embedded;

  /// True for pages whose content depends on the picked city: with no venues in that city they show the no-venues message (icon and
  /// sentence) instead of this page.
  final bool locationBased;

  /// The page for a route, with a suitable title.
  factory ComingSoonPage.forRoute(String route, {bool embedded = false}) {
    final (title, icon, message) = switch (route) {
      AppRoutes.guestBooking => (
        'Guest Court Booking',
        Icons.event_available_outlined,
        'Find nearby venues, check live slots and book a court.',
      ),
      AppRoutes.memberships => (
        'Memberships',
        Icons.diamond_outlined,
        'Discover memberships at clubs near you.',
      ),
      AppRoutes.myMembership => (
        'My Membership',
        Icons.workspace_premium_rounded,
        'Your membership, renewals and sessions.',
      ),
      AppRoutes.coaching => (
        'Coaching',
        Icons.school_outlined,
        'Find certified coaches and academies.',
      ),
      AppRoutes.myCoaching => (
        'My Coaching',
        Icons.school_outlined,
        'Your coaching programmes and sessions.',
      ),
      AppRoutes.search => (
        'Search',
        Icons.search_rounded,
        'Search venues, sports, memberships and coaching academies.',
      ),
      AppRoutes.notifications => (
        'Notifications',
        Icons.notifications_none_rounded,
        'Booking and payment updates will appear here.',
      ),
      AppRoutes.tournaments => (
        'Tournaments',
        Icons.emoji_events_outlined,
        'No tournaments have been created yet. Tournaments created on GameAll will appear here.',
      ),
      AppRoutes.login => (
        'Login',
        Icons.login_rounded,
        'Sign in to see your bookings, memberships and coaching.',
      ),
      AppRoutes.howItWorks => (
        'How GameAll Works',
        Icons.play_circle_outline_rounded,
        'A short tour of booking, memberships and coaching.',
      ),
      _ => (
        'GameAll',
        Icons.sports_rounded,
        'This part of the app is coming soon.',
      ),
    };
    // Memberships and Coaching have their own pages (see player_pages.dart); Tournaments are created in a separate app and none exist yet.
    const byCity = {AppRoutes.guestBooking, AppRoutes.search};
    return ComingSoonPage(
      title: title,
      icon: icon,
      message: message,
      embedded: embedded,
      locationBased: byCity.contains(route),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget body = locationBased
        ? LocationAwareBody(
            builder: (context, venues) => _content(context, venues.length),
          )
        : _content(context, null);
    if (embedded) {
      // Opened from the brand bar: same frame as Venues (title top left, content centred).
      if (locationBased) {
        return Consumer(
          builder: (context, ref, _) => SectionScaffold(
            title: title,
            subtitle: 'Near you in ${cityOf(ref.watch(selectedCityProvider))}',
            child: body,
          ),
        );
      }
      return SafeArea(child: body);
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(
          title,
          style: AppTextStyles.cardHeading(context.palette.primaryText),
        ),
      ),
      body: body,
    );
  }

  Widget _content(BuildContext context, int? venueCount) {
    final p = context.palette;
    return Consumer(
      builder: (context, ref, _) => _centered(
        context,
        p,
        venueCount == null
            ? null
            : '$venueCount ${venueCount == 1 ? 'venue' : 'venues'} in ${cityOf(ref.watch(selectedCityProvider))}',
      ),
    );
  }

  Widget _centered(BuildContext context, AppPalette p, String? venuesLine) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(AppDimensions.screenPadding * 1.5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: p.surface,
                  border: Border.all(color: p.border),
                ),
                child: Icon(icon, color: p.highlight, size: 34),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                textAlign: TextAlign.center,
                style: AppTextStyles.sectionHeading(p.primaryText),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: AppTextStyles.body(p.secondaryText),
              ),
              if (venuesLine != null) ...[
                const SizedBox(height: 10),
                Text(
                  venuesLine,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.button(p.highlight),
                ),
              ],
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: AppColors.violet.withValues(alpha: 0.16),
                ),
                child: Text(
                  'Coming soon',
                  style: AppTextStyles.meta(
                    p.isDark ? AppColors.purple : AppColors.violet,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
