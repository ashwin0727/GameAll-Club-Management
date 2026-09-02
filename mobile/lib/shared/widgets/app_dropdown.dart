import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';

/// The app's one dropdown: an outlined field with the label floating in the
/// border notch, a chevron affordance, and a rounded menu whose selected row
/// is highlighted — the pattern from the design.
///
/// Deliberately a drop-in for `DropdownButtonFormField<T>`: same parameter
/// names, so call sites migrate by changing the constructor alone. The
/// styling lives here rather than at each of the app's call sites, so a
/// dropdown cannot drift off-design by being written by hand again.
class AppDropdown<T> extends StatelessWidget {
  const AppDropdown({
    super.key,
    required this.items,
    required this.onChanged,
    this.initialValue,
    this.decoration,
    this.validator,
    this.hint,
    this.isExpanded = true,
  });

  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final T? initialValue;

  /// Only `labelText`, `hintText`, `helperText`, `errorText` and `prefixIcon`
  /// are honoured — borders and fill come from the design, not the caller.
  final InputDecoration? decoration;
  final FormFieldValidator<T>? validator;
  final Widget? hint;
  final bool isExpanded;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final radius = BorderRadius.circular(AppRadius.md);

    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: color, width: width),
        );

    return DropdownButtonFormField<T>(
      initialValue: initialValue,
      items: items,
      onChanged: onChanged,
      validator: validator,
      hint: hint,
      isExpanded: isExpanded,
      borderRadius: radius,
      dropdownColor: tokens.surface1,
      icon: Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: tokens.textSecondary),
      // The field reads as outlined, not filled: a hairline border with the
      // label sitting in its notch, matching the design's trigger.
      decoration: InputDecoration(
        labelText: decoration?.labelText,
        hintText: decoration?.hintText,
        helperText: decoration?.helperText,
        errorText: decoration?.errorText,
        prefixIcon: decoration?.prefixIcon,
        filled: true,
        fillColor: tokens.surface1,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        border: border(tokens.borderColor, 1),
        enabledBorder: border(tokens.borderColor, 1),
        focusedBorder: border(tokens.primary, 2),
        errorBorder: border(tokens.destructive, 1),
        focusedErrorBorder: border(tokens.destructive, 2),
      ),
    );
  }
}
