import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/hover_scope.dart';
import '../../application/player_home_controller.dart';

/// The search field with the location pin built into it. Tapping the field opens search; tapping the pin opens the city picker.
class PlayerSearchBar extends ConsumerWidget {
  const PlayerSearchBar({super.key, required this.onSearch});

  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final city = ref.watch(selectedCityProvider);
    return Container(
      height: AppDimensions.searchHeight,
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(AppDimensions.searchRadius),
        border: Border.all(color: p.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              button: true,
              label: 'Search venues, sports, memberships',
              child: ExcludeSemantics(
                child: InkWell(
                  onTap: onSearch,
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(AppDimensions.searchRadius),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Row(
                      children: [
                        Icon(
                          Icons.search_rounded,
                          size: 20,
                          color: p.secondaryText,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Search venues, sports, memberships...',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.support(p.secondaryText),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Container(width: 1, height: 24, color: p.border),
          Tooltip(
            message: 'Location: $city',
            child: Semantics(
              button: true,
              label: 'Choose location, now $city',
              child: ExcludeSemantics(
                child: InkWell(
                  onTap: () => showCityPicker(context, ref),
                  borderRadius: const BorderRadius.horizontal(
                    right: Radius.circular(AppDimensions.searchRadius),
                  ),
                  child: SizedBox(
                    width: 54,
                    height: AppDimensions.searchHeight,
                    child: Icon(
                      Icons.location_on_rounded,
                      size: 20,
                      color: p.highlight,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pick the city by hand (no device location permission needed). On a wide window (the web) it is a centred popup; on a phone it
/// is a sheet that slides up from the bottom. Choosing a city closes it.
Future<void> showCityPicker(BuildContext context, WidgetRef ref) {
  final wide =
      MediaQuery.sizeOf(context).width >= AppDimensions.desktopBreakpoint;
  if (!wide) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          ),
          child: _CityPicker(
            onClose: () => Navigator.of(sheetContext).pop(),
            showClose: false,
          ),
        ),
      ),
    );
  }
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: dialogContext.palette.secondaryBackground,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: dialogContext.palette.border),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 440,
          maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.8,
        ),
        child: _CityPicker(
          onClose: () => Navigator.of(dialogContext).pop(),
          showClose: true,
        ),
      ),
    ),
  );
}

class _CityPicker extends ConsumerWidget {
  const _CityPicker({required this.onClose, required this.showClose});

  final VoidCallback onClose;

  /// The popup has a close button; the bottom sheet closes by dragging down or tapping outside.
  final bool showClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final current = ref.watch(selectedCityProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            showClose ? 18 : 0,
            showClose ? 8 : 24,
            8,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Choose your city',
                  style: AppTextStyles.sectionHeading(p.primaryText),
                ),
              ),
              if (showClose)
                IconButton(
                  tooltip: 'Close',
                  onPressed: onClose,
                  icon: Icon(Icons.close_rounded, color: p.secondaryText),
                ),
            ],
          ),
        ),
        Flexible(
          // No visible scrollbar in the popup; the list still scrolls with the wheel or a swipe if the window is short.
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context)
                .copyWith(scrollbars: false),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 12),
              children: [
                for (final city in playerCities)
                  HoverRegion(
                    key: ValueKey('city-$city'),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 24,
                      ),
                      leading: Icon(
                        Icons.location_city_rounded,
                        color: city == current ? p.highlight : p.secondaryText,
                      ),
                      title: HoverText(
                        city,
                        style: AppTextStyles.body(p.primaryText)
                            .copyWith(fontWeight: FontWeight.w500),
                      ),
                      trailing: city == current
                          ? Icon(Icons.check_circle_rounded, color: p.highlight)
                          : null,
                      onTap: () {
                        ref.read(selectedCityProvider.notifier).select(city);
                        onClose();
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
