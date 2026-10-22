import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';

/// The look of every select-style field — dropdowns, and the tap-to-pick date / time / choice
/// fields built on [InputDecorator]: a rounded hairline border at rest, the same border (never none) when the
/// field is disabled, a 2px ring in the brand colour while it is open or focused, red on error. Kept in one place so
/// the two can't drift apart.
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
  final radius = BorderRadius.circular(AppRadius.lg);
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

/// Opens the app's dropdown list under [anchor]: a soft rounded card, as wide as the field, with roomy rows and the
/// chosen one picked out. Every dropdown in the app — the full-width [AppDropdown], the compact
/// [AppInlineDropdown], and the chip pickers — opens this same list, so they can never look different.
///
/// Returns the picked value, or null if the list was dismissed.
Future<T?> showAppDropdownMenu<T>({
  required BuildContext context,
  required RenderBox anchor,
  required List<DropdownMenuItem<T>> items,
  T? selected,
  double minWidth = 0,
}) {
  final tokens = context.tokens;
  final overlay = Overlay.of(context, rootOverlay: true).context.findRenderObject()! as RenderBox;
  // Just under the field, with a small gap, like the design.
  final topLeft = anchor.localToGlobal(Offset(0, anchor.size.height + 6), ancestor: overlay);
  final width = anchor.size.width < minWidth ? minWidth : anchor.size.width;
  final position = RelativeRect.fromLTRB(
    topLeft.dx,
    topLeft.dy,
    overlay.size.width - topLeft.dx - width,
    overlay.size.height - topLeft.dy,
  );
  final radius = BorderRadius.circular(AppRadius.lg);

  return showMenu<T>(
    context: context,
    position: position,
    constraints: BoxConstraints(minWidth: width, maxWidth: width < 200 ? 320 : width),
    color: tokens.surface1,
    surfaceTintColor: Colors.transparent,
    elevation: 10,
    shadowColor: Colors.black.withValues(alpha: tokens.isLight ? 0.22 : 0.6),
    shape: RoundedRectangleBorder(
      borderRadius: radius,
      side: BorderSide(color: tokens.borderColor.withValues(alpha: tokens.isLight ? 0.6 : 1)),
    ),
    clipBehavior: Clip.antiAlias,
    menuPadding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
    items: [
      for (final item in items)
        PopupMenuItem<T>(
          value: item.value,
          enabled: item.enabled,
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: DefaultTextStyle.merge(
            style: TextStyle(
              fontSize: 15,
              fontWeight: item.value == selected ? FontWeight.w700 : FontWeight.w500,
              color: item.enabled
                  ? (item.value == selected ? tokens.primary : tokens.textPrimary)
                  : tokens.textSecondary.withValues(alpha: 0.6),
            ),
            child: item.child,
          ),
        ),
    ],
  );
}

/// A compact select that sits inline in a row of text or controls (e.g. "Day type: [Weekday ▾]") —
/// the same rounded, filled box as [AppDropdown], just sized to its content instead of spanning the width, opening
/// the same list.
class AppInlineDropdown<T> extends StatelessWidget {
  const AppInlineDropdown({super.key, required this.value, required this.items, required this.onChanged});

  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final enabled = onChanged != null;
    final selected = items.where((i) => i.value == value).firstOrNull;
    return Builder(builder: (context) {
      return InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: !enabled
            ? null
            : () async {
                final box = context.findRenderObject()! as RenderBox;
                final picked = await showAppDropdownMenu<T>(
                  context: context,
                  anchor: box,
                  items: items,
                  selected: value,
                  minWidth: 160,
                );
                if (picked != null && picked != value) onChanged!(picked);
              },
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tokens.surface1,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: enabled ? tokens.borderColor : tokens.borderColor.withValues(alpha: 0.5)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DefaultTextStyle.merge(
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: tokens.textPrimary),
                  child: selected?.child ?? const SizedBox.shrink(),
                ),
                const SizedBox(width: 6),
                Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: tokens.textSecondary),
              ],
            ),
          ),
        ),
      );
    });
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

/// The app's one dropdown: a rounded outlined field with the label floating in the border, a chevron that turns when
/// the list is open, and a soft rounded list that drops just under the field — the pattern from the design.
///
/// A drop-in for `DropdownButtonFormField<T>`: same parameter names, so call sites migrate by changing the constructor
/// alone. The styling lives here rather than at each call site, so a dropdown cannot drift off-design by being written by
/// hand again. It is a real [FormField]: validators and `Form.validate()` work as before.
class AppDropdown<T> extends FormField<T> {
  AppDropdown({
    super.key,
    required this.items,
    required this.onChanged,
    super.initialValue,
    this.decoration,
    super.validator,
    this.hint,
    this.isExpanded = true,
  }) : super(
          enabled: onChanged != null,
          builder: (field) {
            final state = field as _AppDropdownState<T>;
            return state._build(field.context);
          },
        );

  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;

  /// Only `labelText`, `hintText`, `helperText`, `errorText` and `prefixIcon`
  /// are honoured — borders and fill come from the design, not the caller.
  final InputDecoration? decoration;
  final Widget? hint;
  final bool isExpanded;

  @override
  FormFieldState<T> createState() => _AppDropdownState<T>();
}

class _AppDropdownState<T> extends FormFieldState<T> {
  bool _open = false;

  AppDropdown<T> get _w => widget as AppDropdown<T>;

  @override
  void didUpdateWidget(covariant AppDropdown<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Like DropdownButtonFormField: a new initialValue from the parent replaces the shown value.
    if (oldWidget.initialValue != _w.initialValue) setValue(_w.initialValue);
  }

  Future<void> _openMenu() async {
    if (_w.onChanged == null || _open) return;
    final box = context.findRenderObject()! as RenderBox;
    setState(() => _open = true);
    final picked = await showAppDropdownMenu<T>(context: context, anchor: box, items: _w.items, selected: value);
    if (!mounted) return;
    setState(() => _open = false);
    if (picked != null) {
      didChange(picked);
      _w.onChanged?.call(picked);
    }
  }

  Widget _build(BuildContext context) {
    final tokens = context.tokens;
    final enabled = _w.onChanged != null;
    final selected = _w.items.where((i) => i.value == value).firstOrNull;
    final d = _w.decoration;
    final hasLabel = d?.labelText != null;
    // A hint shows in the field itself when there is no label to sit there instead.
    final showHint = selected == null && _w.hint != null && !hasLabel;

    return Semantics(
      button: true,
      enabled: enabled,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: enabled ? _openMenu : null,
        child: InputDecorator(
          isEmpty: selected == null && !showHint,
          isFocused: _open,
          decoration: appSelectDecoration(
            context,
            labelText: d?.labelText,
            hintText: d?.hintText,
            helperText: d?.helperText,
            errorText: errorText,
            prefixIcon: d?.prefixIcon,
            suffixIcon: AnimatedRotation(
              turns: _open ? 0.5 : 0,
              duration: const Duration(milliseconds: 180),
              child: Icon(Icons.keyboard_arrow_down_rounded, size: 22, color: enabled ? tokens.textSecondary : tokens.textSecondary.withValues(alpha: 0.5)),
            ),
          ),
          child: DefaultTextStyle.merge(
            style: TextStyle(fontSize: 15, color: showHint ? tokens.textSecondary : tokens.textPrimary),
            child: Align(
              alignment: Alignment.centerLeft,
              heightFactor: 1,
              child: showHint ? _w.hint! : (selected?.child ?? const SizedBox.shrink()),
            ),
          ),
        ),
      ),
    );
  }
}
