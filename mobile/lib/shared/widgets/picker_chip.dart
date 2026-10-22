import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
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
                      fontWeight: FontWeight.w500,
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

/// The options list that pairs with [PickerChip]: a floating, rounded card with roomy rows and the chosen one picked
/// out — the same look as every dropdown in the app. Scrollable and bottom-inset aware so a long option list (or a large
/// system font) can never overflow.
Future<T?> showPickerSheet<T>({
  required BuildContext context,
  required List<({T value, String label})> options,
  required T selected,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    elevation: 0,
    builder: (sheetContext) {
      final tokens = sheetContext.tokens;
      final maxHeight = MediaQuery.sizeOf(sheetContext).height * 0.7;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
          child: Container(
            constraints: BoxConstraints(maxHeight: maxHeight),
            decoration: BoxDecoration(
              color: tokens.surface1,
              borderRadius: BorderRadius.circular(AppRadius.xl),
              border: Border.all(color: tokens.borderColor.withValues(alpha: tokens.isLight ? 0.6 : 1)),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: tokens.isLight ? 0.2 : 0.55), blurRadius: 28, offset: const Offset(0, 10))],
            ),
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final option in options)
                    InkWell(
                      onTap: () => Navigator.pop(sheetContext, option.value),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 52),
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                        alignment: Alignment.centerLeft,
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                option.label,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: option.value == selected ? FontWeight.w700 : FontWeight.w500,
                                  color: option.value == selected ? tokens.primary : tokens.textPrimary,
                                ),
                              ),
                            ),
                            if (option.value == selected) Icon(Icons.check_rounded, size: 20, color: tokens.primary),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
