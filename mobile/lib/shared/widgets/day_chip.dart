import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';

/// One weekday in a day picker. Selected days are filled with the brand colour and show a tick, so it is obvious at a glance
/// which days are on; unselected days are quiet outlines. (The stock FilterChip only tints the background a little, which is
/// hard to see on a phone.)
class DayChip extends StatelessWidget {
  const DayChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onChanged,
    this.compact = false,
  });

  final String label;
  final bool selected;

  /// Called with the new value when the chip is tapped; null makes the chip read-only.
  final ValueChanged<bool>? onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final fg = selected ? t.onPrimary : t.textPrimary;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected ? t.primary : t.surface2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          side: BorderSide(color: selected ? t.primary : t.borderColor, width: selected ? 1.5 : 1),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onChanged == null ? null : () => onChanged!(!selected),
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: compact ? 52 : 64, minHeight: compact ? 36 : 44),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: compact ? AppSpacing.sm : AppSpacing.md, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (selected) ...[
                    Icon(Icons.check_rounded, size: compact ? 14 : 16, color: fg),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    label,
                    style: TextStyle(fontSize: compact ? 12 : 14, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: fg),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
