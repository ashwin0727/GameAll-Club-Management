import 'package:flutter/material.dart';

import '../../core/routing/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../venues/domain/venue.dart';
import '../venues/presentation/coaching_page.dart';
import '../venues/presentation/memberships_page.dart';
import 'coming_soon_page.dart';

/// The page for a route. Memberships and Coaching are venue lists (like Venues) filtered to venues that have created a plan or a
/// programme; everything else is a [ComingSoonPage]. [embedded] is true inside the shell (the brand bar is above, no back button);
/// otherwise the page opens on its own with a back button. [onNavigate] opens another route (the shell passes its own).
Widget playerPageForRoute(String route, {bool embedded = false, void Function(String route)? onNavigate}) {
  final kind = switch (route) {
    AppRoutes.memberships => VenueKind.memberships,
    AppRoutes.coaching => VenueKind.coaching,
    _ => null,
  };
  if (kind == null) return ComingSoonPage.forRoute(route, embedded: embedded);

  return Builder(
    builder: (context) {
      void open(String r) => onNavigate != null ? onNavigate(r) : Navigator.of(context).pushNamed(r);
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
