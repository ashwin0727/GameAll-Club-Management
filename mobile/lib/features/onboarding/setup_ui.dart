import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
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
  static const Color skeleton = Color(0xFFEEEAF7);
}

final Map<int, TextStyle> _setupTextCache = <int, TextStyle>{};

/// Inter (bundled with the app) at the requested size, weight and colour. A screen asks for the same handful of styles hundreds of
/// times per build, so each distinct style is created once and reused.
TextStyle setupText({double size = 14, FontWeight weight = FontWeight.w400, Color color = SetupColors.text, double? height}) {
  final key = Object.hash(size, weight.value, color.toARGB32(), height);
  return _setupTextCache[key] ??= TextStyle(fontFamily: 'Inter', fontSize: size, fontWeight: weight, color: color, height: height);
}

/// Back: returns to the previous step exactly as it was left (nothing is rebuilt or reloaded). Only when there is nothing to go back
/// to (the app was opened straight on this step) does it open [fallback].
void goBackOr(BuildContext context, String fallback) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(fallback);
  }
}

/// The shared page: white ground, GameAll logo + "Need Help?" on top, scrolling body, pinned footer.
class SetupPage extends StatelessWidget {
  const SetupPage({super.key, required this.children, required this.footer, this.scrollController});

  final List<Widget> children;
  final Widget footer;
  final ScrollController? scrollController;

  static const double maxWidth = 640;

  // Built once: ColorScheme.fromSeed does real colour maths, which is wasted work on every keystroke.
  static final ColorScheme _scheme = ColorScheme.fromSeed(seedColor: SetupColors.primary, brightness: Brightness.light, primary: SetupColors.primary, surface: SetupColors.background);
  static const TextSelectionThemeData _selection = TextSelectionThemeData(cursorColor: SetupColors.primary, selectionHandleColor: SetupColors.primary);

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(brightness: Brightness.light, scaffoldBackgroundColor: SetupColors.background, colorScheme: _scheme, textSelectionTheme: _selection),
      child: Scaffold(
        backgroundColor: SetupColors.background,
        body: SafeArea(
          child: Column(
            children: [
              const SetupHeader(),
              Expanded(
                // Top-aligned: a short page (or a loading page) sits at the top like the full one, never floating in the middle.
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: maxWidth),
                    child: SingleChildScrollView(
                      controller: scrollController,
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
                    ),
                  ),
                ),
              ),
              // A slim bar: one row of buttons, no extra lines, so the content keeps the screen.
              DecoratedBox(
                decoration: const BoxDecoration(color: SetupColors.background, border: Border(top: BorderSide(color: SetupColors.border))),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Center(
                    heightFactor: 1,
                    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: maxWidth), child: footer),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The footer every setup step uses: Back (left, narrow) and the main action (right, wide), one slim row.
class SetupNavFooter extends StatelessWidget {
  const SetupNavFooter({super.key, required this.onBack, required this.next, this.backLabel = 'Back'});

  final VoidCallback? onBack;
  final Widget next;
  final String backLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: SetupButton(label: backLabel, icon: Icons.arrow_back, onPressed: onBack)),
        const SizedBox(width: 12),
        Expanded(flex: 2, child: next),
      ],
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
              child: ExcludeSemantics(child: Image.asset('assets/images/gameall_logo_light.png', height: 34, cacheHeight: 150, fit: BoxFit.contain, alignment: Alignment.centerLeft, filterQuality: FilterQuality.high)),
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

/// Label + dropdown, styled like [SetupTextField] and like the website's select: a rounded field that always shows the current value, and
/// a list of every option that opens from the bottom of the screen with the chosen one highlighted and ticked. A long list (states,
/// banks) gets a search box. It is driven by [value], so a value set by the screen (a prefill, Back) always shows, and its validator
/// always sees the current value.
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

  static String _labelOf<T>(DropdownMenuItem<T> item) {
    final child = item.child;
    if (child is Text) return child.data ?? child.textSpan?.toPlainText() ?? '';
    return '${item.value}';
  }

