import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/hover_scope.dart';
import '../../../../core/widgets/pressable.dart';
import '../../../../core/widgets/sport_icon.dart';
import '../../application/player_home_controller.dart';

/// A horizontally scrolling row of sports; the selected one has the blue-to-violet gradient.
class SportsSelector extends ConsumerWidget {
  const SportsSelector({super.key, this.onMore});

  /// Called when "More" is tapped.
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedSportProvider);
    return SizedBox(
      height: 78,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: sportOptions.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final sport = sportOptions[i];
          return _SportItem(
            key: ValueKey('sport-${sport.id}'),
            sport: sport,
            selected: sport.id == selected,
            onTap: () {
              if (sport.id == 'more') {
                onMore?.call();
              } else {
                ref.read(selectedSportProvider.notifier).select(sport.id);
              }
            },
          );
        },
      ),
    );
  }
}

class _SportItem extends StatelessWidget {
  const _SportItem({
    super.key,
    required this.sport,
    required this.selected,
    required this.onTap,
  });

  final SportOption sport;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final labelColor = selected
        ? (p.isDark ? p.highlight : p.primary)
        : p.secondaryText;
    return Semantics(
      button: true,
      selected: selected,
      label: sport.label,
      child: ExcludeSemantics(
        child: SizedBox(
          width: 62,
          child: Pressable(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppDimensions.chipRadius),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: AppDimensions.sportIconBox,
                  height: AppDimensions.sportIconBox,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(
                      AppDimensions.chipRadius,
                    ),
                    gradient: selected ? AppColors.accentGradient : null,
                    color: selected ? null : p.surface,
                    border: selected ? null : Border.all(color: p.border),
                  ),
                  child: sport.sportName == null
                      ? Icon(
                          sport.icon,
                          size: 22,
                          color: selected
                              ? Colors.white
                              : (p.isDark
                                    ? const Color(0xFFD7E2F3)
                                    : p.secondaryText),
                        )
                      : SportIcon(
                          sport.sportName,
                          size: 26,
                          color: selected
                              ? Colors.white
                              : (p.isDark
                                    ? const Color(0xFFD7E2F3)
                                    : p.secondaryText),
                        ),
                ),
                const SizedBox(height: 6),
                HoverText(
                  sport.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.navLabel(labelColor).copyWith(
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
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
