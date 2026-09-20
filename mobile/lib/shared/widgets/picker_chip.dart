import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';

/// A tap-to-choose chip — the mobile stand-in for the web's `<Select>`
/// trigger, following the pattern the Owner Dashboard already established
/// (chip + `showModalBottomSheet` list of options) rather than a Material
/// `DropdownButton`, which is cramped on small screens and clips badly at
/// large system font sizes.
///
/// Constrained to [AppSpacing.minTouchTarget] and shrink-wrapped so a row of
/// these can live inside a `Wrap` and reflow instead of overflowing at 320dp.
class PickerChip extends StatelessWidget {
  const PickerChip({
    super.key,
    required this.label,
    required this.onSelect,
    this.icon = Icons.arrow_drop_down,
    this.leading,
  });

  final String label;
  final VoidCallback onSelect;
  final IconData icon;

  /// Optional icon shown before the label (e.g. a sport/court glyph) —
  /// omitted by default so every existing call site is unaffected.
  final IconData? leading;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return InkWell(
      onTap: onSelect,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        constraints: const BoxConstraints(minHeight: AppSpacing.minTouchTarget),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        decoration: BoxDecoration(
          // A filled pill, not a bare outline floating on the page — the
          // same "premium" filter treatment as the dashboard's date/sport
          // chip, rolled out everywhere PickerChip is used.
          color: tokens.surface1,
          border: Border.all(color: tokens.borderColor),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[
              Icon(leading, size: 16, color: tokens.textSecondary),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: tokens.textPrimary)),
            ),
            const SizedBox(width: 4),
            Icon(icon, size: 20, color: tokens.primary),
          ],
        ),
      ),
    );
  }
}

/// The options sheet that pairs with [PickerChip]. Scrollable and
/// bottom-inset aware so a long option list (or a large system font) can
/// never overflow.
Future<T?> showPickerSheet<T>({
  required BuildContext context,
  required List<({T value, String label})> options,
  required T selected,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: options
              .map(
                (option) => ListTile(
                  title: Text(option.label),
                  trailing: option.value == selected ? const Icon(Icons.check, color: AppColors.primary) : null,
                  onTap: () => Navigator.pop(context, option.value),
                ),
              )
              .toList(),
        ),
      ),
    ),
  );
}