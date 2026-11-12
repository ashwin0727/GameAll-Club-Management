import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/external_links.dart';
import '../../../core/widgets/gameall_buttons.dart';
import '../../../core/widgets/pressable.dart';
import '../../../core/widgets/reveal.dart';
import '../../../core/widgets/sport_icon.dart';
import '../../player_home/presentation/widgets/player_header.dart';
import '../application/venues_providers.dart';
import '../domain/venue.dart';
import '../domain/venue_detail.dart';
import 'sport_style.dart';
import 'venue_gallery.dart';

/// One venue's page. On a wide window (the web) it sits inside the shell under the brand bar, with a breadcrumb; on a phone it is a
/// full page with its own top bar. Both are built from the same data (`get_public_venue`).
class VenueDetailPage extends ConsumerWidget {
  const VenueDetailPage({
    super.key,
    required this.venueId,
    required this.onNavigate,
    this.embedded = false,
  });

  final String venueId;
  final void Function(String route) onNavigate;

  /// True inside the shell on a wide window (the brand bar is already above).
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final async = ref.watch(venueDetailProvider(venueId));
    final wide =
        MediaQuery.sizeOf(context).width >= AppDimensions.desktopBreakpoint;

    Widget body;
    if (async.isLoading && !async.hasValue) {
      body = const Center(
        child: SizedBox(
          key: ValueKey('venue-loading'),
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      );
    } else if (async.hasError && !async.hasValue) {
      body = _Message(
        icon: Icons.cloud_off_outlined,
        title: "We couldn't load this venue",
        message: 'Check your connection and try again.',
        action: GameAllButton.secondary(
          label: 'Try again',
          onPressed: () => ref.invalidate(venueDetailProvider(venueId)),
        ),
      );
    } else if (async.value == null) {
      body = _Message(
        key: const ValueKey('venue-missing'),
        icon: Icons.storefront_outlined,
        title: "This venue isn't available",
        message:
            'It may have closed or moved. Have a look at the other venues.',
        action: GameAllButton.secondary(
          label: 'See venues',
          onPressed: () => onNavigate(AppRoutes.explore),
        ),
      );
    } else {
      final venue = async.value!;
      body = wide
          ? _WideBody(venue: venue, onNavigate: onNavigate)
          : _PhoneBody(venue: venue, onNavigate: onNavigate);
    }

    if (embedded) return SafeArea(child: body);
    return Scaffold(
      backgroundColor: p.background,
      body: SafeArea(child: body),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: p.highlight),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextStyles.sectionHeading(p.primaryText),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTextStyles.body(p.secondaryText),
            ),
            const SizedBox(height: 18),
            action,
          ],
        ),
      ),
    );
  }
}

// ── shared pieces ──────────────────────────────────────────────────────────

IconData _amenityIcon(String label) => switch (label) {
  'Free Parking' || 'Car Parking' => Icons.local_parking_rounded,
  'Two-Wheeler Parking' => Icons.two_wheeler_rounded,
  'Changing Rooms' || 'Changing Room' => Icons.checkroom_outlined,
  'Toilets / Rest Room' || 'Restroom' => Icons.wc_rounded,
  'Cafeteria' || 'Cafeteria / Food' => Icons.local_cafe_outlined,
  'Shower' => Icons.shower_outlined,
  'Drinking Water' => Icons.water_drop_outlined,
  'Seating Area' => Icons.event_seat_outlined,
  'Wi-Fi' => Icons.wifi_rounded,
  'Lockers' => Icons.lock_outline_rounded,
  'First Aid' => Icons.medical_services_outlined,
  'Equipment Rental' => Icons.sports_tennis_rounded,
  _ => Icons.check_circle_outline_rounded,
};

IconData _courtAmenityIcon(String label) => switch (label) {
  'AC' => Icons.ac_unit_rounded,
  'Shower' => Icons.shower_outlined,
  'Locker' => Icons.lock_outline_rounded,
  _ => Icons.check_circle_outline_rounded,
};

/// "Courts": for each sport, every court with its type, surface, lighting and amenities, as the owner set them up.
class _CourtsSection extends StatelessWidget {
  const _CourtsSection({required this.venue});

  final VenueDetail venue;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final detailed = [for (final c in venue.courts) if (c.hasDetails) c];
    if (detailed.isEmpty) return const SizedBox.shrink();

    Widget chip(String label, {Color? color}) {
      final c = color ?? p.secondaryText;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: c.withValues(alpha: p.isDark ? 0.18 : 0.10),
          border: Border.all(color: c.withValues(alpha: 0.45)),
        ),
        child: Text(
          label,
          style: AppTextStyles.meta(p.isDark ? Colors.white : c)
              .copyWith(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      );
    }

