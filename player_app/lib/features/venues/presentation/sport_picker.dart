import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/pressable.dart';
import '../../../core/widgets/sport_icon.dart';

/// The sports a venue offers, as small chips on a card: tap one and the card shows that sport's prices (Memberships) or programme
/// (Coaching). The chosen sport is outlined with the same cyan-to-violet gradient as the sport chips on the Venues page.
class SportPicker extends StatelessWidget {
  const SportPicker({
    super.key,
    required this.sports,
    required this.selected,
    required this.onSelected,
    this.keyPrefix = 'sport-pick',
  });

  final List<String> sports;

  /// The sport shown now (compared without regard to case).
  final String? selected;
  final ValueChanged<String> onSelected;

  /// Chip keys are `<keyPrefix>-<sport>`.
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final s in sports)
          Builder(
            builder: (context) {
              final on =
                  selected != null &&
                  selected!.trim().toLowerCase() == s.trim().toLowerCase();
              return Semantics(
                button: true,
                selected: on,
                label: s,
                child: ExcludeSemantics(
                  child: Pressable(
                    key: ValueKey('$keyPrefix-$s'),
                    onTap: () => onSelected(s),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: EdgeInsets.all(on ? 1.5 : 1),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        gradient: on
                            ? const LinearGradient(
                                colors: [Color(0xFF22D3EE), Color(0xFF8B5CF6)],
                              )
                            : null,
                        color: on
                            ? null
                            : (p.isDark ? const Color(0xFF2E3B63) : p.border),
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(19),
                          color: p.isDark ? const Color(0xFF0A1126) : p.surface,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SportIcon(
                              s,
                              size: 16,
                              color: on
                                  ? AppColors.cyan
                                  : p.primaryText.withValues(alpha: 0.85),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              s,
                              maxLines: 1,
                              style: AppTextStyles.meta(p.primaryText).copyWith(
                                fontSize: 12.5,
                                fontWeight: on
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}
