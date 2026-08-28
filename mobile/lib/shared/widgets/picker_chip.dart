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
  const PickerChip({super.key, required this.label, required this.onSelect, this.icon = Icons.arrow_drop_down});

  final String label;
  final VoidCallback onSelect;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onSelect,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        constraints: const BoxConstraints(minHeight: AppSpacing.minTouchTarget),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 4),
            Icon(icon, size: 20),
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