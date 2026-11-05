import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/gameall_buttons.dart';
import '../application/venues_providers.dart';
import '../domain/venue.dart';
import 'no_venues_state.dart';

/// The body of any page whose content depends on the picked city. While the venues load it shows a spinner; if there are none
/// it shows [NoVenuesState]; otherwise it builds the page's own content with the venues of that city.
class LocationAwareBody extends ConsumerWidget {
  const LocationAwareBody({super.key, required this.builder, this.kind = VenueKind.venues});

  /// Which list this page needs (all venues, those with membership plans, those with coaching).
  final VenueKind kind;

  final Widget Function(BuildContext context, List<Venue> venues) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final venues = ref.watch(venuesForSelectedCityProvider(kind));
    final p = context.palette;
    return venues.when(
      skipLoadingOnReload: false,
      data: (list) =>
          list.isEmpty ? NoVenuesState(kind: kind) : builder(context, list),
      loading: () => Center(
        child: SizedBox(
          key: const ValueKey('venues-loading'),
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 3, color: p.highlight),
        ),
      ),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            key: const ValueKey('venues-error'),
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined, size: 40, color: p.secondaryText),
              const SizedBox(height: 14),
              Text(
                "We couldn't load venues just now.",
                textAlign: TextAlign.center,
                style: AppTextStyles.body(p.primaryText),
              ),
              const SizedBox(height: 16),
              GameAllButton.secondary(
                label: 'Try again',
                onPressed: () => ref.invalidate(venuesForSelectedCityProvider(kind)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
