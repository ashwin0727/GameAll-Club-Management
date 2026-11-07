import 'package:flutter/material.dart';

import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../venues/domain/venue.dart';
import '../my_coaching/presentation/my_coaching_page.dart';
import '../my_membership/presentation/my_membership_page.dart';
import '../venues/presentation/coaching_page.dart';
import '../venues/presentation/discover_venues_page.dart';
import '../venues/presentation/memberships_page.dart';
import 'coming_soon_page.dart';

/// The page for a route. Memberships and Coaching are venue lists (like Venues) filtered to venues that have created a plan or a
/// programme; everything else is a [ComingSoonPage]. [embedded] is true inside the shell (the brand bar is above, no back button);
/// otherwise the page opens on its own with a back button. [onNavigate] opens another route (the shell passes its own).
Widget playerPageForRoute(
  String route, {
  bool embedded = false,
  void Function(String route)? onNavigate,
}) {
  // Guest Court Booking starts where the Venues page does: the same venues, search, sport and filters, then a venue's own page and its
  // booking steps. (Home's "Book a Court" / "Find a Court" buttons and the promo card all open this route.)
  if (route == AppRoutes.guestBooking) {
    return Builder(
      builder: (context) {
        void open(String r) => onNavigate != null
            ? onNavigate(r)
            : Navigator.of(context).pushNamed(r);
        final page = DiscoverVenuesPage(onNavigate: open);
        if (embedded) return page;
        return Scaffold(
          appBar: AppBar(
            title: Text(
              'Book a Court',
              style: AppTextStyles.cardHeading(context.palette.primaryText),
            ),
          ),
          body: page,
        );
      },
    );
  }
  // "My Membership": a player with an active membership lands on its details (Home's membership card and the Memberships link open it)
  if (route == AppRoutes.myMembership) {
    return Builder(
      builder: (context) {
        void open(String r) => onNavigate != null
            ? onNavigate(r)
            : Navigator.of(context).pushNamed(r);
        final page = MyMembershipPage(onNavigate: open);
        if (embedded) return page;
        return Scaffold(
          appBar: AppBar(
            title: Text(
              'Membership Details',
              style: AppTextStyles.cardHeading(context.palette.primaryText),
            ),
          ),
          body: page,
        );
      },
    );
  }
  // "My Coaching": a player enrolled in coaching lands on its details (Home's coaching card and the Coaching link open it)
  if (route == AppRoutes.myCoaching) {
    return Builder(
      builder: (context) {
        void open(String r) => onNavigate != null
            ? onNavigate(r)
            : Navigator.of(context).pushNamed(r);
        final page = MyCoachingPage(onNavigate: open);
        if (embedded) return page;
        return Scaffold(
          appBar: AppBar(
            title: Text(
              'My Coaching',
              style: AppTextStyles.cardHeading(context.palette.primaryText),
            ),
          ),
          body: page,
        );
      },
    );
  }
  final kind = switch (route) {
    AppRoutes.memberships => VenueKind.memberships,
    AppRoutes.coaching => VenueKind.coaching,
    _ => null,
  };
  if (kind == null) return ComingSoonPage.forRoute(route, embedded: embedded);

  return Builder(
    builder: (context) {
      void open(String r) => onNavigate != null
          ? onNavigate(r)
          : Navigator.of(context).pushNamed(r);
      // Memberships and Coaching each have their own page (price tiles per length / coach and programme cards, with their own filters)
      final Widget page = kind == VenueKind.memberships
          ? MembershipsPage(onNavigate: open)
          : CoachingPage(onNavigate: open);
      if (embedded) return page;
      return Scaffold(
        appBar: AppBar(
          title: Text(
            kind == VenueKind.memberships ? 'Memberships' : 'Coaching',
            style: AppTextStyles.cardHeading(context.palette.primaryText),
          ),
        ),
        body: page,
      );
    },
  );
}