  @override
  Widget build(BuildContext context) {
    final options = [for (final i in items) (value: i.value as T, label: _labelOf(i))];
    final selected = options.where((o) => o.value == value).firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SetupLabel(label, required: required),
        FormField<T>(
          key: fieldKey,
          initialValue: value,
          // always judge what the screen holds now, not what the field last heard about
          validator: validator == null ? null : (_) => validator!(value),
          autovalidateMode: AutovalidateMode.onUserInteraction,
          builder: (state) {
            final hasError = state.hasError;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  button: true,
                  label: selected == null ? label : '$label, ${selected.label}',
                  child: Material(
                    color: SetupColors.background,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: hasError ? SetupColors.error : SetupColors.border)),
                    child: InkWell(
                      key: ValueKey('select-$label'),
                      borderRadius: BorderRadius.circular(10),
                      onTap: () async {
                        final picked = await showSetupOptionSheet<T>(context, title: label, options: options, selected: value);
                        if (picked == null) return;
                        state.didChange(picked.value);
                        onChanged(picked.value);
                      },
                      child: Container(
                        height: 48,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                selected?.label ?? hint ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: setupText(size: 15, color: selected == null ? SetupColors.placeholder : SetupColors.text),
                              ),
                            ),
                            const Icon(Icons.keyboard_arrow_down, color: SetupColors.text),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (hasError) Padding(padding: const EdgeInsets.only(top: 6), child: Text(state.errorText ?? '', style: setupText(size: 12, weight: FontWeight.w500, color: SetupColors.error, height: 1.3))),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// The option list behind a [SetupDropdown]. Returns the chosen option, or null when it is dismissed. [searchAbove] options or more
/// adds a search box.
Future<({T value, String label})?> showSetupOptionSheet<T>(
  BuildContext context, {
  required String title,
  required List<({T value, String label})> options,
  required T? selected,
  int searchAbove = 8,
}) {
  return showModalBottomSheet<({T value, String label})>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false, // the list draws its own handle
    backgroundColor: SetupColors.background,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (sheetContext) => _OptionSheet<T>(title: title, options: options, selected: selected, searchable: options.length > searchAbove),
  );
}

class _OptionSheet<T> extends StatefulWidget {
  const _OptionSheet({required this.title, required this.options, required this.selected, required this.searchable});

  final String title;
  final List<({T value, String label})> options;
  final T? selected;
  final bool searchable;

  @override
  State<_OptionSheet<T>> createState() => _OptionSheetState<T>();
}

class _OptionSheetState<T> extends State<_OptionSheet<T>> {
  static const double _rowHeight = 52;
  final _search = TextEditingController();
  late final ScrollController _scroll;
  String _query = '';

  @override
  void initState() {
    super.initState();
    // opens with the chosen row in view
    final index = widget.options.indexWhere((o) => o.value == widget.selected);
    _scroll = ScrollController(initialScrollOffset: index <= 2 ? 0 : (index - 2) * _rowHeight);
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = _query.isEmpty ? widget.options : widget.options.where((o) => o.label.toLowerCase().contains(_query)).toList();
    final screen = MediaQuery.of(context).size.height;
    final keyboard = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: screen * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(height: 4, width: 40, decoration: BoxDecoration(color: SetupColors.border, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
              child: Align(alignment: Alignment.centerLeft, child: Text(widget.title, style: setupText(size: 17, weight: FontWeight.w600))),
            ),
            if (widget.searchable)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: _search,
                  onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                  style: setupText(size: 15),
                  decoration: setupDecoration(hint: 'Search', prefix: const Padding(padding: EdgeInsets.only(left: 12, right: 8), child: Icon(Icons.search, size: 20, color: SetupColors.secondary))),
                ),
              ),
            Flexible(
              child: shown.isEmpty
                  ? Padding(padding: const EdgeInsets.all(28), child: Text('No matches', style: setupText(size: 14, color: SetupColors.secondary)))
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                      itemExtent: _rowHeight,
                      itemCount: shown.length,
                      itemBuilder: (context, i) {
                        final o = shown[i];
                        final isSelected = o.value == widget.selected;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Material(
                            color: isSelected ? SetupColors.activeBg : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => Navigator.of(context).pop(o),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        o.label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: setupText(size: 15, weight: isSelected ? FontWeight.w600 : FontWeight.w400, color: isSelected ? SetupColors.primary : SetupColors.text),
                                      ),
                                    ),
                                    if (isSelected) const Icon(Icons.check, size: 20, color: SetupColors.primary),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
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
      height: 48,
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

/// A flat placeholder block for [SetupLoadingPage]. Its colour is painted by the one shimmer above it.
class SetupSkeletonBox extends StatelessWidget {
  const SetupSkeletonBox({super.key, this.width, this.height = 14, this.radius = 8});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(width: width, height: height, decoration: BoxDecoration(color: SetupColors.skeleton, borderRadius: BorderRadius.circular(radius)));
}

/// One sweep of light across everything inside it. A single controller and a single shader for the whole loading page, however many
/// placeholder blocks it holds (a controller per block is what makes naive skeletons janky). With "remove animations" it stays still.
class SetupShimmer extends StatefulWidget {
  const SetupShimmer({super.key, required this.child});

  final Widget child;

  @override
  State<SetupShimmer> createState() => _SetupShimmerState();
}

class _SetupShimmerState extends State<SetupShimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (rect) {
          final dx = rect.width * (_c.value * 3 - 1);
          return LinearGradient(
            colors: const [Color(0x00FFFFFF), Color(0x99FFFFFF), Color(0x00FFFFFF)],
            stops: const [0.0, 0.5, 1.0],
          ).createShader(Rect.fromLTWH(dx, 0, rect.width, rect.height));
        },
        child: child,
      ),
    );
  }
}