    final groups = <VenueSport, List<VenueCourt>>{};
    for (final s in venue.sports) {
      final courts = [for (final c in venue.courts) if (c.sportId == s.id) c];
      if (courts.isNotEmpty) groups[s] = courts;
    }

    return Column(
      key: const ValueKey('venue-courts'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Courts',
          style: AppTextStyles.sectionHeading(p.primaryText).copyWith(fontSize: 18),
        ),
        const SizedBox(height: 12),
        for (final entry in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8, top: 4),
            child: Row(
              children: [
                SportIcon(entry.key.name, size: 18, color: p.primaryText),
                const SizedBox(width: 8),
                Text(
                  '${entry.key.name} (${entry.value.length})',
                  style: AppTextStyles.body(p.primaryText).copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          for (final court in entry.value)
            Container(
              key: ValueKey('court-${court.id}'),
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: p.border),
                color: p.surface.withValues(alpha: p.isDark ? 0.6 : 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(court.name, style: AppTextStyles.body(p.primaryText).copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (court.type != null)
                        chip(court.type == VenueType.indoor ? 'Indoor' : 'Outdoor', color: AppColors.violet),
                      if (court.surface != null) chip(court.surface!),
                      if (court.lightingLabel != null) chip(court.lightingLabel!),
                      for (final a in court.amenityLabels)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_courtAmenityIcon(a), size: 15, color: p.secondaryText),
                            const SizedBox(width: 4),
                            Text(a, style: AppTextStyles.meta(p.secondaryText).copyWith(fontSize: 12)),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

/// "Badminton", "Football", ... then Indoor / Outdoor as chips under the title.
class _Chips extends StatelessWidget {
  const _Chips({required this.venue, this.max = 3});

  final VenueDetail venue;
  final int max;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final names = [for (final s in venue.sports) s.name];
    final type = venue.venueType == null
        ? null
        : (venue.venueType == VenueType.indoor ? 'Indoor' : 'Outdoor');
    final all = [...names, ?type];
    final shown = all.take(max).toList();
    final more = all.length - shown.length;
    Widget chip(String label) {
      final isType = label == 'Indoor' || label == 'Outdoor';
      final color = isType ? AppColors.violet : sportColor(label);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: color.withValues(alpha: p.isDark ? 0.18 : 0.12),
          border: Border.all(color: color.withValues(alpha: 0.6)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isType) ...[
              SportIcon(
                label,
                size: 18,
                color: p.isDark ? Colors.white : color,
              ),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: AppTextStyles.body(p.isDark ? Colors.white : color)
                  .copyWith(fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final c in shown) chip(c),
        if (more > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: p.border),
            ),
            child: Text(
              '+$more',
              style: AppTextStyles.body(p.secondaryText)
                  .copyWith(fontSize: 13.5),
            ),
          ),
      ],
    );
  }
}

class _Place extends StatelessWidget {
  const _Place(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.location_on_outlined, size: 17, color: p.highlight),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            key: const ValueKey('venue-place'),
            style: AppTextStyles.body(p.secondaryText),
          ),
        ),
      ],
    );
  }
}

