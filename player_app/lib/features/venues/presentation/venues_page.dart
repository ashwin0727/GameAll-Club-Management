import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/hover_scope.dart';
import '../../../core/widgets/pressable.dart';
import '../../../core/widgets/reveal.dart';
import '../../player_home/application/player_home_controller.dart';
import '../domain/venue.dart';
import 'location_aware_body.dart';
import 'section_scaffold.dart';

/// "Venues" / "Explore": the venues in the city the player picked, or the no-venues message when there are none.
class VenuesPage extends ConsumerWidget {
  const VenuesPage({super.key, required this.onNavigate});

  final void Function(String route) onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final city = cityOf(ref.watch(selectedCityProvider));
    return SectionScaffold(
      title: 'Venues',
      subtitle: 'Near you in $city',
      child: LocationAwareBody(
        builder: (context, venues) => Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                AppDimensions.screenPadding,
                12,
                AppDimensions.screenPadding,
                24,
              ),
              itemCount: venues.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: AppDimensions.cardSpacing),
              itemBuilder: (context, i) => Reveal(
                delay: Duration(milliseconds: 35 * (i < 6 ? i : 6)),
                child: VenueCard(
                  venue: venues[i],
                  onTap: () => onNavigate(AppRoutes.guestBooking),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class VenueCard extends StatelessWidget {
  const VenueCard({super.key, required this.venue, required this.onTap});

  final Venue venue;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final radius = AppDimensions.cardBorderRadius;
    final logo = venue.logoUrl;
    final fallback = Container(
      color: p.elevated,
      alignment: Alignment.center,
      child: Text(
        venue.initials,
        style: AppTextStyles.cardHeading(p.highlight).copyWith(fontSize: 20),
      ),
    );
    return Semantics(
      button: true,
      label: '${venue.name}, ${venue.place}',
      child: ExcludeSemantics(
        child: Pressable(
          onTap: onTap,
          borderRadius: radius,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: radius,
              border: Border.all(color: p.border),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: 64,
                    height: 64,
                    child: logo == null
                        ? fallback
                        : Image.network(
                            logo,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => fallback,
                          ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      HoverText(
                        venue.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.cardHeading(p.primaryText)
                            .copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: 14,
                            color: p.secondaryText,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              venue.place,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.support(p.secondaryText),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final sport in venue.sports.take(4))
                            _Chip(label: sport, color: p.highlight),
                          _Chip(
                            label: venue.courtCount == 1
                                ? '1 court'
                                : '${venue.courtCount} courts',
                            color: AppColors.violet,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 18,
                  color: p.secondaryText,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(label, style: AppTextStyles.meta(color)),
  );
}