/// What a setup step shows while its data loads: the real page chrome (logo, slim footer) around placeholders shaped like the content that
/// is coming, so nothing jumps when it arrives. No spinner, no "Step X of 5" floating in the middle of the screen.
class SetupLoadingPage extends StatelessWidget {
  const SetupLoadingPage({super.key, this.cards = const [3, 3, 2]});

  /// How many fields each placeholder card has.
  final List<int> cards;

  @override
  Widget build(BuildContext context) {
    return SetupPage(
      footer: Row(
        children: const [
          Expanded(child: SetupShimmer(child: SetupSkeletonBox(height: 48, radius: 12))),
          SizedBox(width: 12),
          Expanded(flex: 2, child: SetupShimmer(child: SetupSkeletonBox(height: 48, radius: 12))),
        ],
      ),
      children: [
        Semantics(
          label: 'Loading',
          liveRegion: true,
          child: SetupShimmer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // the stepper
                const SetupSkeletonBox(width: 150, height: 12),
                const SizedBox(height: 10),
                Row(children: [for (var i = 0; i < 5; i++) ...[const Expanded(child: SetupSkeletonBox(height: 5, radius: 99)), if (i < 4) const SizedBox(width: 5)]]),
                const SizedBox(height: 22),
                // the heading and its line
                const SetupSkeletonBox(width: 210, height: 28, radius: 8),
                const SizedBox(height: 10),
                const SetupSkeletonBox(height: 13),
                const SizedBox(height: 6),
                const SetupSkeletonBox(width: 240, height: 13),
                const SizedBox(height: 20),
                for (final fields in cards) ...[
                  _SkeletonCard(fields: fields),
                  const SizedBox(height: 16),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard({required this.fields});

  final int fields;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(border: Border.all(color: SetupColors.border), borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SetupSkeletonBox(width: 150, height: 18),
          const SizedBox(height: 16),
          for (var i = 0; i < fields; i++) ...[
            const SetupSkeletonBox(width: 90, height: 12),
            const SizedBox(height: 8),
            const SetupSkeletonBox(height: 46, radius: 10),
            if (i < fields - 1) const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}
