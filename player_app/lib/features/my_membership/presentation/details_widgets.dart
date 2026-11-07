import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/pressable.dart';

/// The rounded panel every details page is built from (Membership Details, My Coaching): an optional title with an icon and a trailing
/// widget, then the content.
class DetailsCard extends StatelessWidget {
  const DetailsCard({
    super.key,
    required this.child,
    this.title,
    this.icon,
    this.trailing,
  });

  final Widget child;
  final String? title;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: p.isDark ? const Color(0xFF2E3B63) : p.border,
        ),
        color: p.surface.withValues(alpha: p.isDark ? 0.6 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Row(
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 22,
                    color: p.isDark
                        ? const Color(0xFFB9A4FF)
                        : AppColors.violet,
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    title!,
                    style: AppTextStyles.cardHeading(p.primaryText)
                        .copyWith(fontSize: 18),
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 14),
          ],
          child,
        ],
      ),
    );
  }
}

/// The rounded row of tabs under a details page's summary: [labels] in order, the current one highlighted.
class PillTabs extends StatelessWidget {
  const PillTabs({
    super.key,
    required this.labels,
    required this.current,
    required this.onTab,
    required this.keyOf,
  });

  final List<String> labels;
  final int current;
  final ValueChanged<int> onTab;

  /// The test key of the tab at an index (e.g. 'mm-tab-payments').
  final String Function(int index) keyOf;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
            color: p.isDark ? const Color(0xFF2E3B63) : p.border,
          ),
          color: p.surface.withValues(alpha: p.isDark ? 0.5 : 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < labels.length; i++)
              Semantics(
                button: true,
                selected: i == current,
                label: labels[i],
                child: Pressable(
                  key: ValueKey(keyOf(i)),
                  onTap: () => onTab(i),
                  borderRadius: BorderRadius.circular(22),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 26,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      gradient: i == current
                          ? const LinearGradient(
                              colors: [Color(0xFF9B5CFF), Color(0xFF6A4BE0)],
                            )
                          : null,
                    ),
                    child: Text(
                      labels[i],
                      style: AppTextStyles.button(
                        i == current ? Colors.white : p.primaryText,
                      ).copyWith(fontSize: 14.5),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
