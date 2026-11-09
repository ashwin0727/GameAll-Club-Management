import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/pressable.dart';
import '../../../core/widgets/sport_icon.dart';
import '../../player_home/application/player_home_controller.dart';
import '../../player_home/presentation/widgets/player_search_bar.dart';

/// The pieces that make the top of the three venue-list pages on a phone (Book a Court, Explore Memberships, Find a Coach): a title
/// line with the location icon at its right end, a row of sports, and a small search box. They are the same on every page, so the
/// pages look and behave alike.

/// A round location icon: tapping it opens the city list (with "Use my current location"). It sits at the right end of the title line.
class LocationActionButton extends ConsumerWidget {
  const LocationActionButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final city = ref.watch(selectedCityProvider);
    return Semantics(
      button: true,
      label: 'Location: $city',
      child: Tooltip(
        message: city,
        child: Pressable(
          key: const ValueKey('discover-city'),
          onTap: () => showCityPicker(context, ref),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: p.surface,
              border: Border.all(color: p.border),
            ),
            child: Icon(
              Icons.location_on_outlined,
              size: 22,
              color: p.highlight,
            ),
          ),
        ),
      ),
    );
  }
}

/// The page's own title line, for when the page is a tab (a pushed page has the app bar instead): title at the left, location icon at
/// the right end of the same line.
class PhoneTitleRow extends StatelessWidget {
  const PhoneTitleRow({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            key: const ValueKey('phone-title'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.sectionHeading(p.primaryText),
          ),
        ),
        const SizedBox(width: 12),
        const LocationActionButton(),
      ],
    );
  }
}

/// "All" and each sport as a tile (icon over name), scrolling sideways. Tapping a sport selects it at once (the list below changes
/// straight away); tapping "All" or the chosen sport again shows every sport.
class SportChipsRow extends StatelessWidget {
  const SportChipsRow({
    super.key,
    required this.sports,
    required this.selected,
    required this.onSelect,
  });

  final List<String> sports;

  /// The chosen sport, or null for All.
  final String? selected;
  final ValueChanged<String?> onSelect;

  bool _on(String? s) => s == null
      ? selected == null
      : selected != null &&
            selected!.trim().toLowerCase() == s.trim().toLowerCase();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget tile(String? sport) {
      final on = _on(sport);
      final label = sport ?? 'All';
      return Semantics(
        button: true,
        selected: on,
        label: label,
        child: ExcludeSemantics(
          child: Pressable(
            key: ValueKey(sport == null ? 'sport-chip-all' : 'sport-chip-$sport'),
            onTap: () => onSelect(on && sport != null ? null : sport),
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              width: 68,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: on
                          ? const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF9B5CFF), Color(0xFF5B5BE8)],
                            )
                          : null,
                      color: on ? null : p.surface,
                      border: Border.all(
                        color: on ? Colors.transparent : p.border,
                      ),
                      boxShadow: on
                          ? [
                              BoxShadow(
                                color: const Color(
                                  0xFF7C5CFF,
                                ).withValues(alpha: 0.35),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ]
                          : null,
                    ),
                    child: Center(
                      child: sport == null
                          ? Icon(
                              Icons.grid_view_rounded,
                              size: 22,
                              color: on ? Colors.white : p.highlight,
                            )
                          : SportIcon(
                              sport,
                              size: 26,
                              color: on ? Colors.white : p.highlight,
                            ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.meta(
                      on ? p.primaryText : p.secondaryText,
                    ).copyWith(
                      fontSize: 12,
                      fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final items = <String?>[null, ...sports];
    return SizedBox(
      height: 86,
      child: ListView.separated(
        key: const ValueKey('sport-chips'),
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (_, i) => tile(items[i]),
      ),
    );
  }
}

/// A small search box (40 px high): a magnifier, the hint, and a clear button once something is typed.
class CompactSearchField extends StatelessWidget {
  const CompactSearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
    required this.onSearch,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      height: 42,
      padding: const EdgeInsets.only(left: 12, right: 4),
      decoration: BoxDecoration(
        color: p.isDark ? const Color(0xFF0E1630) : p.elevated,
        borderRadius: BorderRadius.circular(21),
        border: Border.all(
          color: p.isDark ? const Color(0xFF263552) : p.border,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 20, color: p.secondaryText),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              key: const ValueKey('discover-search'),
              controller: controller,
              onChanged: onChanged,
              onSubmitted: (_) => onSearch(),
              textInputAction: TextInputAction.search,
              style: AppTextStyles.body(p.primaryText).copyWith(fontSize: 14),
              cursorColor: AppColors.cyan,
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                hintText: hint,
                hintStyle: AppTextStyles.body(p.mutedText).copyWith(fontSize: 14),
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            IconButton(
              key: const ValueKey('discover-search-clear'),
              tooltip: 'Clear',
              visualDensity: VisualDensity.compact,
              onPressed: () => onChanged(''),
              icon: Icon(Icons.close_rounded, size: 18, color: p.secondaryText),
            ),
        ],
      ),
    );
  }
}