/// A short list of everything the venue offers, opened from "View All".
void _showFacilities(BuildContext context, VenueDetail venue) {
  final p = context.palette;
  final all = venue.facilityCatalogue;
  final on = {...venue.facilityLabels};
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: p.surface,
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Facilities',
              style: AppTextStyles.sectionHeading(p.primaryText),
            ),
            const SizedBox(height: 12),
            for (final a in all)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      _amenityIcon(a),
                      size: 22,
                      color: on.contains(a) ? p.highlight : p.mutedText,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        a,
                        style: AppTextStyles.body(
                          on.contains(a) ? p.primaryText : p.mutedText,
                        ),
                      ),
                    ),
                    Icon(
                      on.contains(a)
                          ? Icons.check_circle_rounded
                          : Icons.remove_circle_outline_rounded,
                      size: 20,
                      color: on.contains(a) ? AppColors.success : p.mutedText,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

// ── wide (web) ─────────────────────────────────────────────────────────────

class _WideBody extends ConsumerWidget {
  const _WideBody({required this.venue, required this.onNavigate});

  final VenueDetail venue;
  final void Function(String route) onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final width = MediaQuery.sizeOf(context).width;
    final side = AppDimensions.desktopSidePadding(width);
    final mainSport = venue.sports.isEmpty ? null : venue.sports.first.name;
    final amenities = venue.facilityLabels;

    Widget action(
      String label,
      IconData icon,
      VoidCallback onTap, {
      Color? color,
      Key? key,
    }) => Pressable(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: (color ?? p.highlight).withValues(alpha: 0.7),
          ),
          color: (color ?? p.highlight).withValues(alpha: 0.08),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 19, color: color ?? p.highlight),
            const SizedBox(width: 10),
            Text(label, style: AppTextStyles.button(p.primaryText)),
            const SizedBox(width: 8),
            Icon(Icons.arrow_forward_rounded, size: 17, color: p.primaryText),
          ],
        ),
      ),
    );

    return SingleChildScrollView(
      key: const ValueKey('venue-scroll'),
      padding: EdgeInsets.fromLTRB(side, 12, side, 56),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Reveal(
            delay: const Duration(milliseconds: 40),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 10,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              venue.name,
                              key: const ValueKey('venue-title'),
                              style: AppTextStyles.desktopHeroHeading(
                                p.primaryText,
                              ).copyWith(fontSize: 42, height: 1.1),
                            ),
                          ),
                          if (venue.locationVerified) ...[
                            const SizedBox(width: 12),
                            Tooltip(
                              message: 'Verified venue',
                              child: Icon(
                                Icons.verified_rounded,
                                key: const ValueKey('venue-verified'),
                                size: 28,
                                color: AppColors.violet,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 12),
                      _Place(venue.place),
                      const SizedBox(height: 18),
                      _Chips(venue: venue),
                      if (venue.description != null) ...[
                        const SizedBox(height: 18),
                        Text(
                          venue.description!,
                          key: const ValueKey('venue-description'),
                          style: AppTextStyles.body(p.secondaryText)
                              .copyWith(fontSize: 16, height: 1.5),
                        ),
                      ],
                      const SizedBox(height: 24),
                      Wrap(
                        spacing: 14,
                        runSpacing: 14,
                        children: [
                          action(
                            'Book a Court',
                            Icons.calendar_month_outlined,
                            () => onNavigate(AppRoutes.bookPath(venue.id)),
                            key: const ValueKey('action-book'),
                          ),
                          if (venue.hasMemberships)
                            action(
                              'Memberships',
                              Icons.workspace_premium_outlined,
                              () => onNavigate(AppRoutes.enrollPath(venue.id)),
                              color: AppColors.violet,
                              key: const ValueKey('action-memberships'),
                            ),
                          if (venue.hasCoaching)
                            action(
                              'Coaching',
                              Icons.school_outlined,
                              () => onNavigate(
                                AppRoutes.coachingEnrollPath(venue.id),
                              ),
                              color: AppColors.violet,
                              key: const ValueKey('action-coaching'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 36),
                Expanded(
                  flex: 12,
                  child: VenueGallery(
                    venueId: venue.id,
                    photos: venue.photos,
                    sport: mainSport,
                    thumbnails: true,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
          // courts, hours and facilities in one bar
          Reveal(
            delay: const Duration(milliseconds: 90),
            child: Container(
              key: const ValueKey('venue-stats'),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: p.border),
                color: p.surface.withValues(alpha: p.isDark ? 0.6 : 1),
              ),
              child: Row(
                children: [
                  _Stat(
                    icon: Icons.grid_view_rounded,
                    label: venue.courtCount == 1
                        ? '1 Court'
                        : '${venue.courtCount} Courts',
                  ),
                  if (venue.hoursLabel != null) ...[
                    const _Divider(),
                    _Stat(
                      icon: Icons.schedule_rounded,
                      label: venue.hoursLabel!,
                    ),
                  ],
                  if (venue.playersLabel != null) ...[
                    const _Divider(),
                    _Stat(
                      key: const ValueKey('stat-players'),
                      icon: Icons.groups_outlined,
                      label: venue.playersLabel!,
                      bold: true,
                    ),
                  ],
                  if (amenities.isNotEmpty) ...[
                    const _Divider(),
                    for (final a in amenities.take(4))
                      Expanded(
                        child: _Stat(
                          icon: _amenityIcon(a),
                          label: a,
                          compact: true,
                        ),
                      ),
                    const SizedBox(width: 10),
                    Pressable(
                      key: const ValueKey('view-all-facilities'),
                      onTap: () => _showFacilities(context, venue),
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: p.border),
                        ),
                        child: Text(
                          'View All',
                          style: AppTextStyles.button(p.primaryText)
                              .copyWith(fontSize: 13),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (venue.courts.any((c) => c.hasDetails)) ...[
            const SizedBox(height: 30),
            _CourtsSection(venue: venue),
          ],
          if (venue.hasMemberships || venue.hasCoaching) ...[
            const SizedBox(height: 34),
            Reveal(
              delay: const Duration(milliseconds: 130),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 24,
                    decoration: BoxDecoration(
                      color: AppColors.cyan,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Explore at this venue',
                    style: AppTextStyles.sectionHeading(p.primaryText)
                        .copyWith(fontSize: 22),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Reveal(
              delay: const Duration(milliseconds: 160),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (venue.hasMemberships)
                      Expanded(
                        child: _ExploreCard(
                          key: const ValueKey('explore-memberships'),
                          title: 'Memberships',
                          subtitle: 'Play more, save more',
                          cta: venue.cheapestPlan == null
                              ? 'View plans'
                              : 'Plans from ${rupees(venue.cheapestPlan!.priceInr)} / ${venue.cheapestPlan!.period}',
                          link: 'Explore plans',
                          icon: Icons.workspace_premium_outlined,
                          image: 'assets/images/hero_membership.webp',
                          color: AppColors.violet,
                          onTap: () =>
                              onNavigate(AppRoutes.enrollPath(venue.id)),
                        ),
                      ),
                    if (venue.hasMemberships && venue.hasCoaching)
                      const SizedBox(width: 24),
                    if (venue.hasCoaching)
                      Expanded(
                        child: _ExploreCard(
                          key: const ValueKey('explore-coaching'),
                          title: 'Coaching',
                          subtitle: 'Train with certified coaches',
                          cta: venue.cheapestProgramPrice == null
                              ? 'View programs'
                              : 'Programs from ${rupees(venue.cheapestProgramPrice!)}',
                          link: 'Meet coaches',
                          icon: Icons.school_outlined,
                          image: 'assets/images/hero_coaching.webp',
                          color: AppColors.cyan,
                          onTap: () => onNavigate(
                            AppRoutes.coachingEnrollPath(venue.id),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    super.key,
    required this.icon,
    required this.label,
    this.compact = false,
    this.bold = false,
  });

  final IconData icon;
  final String label;
  final bool compact;

  /// The heavier weight the design gives "50+ Players".
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final child = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: compact ? 24 : 28,
          color: p.primaryText.withValues(alpha: 0.9),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.body(p.primaryText).copyWith(
            fontSize: compact ? 13.5 : 15,
            fontWeight: bold
                ? FontWeight.w700
                : (compact ? FontWeight.w500 : FontWeight.w600),
          ),
        ),
      ],
    );
    return compact ? child : Expanded(child: child);
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 52,
    margin: const EdgeInsets.symmetric(horizontal: 12),
    color: context.palette.border,
  );
}

class _ExploreCard extends StatelessWidget {
  const _ExploreCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.cta,
    required this.link,
    required this.icon,
    required this.image,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String cta;
  final String link;
  final IconData icon;
  final String image;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Pressable(
      onTap: onTap,
      scale: 0.99,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: color.withValues(alpha: 0.6)),
          gradient: LinearGradient(
            colors: [
              Color.alphaBlend(color.withValues(alpha: 0.30), p.surface),
              Color.alphaBlend(color.withValues(alpha: 0.10), p.surface),
            ],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: 260,
              child: ExcludeSemantics(
                child: ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (r) => const LinearGradient(
                    colors: [Color(0x00000000), Color(0xCC000000)],
                    stops: [0.0, 0.6],
                  ).createShader(r),
                  child: Image.asset(
                    image,
                    fit: BoxFit.cover,
                    alignment: Alignment.centerRight,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(26),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(
                        icon,
                        size: 40,
                        color: p.isDark ? Colors.white : color,
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: AppTextStyles.sectionHeading(p.primaryText)
                                .copyWith(fontSize: 24),
                          ),
                          Text(
                            subtitle,
                            style: AppTextStyles.body(
                              p.primaryText.withValues(alpha: 0.85),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(26),
                          border: Border.all(
                            color: p.primaryText.withValues(alpha: 0.35),
                          ),
                          color: Colors.black.withValues(alpha: 0.22),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              cta,
                              style: AppTextStyles.button(p.primaryText)
                                  .copyWith(fontSize: 15),
                            ),
                            const SizedBox(width: 10),
                            Icon(
                              Icons.arrow_forward_rounded,
                              size: 18,
                              color: p.primaryText,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 20),
                      Text(
                        link,
                        style: AppTextStyles.body(
                          p.primaryText.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── phone ──────────────────────────────────────────────────────────────────

class _PhoneBody extends ConsumerWidget {
  const _PhoneBody({required this.venue, required this.onNavigate});

  final VenueDetail venue;
  final void Function(String route) onNavigate;

  void _openTabs(BuildContext context, int tab) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VenueActionsPage(
          venue: venue,
          initialTab: tab,
          onNavigate: onNavigate,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final mainSport = venue.sports.isEmpty ? null : venue.sports.first.name;
    final amenities = venue.facilityLabels;

    Widget tile(
      String label,
      IconData icon,
      VoidCallback onTap, {
      Color? color,
      Key? key,
    }) => Expanded(
      child: Pressable(
        key: key,
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          // at least this tall, and taller when larger text needs the room
          constraints: const BoxConstraints(minHeight: 104),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: (color ?? p.highlight).withValues(alpha: 0.55),
            ),
            color: (color ?? p.highlight).withValues(alpha: 0.07),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 24, color: color ?? p.highlight),
              const SizedBox(height: 14),
              Text(
                label,
                style: AppTextStyles.body(p.primaryText)
                    .copyWith(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Icon(
                Icons.arrow_forward_rounded,
                size: 16,
                color: p.secondaryText,
              ),
            ],
          ),
        ),
      ),
    );

    return SingleChildScrollView(
      key: const ValueKey('venue-scroll'),
      padding: const EdgeInsets.fromLTRB(
        AppDimensions.screenPadding,
        4,
        AppDimensions.screenPadding,
        40,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 52,
            child: Row(
              children: [
                IconButton(
                  key: const ValueKey('venue-back'),
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: Icon(Icons.arrow_back_rounded, color: p.primaryText),
                ),
                const Expanded(child: Center(child: GameAllLogo(height: 28))),
                const SizedBox(width: 48),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Reveal(
            dy: 8,
            child: VenueGallery(
              venueId: venue.id,
              photos: venue.photos,
              sport: mainSport,
              arrows: false,
              counter: true,
              verifiedBadge: venue.locationVerified,
              aspectRatio: 1.6,
              borderRadius: 22,
            ),
          ),
          const SizedBox(height: 18),
          Reveal(
            delay: const Duration(milliseconds: 40),
            child: Text(
              venue.name,
              key: const ValueKey('venue-title'),
              style: AppTextStyles.desktopHeroHeading(p.primaryText)
                  .copyWith(fontSize: 30, height: 1.1),
            ),
          ),
          const SizedBox(height: 8),
          Reveal(
            delay: const Duration(milliseconds: 60),
            child: Align(
              alignment: Alignment.centerLeft,
              child: _Place(venue.place),
            ),
          ),
          const SizedBox(height: 14),
          Reveal(
            delay: const Duration(milliseconds: 80),
            child: _Chips(venue: venue, max: 2),
          ),
          if (venue.description != null) ...[
            const SizedBox(height: 14),
            Text(
              venue.description!,
              key: const ValueKey('venue-description'),
              style: AppTextStyles.body(p.secondaryText),
            ),
          ],
          const SizedBox(height: 18),
          Reveal(
            delay: const Duration(milliseconds: 100),
            child: Row(
              children: [
                tile(
                  'Book Court',
                  Icons.calendar_month_outlined,
                  () => onNavigate(AppRoutes.bookPath(venue.id)),
                  key: const ValueKey('tile-book'),
                ),
                if (venue.hasMemberships) ...[
                  const SizedBox(width: 10),
                  tile(
                    'Memberships',
                    Icons.workspace_premium_outlined,
                    () => _openTabs(context, 1),
                    color: AppColors.violet,
                    key: const ValueKey('tile-memberships'),
                  ),
                ],
                if (venue.hasCoaching) ...[
                  const SizedBox(width: 10),
                  tile(
                    'Coaching',
                    Icons.school_outlined,
                    () => _openTabs(context, 2),
                    color: AppColors.violet,
                    key: const ValueKey('tile-coaching'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 26),
          Text(
            'At a Glance',
            style: AppTextStyles.sectionHeading(p.primaryText)
                .copyWith(fontSize: 18),
          ),
          const SizedBox(height: 14),
          Row(
            key: const ValueKey('venue-glance'),
            children: [
              _Stat(
                icon: Icons.grid_view_rounded,
                label: venue.courtCount == 1
                    ? '1 Court'
                    : '${venue.courtCount} Courts',
              ),
              if (venue.hoursShort != null) ...[
                const _Divider(),
                _Stat(icon: Icons.schedule_rounded, label: venue.hoursShort!),
              ],
              if (venue.playersLabel != null) ...[
                const _Divider(),
                _Stat(
                  key: const ValueKey('stat-players'),
                  icon: Icons.groups_outlined,
                  label: venue.playersLabel!,
                  bold: true,
                ),
              ],
              if (venue.minCourtPriceInr != null) ...[
                const _Divider(),
                _Stat(
                  icon: Icons.currency_rupee_rounded,
                  label: 'From ${rupees(venue.minCourtPriceInr!)} / hr',
                ),
              ],
            ],
          ),
          if (amenities.isNotEmpty) ...[
            const SizedBox(height: 26),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Facilities',
                    style: AppTextStyles.sectionHeading(p.primaryText)
                        .copyWith(fontSize: 18),
                  ),
                ),
                Pressable(
                  key: const ValueKey('view-all-facilities'),
                  onTap: () => _showFacilities(context, venue),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Text(
                      'View All',
                      style: AppTextStyles.body(p.secondaryText),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                for (final a in amenities.take(4))
                  Expanded(
                    child: Column(
                      children: [
                        Icon(_amenityIcon(a), size: 26, color: p.primaryText),
                        const SizedBox(height: 8),
                        Text(
                          a,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          style: AppTextStyles.meta(p.secondaryText)
                              .copyWith(fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
          if (venue.courts.any((c) => c.hasDetails)) ...[
            const SizedBox(height: 26),
            _CourtsSection(venue: venue),
          ],
          if (venue.address != null) ...[
            const SizedBox(height: 26),
            _LocationCard(venue: venue),
          ],
        ],
      ),
    );
  }
}

class _LocationCard extends ConsumerWidget {
  const _LocationCard({required this.venue});
  final VenueDetail venue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final link = venue.locationUrl;
    return Container(
      key: const ValueKey('venue-location'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.border),
        color: p.surface.withValues(alpha: p.isDark ? 0.6 : 1),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: AppColors.blue.withValues(alpha: 0.18),
            ),
            child: Icon(
              Icons.location_on_rounded,
              color: AppColors.violet,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              venue.address!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.body(p.primaryText)
                  .copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          if (link != null)
            Semantics(
              button: true,
              label: 'Open in Maps',
              child: Pressable(
                key: const ValueKey('open-maps'),
                onTap: () => ref.read(linkOpenerProvider)(Uri.parse(link)),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: const LinearGradient(
                      colors: [AppColors.violet, AppColors.blue],
                    ),
                  ),
                  child: const Icon(
                    Icons.navigation_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The phone's Memberships / Coaching tabs (booking has its own page).
class VenueActionsPage extends ConsumerStatefulWidget {
  const VenueActionsPage({
    super.key,
    required this.venue,
    required this.onNavigate,
    this.initialTab = 0,
  });

  final VenueDetail venue;
  final int initialTab;
  final void Function(String route) onNavigate;

  @override
  ConsumerState<VenueActionsPage> createState() => _VenueActionsPageState();
}

class _VenueActionsPageState extends ConsumerState<VenueActionsPage> {
  late int _tab = widget.initialTab;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final venue = widget.venue;
    final tabs = <(String, int)>[
      if (venue.hasMemberships) ('Memberships', 1),
      if (venue.hasCoaching) ('Coaching', 2),
    ];
    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(
        backgroundColor: p.background,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: Icon(Icons.arrow_back_rounded, color: p.primaryText),
        ),
        title: Text(
          venue.name,
          style: AppTextStyles.cardHeading(p.primaryText),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppDimensions.screenPadding,
            4,
            AppDimensions.screenPadding,
            40,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: p.border),
                  color: p.surface.withValues(alpha: 0.6),
                ),
                child: Row(
                  children: [
                    for (final t in tabs)
                      Expanded(
                        child: Pressable(
                          key: ValueKey('tab-${t.$1}'),
                          onTap: () => setState(() => _tab = t.$2),
                          borderRadius: BorderRadius.circular(20),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            height: 40,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              gradient: _tab == t.$2
                                  ? const LinearGradient(
                                      colors: [
                                        AppColors.violet,
                                        AppColors.purple,
                                      ],
                                    )
                                  : null,
                            ),
                            child: Text(
                              t.$1,
                              style: AppTextStyles.body(
                                _tab == t.$2 ? Colors.white : p.primaryText,
                              ).copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (_tab == 1)
                _OfferList(
                  key: const ValueKey('plans-list'),
                  venue: venue,
                  items: [
                    for (final pl in venue.plans)
                      (pl.name, '${rupees(pl.priceInr)} / ${pl.period}'),
                  ],
                  heading: 'Membership plans',
                  onJoin: () =>
                      widget.onNavigate(AppRoutes.enrollPath(venue.id)),
                )
              else
                _OfferList(
                  key: const ValueKey('programs-list'),
                  venue: venue,
                  items: [
                    for (final pr in venue.programs)
                      (
                        pr.name,
                        [
                          if (pr.level != null) pr.level!,
                          if (pr.priceInr != null)
                            'from ${rupees(pr.priceInr!)}',
                        ].join('  ·  '),
                      ),
                  ],
                  heading: 'Coaching programs',
                  onJoin: () =>
                      widget.onNavigate(AppRoutes.coachingEnrollPath(venue.id)),
                  joinLabel: 'Choose a program & enroll',
                  joinKey: 'join-coaching',
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the venue offers (plans or programs), with a way to call the venue to join.
class _OfferList extends ConsumerWidget {
  const _OfferList({
    super.key,
    required this.venue,
    required this.items,
    required this.heading,
    this.onJoin,
    this.joinLabel = 'Choose a time & join',
    this.joinKey = 'join-membership',
  });

  final VenueDetail venue;
  final List<(String, String)> items;
  final String heading;

  /// Opens the Enroll Membership / Coaching page.
  final VoidCallback? onJoin;
  final String joinLabel;
  final String joinKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(heading, style: AppTextStyles.sectionHeading(p.primaryText)),
        const SizedBox(height: 12),
        for (final i in items)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: p.border),
              color: p.surface.withValues(alpha: p.isDark ? 0.7 : 1),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    i.$1,
                    style: AppTextStyles.cardHeading(p.primaryText),
                  ),
                ),
                if (i.$2.isNotEmpty)
                  Text(i.$2, style: AppTextStyles.body(p.secondaryText)),
              ],
            ),
          ),
        if (onJoin != null) ...[
          const SizedBox(height: 6),
          GameAllButton.gradient(
            key: ValueKey(joinKey),
            label: joinLabel,
            icon: Icons.arrow_forward_rounded,
            expand: true,
            onPressed: onJoin,
          ),
        ],
        if (venue.phone != null) ...[
          const SizedBox(height: 6),
          GameAllButton.gradient(
            key: const ValueKey('call-venue'),
            label: 'Call ${venue.name} to join',
            icon: Icons.call_outlined,
            expand: true,
            onPressed: () =>
                ref.read(linkOpenerProvider)(Uri.parse('tel:${venue.phone}')),
          ),
        ],
      ],
    );
  }
}

/// The venue's own page content without its action buttons (Book a Court / Memberships / Coaching): the photos, name with the verified
/// tick, place, sport chips, description, the courts / hours / players / facilities stats and (on a phone) the location card. The
/// Guest Booking page shows it above the booking steps, so the player sees the same venue they just opened.
class VenueOverview extends ConsumerWidget {
  const VenueOverview({super.key, required this.venue, required this.wide});

  final VenueDetail venue;

  /// The web layout (photos beside the title, one stats bar) or the phone layout (photos on top, "At a Glance", "Facilities").
  final bool wide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final mainSport = venue.sports.isEmpty ? null : venue.sports.first.name;
    final amenities = venue.facilityLabels;

    if (wide) {
      return Column(
        key: const ValueKey('venue-overview'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 10,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            venue.name,
                            key: const ValueKey('venue-title'),
                            style: AppTextStyles.desktopHeroHeading(
                              p.primaryText,
                            ).copyWith(fontSize: 42, height: 1.1),
                          ),
                        ),
                        if (venue.locationVerified) ...[
                          const SizedBox(width: 12),
                          Tooltip(
                            message: 'Verified venue',
                            child: Icon(
                              Icons.verified_rounded,
                              key: const ValueKey('venue-verified'),
                              size: 28,
                              color: AppColors.violet,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),
                    _Place(venue.place),
                    const SizedBox(height: 18),
                    _Chips(venue: venue),
                    if (venue.description != null) ...[
                      const SizedBox(height: 18),
                      Text(
                        venue.description!,
                        key: const ValueKey('venue-description'),
                        style: AppTextStyles.body(p.secondaryText)
                            .copyWith(fontSize: 16, height: 1.5),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 36),
              Expanded(
                flex: 12,
                child: VenueGallery(
                  venueId: venue.id,
                  photos: venue.photos,
                  sport: mainSport,
                  thumbnails: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 30),
          Container(
            key: const ValueKey('venue-stats'),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: p.border),
              color: p.surface.withValues(alpha: p.isDark ? 0.6 : 1),
            ),
            child: Row(
              children: [
                _Stat(
                  icon: Icons.grid_view_rounded,
                  label: venue.courtCount == 1
                      ? '1 Court'
                      : '${venue.courtCount} Courts',
                ),
                if (venue.hoursLabel != null) ...[
                  const _Divider(),
                  _Stat(icon: Icons.schedule_rounded, label: venue.hoursLabel!),
                ],
                if (venue.playersLabel != null) ...[
                  const _Divider(),
                  _Stat(
                    key: const ValueKey('stat-players'),
                    icon: Icons.groups_outlined,
                    label: venue.playersLabel!,
                    bold: true,
                  ),
                ],
                if (amenities.isNotEmpty) ...[
                  const _Divider(),
                  for (final a in amenities.take(4))
                    Expanded(
                      child: _Stat(
                        icon: _amenityIcon(a),
                        label: a,
                        compact: true,
                      ),
                    ),
                  const SizedBox(width: 10),
                  Pressable(
                    key: const ValueKey('view-all-facilities'),
                    onTap: () => _showFacilities(context, venue),
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: p.border),
                      ),
                      child: Text(
                        'View All',
                        style: AppTextStyles.button(p.primaryText)
                            .copyWith(fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (venue.courts.any((c) => c.hasDetails)) ...[
            const SizedBox(height: 26),
            _CourtsSection(venue: venue),
          ],
        ],
      );
    }

    return Column(
      key: const ValueKey('venue-overview'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        VenueGallery(
          venueId: venue.id,
          photos: venue.photos,
          sport: mainSport,
          arrows: false,
          counter: true,
          verifiedBadge: venue.locationVerified,
          aspectRatio: 1.6,
          borderRadius: 22,
        ),
        const SizedBox(height: 18),
        Text(
          venue.name,
          key: const ValueKey('venue-title'),
          style: AppTextStyles.desktopHeroHeading(p.primaryText)
              .copyWith(fontSize: 30, height: 1.1),
        ),
        const SizedBox(height: 8),
        Align(alignment: Alignment.centerLeft, child: _Place(venue.place)),
        const SizedBox(height: 14),
        _Chips(venue: venue, max: 2),
        if (venue.description != null) ...[
          const SizedBox(height: 14),
          Text(
            venue.description!,
            key: const ValueKey('venue-description'),
            style: AppTextStyles.body(p.secondaryText),
          ),
        ],
        const SizedBox(height: 22),
        Text(
          'At a Glance',
          style: AppTextStyles.sectionHeading(p.primaryText)
              .copyWith(fontSize: 18),
        ),
        const SizedBox(height: 14),
        Row(
          key: const ValueKey('venue-glance'),
          children: [
            _Stat(
              icon: Icons.grid_view_rounded,
              label: venue.courtCount == 1
                  ? '1 Court'
                  : '${venue.courtCount} Courts',
            ),
            if (venue.hoursShort != null) ...[
              const _Divider(),
              _Stat(icon: Icons.schedule_rounded, label: venue.hoursShort!),
            ],
            if (venue.playersLabel != null) ...[
              const _Divider(),
              _Stat(
                key: const ValueKey('stat-players'),
                icon: Icons.groups_outlined,
                label: venue.playersLabel!,
                bold: true,
              ),
            ],
            if (venue.minCourtPriceInr != null) ...[
              const _Divider(),
              _Stat(
                icon: Icons.currency_rupee_rounded,
                label: 'From ${rupees(venue.minCourtPriceInr!)} / hr',
              ),
            ],
          ],
        ),
        if (amenities.isNotEmpty) ...[
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Facilities',
                  style: AppTextStyles.sectionHeading(p.primaryText)
                      .copyWith(fontSize: 18),
                ),
              ),
              Pressable(
                key: const ValueKey('view-all-facilities'),
                onTap: () => _showFacilities(context, venue),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Text(
                    'View All',
                    style: AppTextStyles.body(p.secondaryText),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (final a in amenities.take(4))
                Expanded(
                  child: Column(
                    children: [
                      Icon(_amenityIcon(a), size: 26, color: p.primaryText),
                      const SizedBox(height: 8),
                      Text(
                        a,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        style: AppTextStyles.meta(p.secondaryText)
                            .copyWith(fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
        if (venue.courts.any((c) => c.hasDetails)) ...[
          const SizedBox(height: 22),
          _CourtsSection(venue: venue),
        ],
        if (venue.address != null) ...[
          const SizedBox(height: 22),
          _LocationCard(venue: venue),
        ],
      ],
    );
  }
}
