import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/gameall_buttons.dart';
import '../../../core/widgets/reveal.dart';
import '../../player_home/application/player_home_controller.dart';
import '../../player_home/presentation/widgets/player_search_bar.dart';
import '../domain/venue.dart';

/// What every location-based page shows when no venue has been added for the city the player picked: an icon, one clear sentence
/// that names the city, and a button to pick another city. One widget, so every page says the same thing in the same way.
class NoVenuesState extends ConsumerWidget {
  const NoVenuesState({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final location = ref.watch(selectedCityProvider);
    final city = cityOf(location);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            key: const ValueKey('no-venues'),
            mainAxisSize: MainAxisSize.min,
            children: [
              Reveal(
                dy: 10,
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: p.surface,
                    border: Border.all(color: p.border),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.blue.withValues(
                          alpha: p.isDark ? 0.20 : 0.10,
                        ),
                        blurRadius: 28,
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.location_off_outlined,
                    size: 40,
                    color: p.highlight,
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Reveal(
                delay: const Duration(milliseconds: 48),
                child: Text(
                  'No venues in $city yet',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.sectionHeading(p.primaryText),
                ),
              ),
              const SizedBox(height: 8),
              Reveal(
                delay: const Duration(milliseconds: 88),
                child: Text(
                  'Currently no venues have been added for the location you selected. Please choose another location to see venues, memberships and coaching.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.body(p.secondaryText)
                      .copyWith(height: 1.5),
                ),
              ),
              const SizedBox(height: 22),
              Reveal(
                delay: const Duration(milliseconds: 128),
                child: GameAllButton.secondary(
                  label: 'Change location',
                  icon: Icons.location_on_outlined,
                  onPressed: () => showCityPicker(context, ref),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
