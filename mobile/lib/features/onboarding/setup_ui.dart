import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

/// The light-only look of the redesigned facility-setup screens (palette and weights from the GameAll setup spec):
/// primary #4817C2, hover #39109F, active #F1EBFF, border #E5E1EF, text #171717 / #666666 on white; Inter 400-700.
class SetupColors {
  const SetupColors._();

  static const Color primary = Color(0xFF4817C2);
  static const Color primaryPressed = Color(0xFF39109F);
  static const Color activeBg = Color(0xFFF1EBFF);
  static const Color border = Color(0xFFE5E1EF);
  static const Color background = Color(0xFFFFFFFF);
  static const Color text = Color(0xFF171717);
  static const Color secondary = Color(0xFF666666);
  static const Color placeholder = Color(0xFF9A97A8);
  static const Color error = Color(0xFFC62828);
  static const Color success = Color(0xFF2E7D32);
  static const Color mutedFill = Color(0xFFF7F5FB);
}

/// Inter at the requested weight. Falls back to the platform font when runtime font fetching is off (unit tests).
TextStyle setupText({double size = 14, FontWeight weight = FontWeight.w400, Color color = SetupColors.text, double? height}) {
  final base = TextStyle(fontSize: size, fontWeight: weight, color: color, height: height);
  if (!GoogleFonts.config.allowRuntimeFetching) return base;
  return GoogleFonts.inter(textStyle: base);
}

/// The shared page: white ground, GameAll logo + "Need Help?" on top, scrolling body, pinned footer.
class SetupPage extends StatelessWidget {
  const SetupPage({super.key, required this.children, required this.footer, this.scrollController});

  final List<Widget> children;
  final Widget footer;
  final ScrollController? scrollController;

