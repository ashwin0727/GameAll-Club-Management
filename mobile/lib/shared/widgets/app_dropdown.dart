import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';

/// The look of every select-style field — dropdowns, and the tap-to-pick date / time / choice
/// fields built on [InputDecorator]: a hairline border at rest, the same border (never none) when the
/// field is disabled, a green 2px ring on focus, red on error. Kept in one place so the two can't
/// drift apart.
InputDecoration appSelectDecoration(
  BuildContext context, {
  String? labelText,
  String? hintText,
  String? helperText,
  String? errorText,
  Widget? prefixIcon,
  Widget? suffixIcon,
}) {
  final tokens = context.tokens;
  final radius = BorderRadius.circular(AppRadius.md);
  OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: color, width: width),
      );
  return InputDecoration(
    labelText: labelText,
    hintText: hintText,
    helperText: helperText,
    errorText: errorText,
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: tokens.surface1,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
    border: border(tokens.borderColor, 1),
    enabledBorder: border(tokens.borderColor, 1),
    // A disabled select keeps its outline (dimmed) — without this it fell back to no border at all.
    disabledBorder: border(tokens.borderColor.withValues(alpha: 0.5), 1),
    focusedBorder: border(tokens.primary, 2),
    errorBorder: border(tokens.destructive, 1),
    focusedErrorBorder: border(tokens.destructive, 2),
  );
}

/// A compact select that sits inline in a row of text or controls (e.g. "Day type: [Weekday ▾]") —
/// the same hairline-bordered, filled box as [AppDropdown], just sized to its content instead of
/// spanning the width. Replaces a bare `DropdownButton`, which draws no border at all.
class AppInlineDropdown<T> extends StatelessWidget {
  const AppInlineDropdown({super.key, required this.value, required this.items, required this.onChanged});

  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final enabled = onChanged != null;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surface1,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: enabled ? tokens.borderColor : tokens.borderColor.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 2),
        child: DropdownButton<T>(
          value: value,
          isDense: true,
          underline: const SizedBox.shrink(),
          borderRadius: BorderRadius.circular(AppRadius.md),
          dropdownColor: tokens.surface1,
          icon: Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: tokens.textSecondary),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

/// A tap-to-pick field (date, time, a choice made in a sheet) drawn exactly like [AppDropdown]. Use
/// it wherever an `InkWell` + `InputDecorator` shows a chosen value, so every select in the app has
/// the same border and fill. Only the label / hint / helper / error text and prefix icon are honoured
/// from [decoration]; borders and fill come from the design.
class AppSelectField extends StatelessWidget {
  const AppSelectField({super.key, this.decoration, this.child, this.isEmpty = false});

  final InputDecoration? decoration;
  final Widget? child;
  final bool isEmpty;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      isEmpty: isEmpty,
      decoration: appSelectDecoration(
        context,
        labelText: decoration?.labelText,
        hintText: decoration?.hintText,
        helperText: decoration?.helperText,
        errorText: decoration?.errorText,
        prefixIcon: decoration?.prefixIcon,
        suffixIcon: decoration?.suffixIcon,
      ),
      child: child,
    );
  }
}

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
      decoration: appSelectDecoration(
        context,
        labelText: decoration?.labelText,
        hintText: decoration?.hintText,
        helperText: decoration?.helperText,
        errorText: decoration?.errorText,
        prefixIcon: decoration?.prefixIcon,
      ),
    );
  }
}