  static const double maxWidth = 640;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        brightness: Brightness.light,
        scaffoldBackgroundColor: SetupColors.background,
        colorScheme: ColorScheme.fromSeed(seedColor: SetupColors.primary, brightness: Brightness.light, primary: SetupColors.primary, surface: SetupColors.background),
        textSelectionTheme: const TextSelectionThemeData(cursorColor: SetupColors.primary, selectionHandleColor: SetupColors.primary),
      ),
      child: Scaffold(
        backgroundColor: SetupColors.background,
        body: SafeArea(
          child: Column(
            children: [
              const SetupHeader(),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: maxWidth),
                    child: SingleChildScrollView(
                      controller: scrollController,
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
                    ),
                  ),
                ),
              ),
              Container(
                decoration: const BoxDecoration(color: SetupColors.background, border: Border(top: BorderSide(color: SetupColors.border))),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Center(
                  child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: maxWidth), child: footer),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SetupHeader extends StatelessWidget {
  const SetupHeader({super.key});

  static const String helpEmail = 'admin@gameall.co';

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(color: SetupColors.background, border: Border(bottom: BorderSide(color: SetupColors.border))),
      child: Row(
        children: [
          // the logo gives way first on a very narrow phone, so the help link is never pushed off the edge
          Flexible(
            child: Semantics(
              label: 'GameAll',
              child: ExcludeSemantics(child: Image.asset('assets/images/gameall_logo_light.png', height: 34, fit: BoxFit.contain, alignment: Alignment.centerLeft, filterQuality: FilterQuality.high)),
            ),
          ),
          const SizedBox(width: 8),
          const Spacer(),
          InkWell(
            key: const ValueKey('setup-help'),
            borderRadius: BorderRadius.circular(8),
            onTap: () => launchUrl(Uri(scheme: 'mailto', path: helpEmail, queryParameters: {'subject': 'Facility setup help'})),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.help_outline, size: 20, color: SetupColors.text),
                  const SizedBox(width: 6),
                  Text('Need Help?', style: setupText(size: 14, weight: FontWeight.w500)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Step 1 of 5 · Facility Information" with a progress bar.
class SetupStepper extends StatelessWidget {
  const SetupStepper({super.key, this.current = 1});

  static const List<String> steps = ['Facility Information', 'Sports & Courts', 'Operating Hours', 'Pricing', 'Payout'];
  final int current;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Step $current of ${steps.length}: ${steps[current - 1]}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Step $current of ${steps.length} · ${steps[current - 1]}', style: setupText(size: 12, weight: FontWeight.w600, color: SetupColors.primary)),
          const SizedBox(height: 8),
          Row(
            children: [
              for (var i = 0; i < steps.length; i++) ...[
                Expanded(
                  child: Container(
                    height: 5,
                    decoration: BoxDecoration(color: i < current ? SetupColors.primary : SetupColors.activeBg, borderRadius: BorderRadius.circular(99)),
                  ),
                ),
                if (i < steps.length - 1) const SizedBox(width: 5),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class SetupCard extends StatelessWidget {
  const SetupCard({super.key, required this.child, this.padding = const EdgeInsets.all(16)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(color: SetupColors.background, border: Border.all(color: SetupColors.border), borderRadius: BorderRadius.circular(16)),
      child: child,
    );
  }
}

class SetupCardHeading extends StatelessWidget {
  const SetupCardHeading({super.key, required this.title, this.description, this.icon});

  final String title;
  final String? description;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[Icon(icon, color: SetupColors.primary, size: 26), const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: setupText(size: 17, weight: FontWeight.w600)),
                if (description != null) ...[const SizedBox(height: 2), Text(description!, style: setupText(size: 13, color: SetupColors.secondary, height: 1.35))],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A label (600) above its control, with the red star / "(Optional)" marker — the same shape on every field so rows line up.
class SetupLabel extends StatelessWidget {
  const SetupLabel(this.text, {super.key, this.required = false, this.optional = false});

  final String text;
  final bool required;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text.rich(
        TextSpan(
          style: setupText(size: 14, weight: FontWeight.w600),
          children: [
            TextSpan(text: text),
            if (required) TextSpan(text: ' *', style: setupText(size: 14, weight: FontWeight.w600, color: SetupColors.error)),
            if (optional) TextSpan(text: ' (Optional)', style: setupText(size: 12, color: SetupColors.secondary)),
          ],
        ),
      ),
    );
  }
}

InputDecoration setupDecoration({String? hint, Widget? prefix, Widget? suffix, bool filled = false, String? counterText}) {
  OutlineInputBorder border(Color c, {double w = 1}) => OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c, width: w));
  return InputDecoration(
    hintText: hint,
    hintStyle: setupText(size: 15, color: SetupColors.placeholder),
    errorStyle: setupText(size: 12, weight: FontWeight.w500, color: SetupColors.error, height: 1.3),
    errorMaxLines: 3,
    filled: true,
    fillColor: filled ? SetupColors.mutedFill : SetupColors.background,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    prefixIcon: prefix,
    prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
    suffixIcon: suffix,
    counterText: counterText,
    enabledBorder: border(SetupColors.border),
    disabledBorder: border(SetupColors.border),
    focusedBorder: border(SetupColors.primary, w: 1.6),
    errorBorder: border(SetupColors.error),
    focusedErrorBorder: border(SetupColors.error, w: 1.6),
  );
}

/// Label + text field. [fieldKey] lets the screen scroll to the first field that fails validation.
class SetupTextField extends StatelessWidget {
  const SetupTextField({
    super.key,
    required this.label,
    required this.controller,
    this.fieldKey,
    this.hint,
    this.required = false,
    this.optional = false,
    this.keyboardType,
    this.textInputAction = TextInputAction.next,
    this.validator,
    this.inputFormatters,
    this.maxLength,
    this.maxLines = 1,
    this.prefix,
    this.onChanged,
    this.helper,
    this.counter,
    this.readOnly = false,
    this.focusNode,
  });

  final String label;
  final TextEditingController controller;
  final GlobalKey<FormFieldState<String>>? fieldKey;
  final String? hint;
  final bool required;
  final bool optional;
  final TextInputType? keyboardType;
  final TextInputAction textInputAction;
  final String? Function(String?)? validator;
  final List<TextInputFormatter>? inputFormatters;
  final int? maxLength;
  final int maxLines;
  final Widget? prefix;
  final ValueChanged<String>? onChanged;
  final String? helper;
  final Widget? counter;
  final bool readOnly;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SetupLabel(label, required: required, optional: optional),
        TextFormField(
          key: fieldKey,
          controller: controller,
          focusNode: focusNode,
          readOnly: readOnly,
          keyboardType: keyboardType,
          textInputAction: maxLines > 1 ? TextInputAction.newline : textInputAction,
          validator: validator,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          inputFormatters: inputFormatters,
          maxLength: maxLength,
          maxLines: maxLines,
          minLines: maxLines > 1 ? maxLines : 1,
          onChanged: onChanged,
          style: setupText(size: 15),
          decoration: setupDecoration(hint: hint, prefix: prefix, filled: readOnly, counterText: ''),
        ),
        if (counter != null) Align(alignment: Alignment.centerRight, child: Padding(padding: const EdgeInsets.only(top: 4), child: counter)),
        if (helper != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(helper!, style: setupText(size: 12, color: SetupColors.secondary, height: 1.35))),
      ],
    );
  }
}

/// Label + dropdown, styled like [SetupTextField].
class SetupDropdown<T> extends StatelessWidget {
  const SetupDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.fieldKey,
    this.hint,
    this.required = false,
    this.validator,
  });

  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final GlobalKey<FormFieldState<T>>? fieldKey;
  final String? hint;
  final bool required;
  final String? Function(T?)? validator;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SetupLabel(label, required: required),
        DropdownButtonFormField<T>(
          key: fieldKey,
          initialValue: value,
          isExpanded: true,
          items: items,
          onChanged: onChanged,
          validator: validator,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          icon: const Icon(Icons.keyboard_arrow_down, color: SetupColors.text),
          dropdownColor: SetupColors.background,
          // A rounded white menu with a soft shadow, matching the field it opens from.
          borderRadius: BorderRadius.circular(12),
          menuMaxHeight: 320,
          elevation: 6,
          style: setupText(size: 15),
          hint: hint == null ? null : Text(hint!, style: setupText(size: 15, color: SetupColors.placeholder)),
          decoration: setupDecoration(),
        ),
      ],
    );
  }
}

/// Two or three pill options in one bordered row (Owned / Leased, Indoor / Outdoor).
class SetupSegmented<T> extends StatelessWidget {
  const SetupSegmented({super.key, required this.label, required this.value, required this.options, required this.onChanged, this.required = false, this.error, this.keyPrefix = 'seg'});

  final String label;
  final T? value;
  final List<({T value, String label})> options;
  final ValueChanged<T> onChanged;
  final bool required;
  final String? error;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SetupLabel(label, required: required),
        Container(
          height: 48,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(color: SetupColors.background, borderRadius: BorderRadius.circular(10), border: Border.all(color: error == null ? SetupColors.border : SetupColors.error)),
          child: Row(
            children: [
              for (final o in options)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: value == o.value,
                    label: o.label,
                    child: GestureDetector(
                      key: ValueKey('$keyPrefix-${o.label.toLowerCase()}'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onChanged(o.value),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: value == o.value ? SetupColors.activeBg : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: value == o.value ? Border.all(color: SetupColors.primary) : null,
                        ),
                        // scales down on a narrow phone instead of overflowing
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (value == o.value) ...[const Icon(Icons.check_circle, size: 16, color: SetupColors.primary), const SizedBox(width: 6)],
                              Text(o.label, style: setupText(size: 14, weight: FontWeight.w600, color: value == o.value ? SetupColors.primary : SetupColors.text)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(error!, key: ValueKey('$keyPrefix-error'), style: setupText(size: 12, weight: FontWeight.w500, color: SetupColors.error))),
      ],
    );
  }
}

/// A checkbox row with an "i" hint pinned to the right edge, so every row lines up whatever the label length.
class SetupCheckRow extends StatelessWidget {
  const SetupCheckRow({super.key, required this.label, required this.value, required this.onChanged, this.hint});

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
              height: 22,
              width: 22,
              child: Checkbox(
                value: value,
                onChanged: (v) => onChanged(v ?? false),
                activeColor: SetupColors.primary,
                side: const BorderSide(color: SetupColors.border, width: 1.6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: setupText(size: 14, weight: FontWeight.w500, height: 1.25))),
            if (hint != null)
              Tooltip(
                message: hint!,
                triggerMode: TooltipTriggerMode.tap,
                child: const Padding(padding: EdgeInsets.only(left: 8), child: Icon(Icons.info_outline, size: 18, color: SetupColors.secondary)),
              ),
          ],
        ),
      ),
    );
  }
}

class SetupErrorBanner extends StatelessWidget {
  const SetupErrorBanner(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFFDECEA), border: Border.all(color: const Color(0xFFF5B5B0)), borderRadius: BorderRadius.circular(10)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 18, color: SetupColors.error),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: setupText(size: 13, weight: FontWeight.w500, color: SetupColors.error, height: 1.35))),
        ],
      ),
    );
  }
}

/// Primary (filled purple) and secondary (outlined) buttons used in the footer.
class SetupButton extends StatelessWidget {
  const SetupButton({super.key, required this.label, required this.onPressed, this.primary = false, this.icon, this.trailingIcon, this.loading = false, this.loadingLabel});

  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final IconData? icon;
  final IconData? trailingIcon;
  final bool loading;
  final String? loadingLabel;

  @override
  Widget build(BuildContext context) {
    final fg = primary ? Colors.white : SetupColors.text;
    final content = loading
        ? Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: fg)),
            const SizedBox(width: 10),
            Text(loadingLabel ?? label, style: setupText(size: 15, weight: FontWeight.w600, color: fg)),
          ])
        : Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 18, color: fg), const SizedBox(width: 8)],
            Text(label, style: setupText(size: 15, weight: FontWeight.w600, color: fg)),
            if (trailingIcon != null) ...[const SizedBox(width: 8), Icon(trailingIcon, size: 18, color: fg)],
          ]);
    // Scales down on a very narrow phone instead of overflowing.
    final child = FittedBox(fit: BoxFit.scaleDown, child: content);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
    return SizedBox(
      height: 52,
      child: primary
          ? FilledButton(
              onPressed: loading ? null : onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: SetupColors.primary,
                disabledBackgroundColor: SetupColors.primary.withValues(alpha: 0.7),
                foregroundColor: Colors.white,
                shape: shape,
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ).copyWith(overlayColor: WidgetStatePropertyAll(SetupColors.primaryPressed.withValues(alpha: 0.35))),
              child: child,
            )
          : OutlinedButton(
              onPressed: loading ? null : onPressed,
              style: OutlinedButton.styleFrom(side: const BorderSide(color: SetupColors.border), foregroundColor: SetupColors.text, shape: shape, padding: const EdgeInsets.symmetric(horizontal: 12)),
              child: child,
            ),
    );
  }
}
