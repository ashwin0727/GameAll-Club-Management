import 'package:flutter/material.dart';

import '../theme/app_text_styles.dart';

/// Tells the text inside a button, link or card whether the mouse is over it. (Phones and tablets have no hover, so there it is
/// always false.) Nothing here paints a background: hovering never shades the surface, it only thickens the lettering a little.
class HoverScope extends InheritedWidget {
  const HoverScope({super.key, required this.hovered, required super.child});

  final bool hovered;

  static bool of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<HoverScope>()?.hovered ?? false;

  @override
  bool updateShouldNotify(HoverScope old) => old.hovered != hovered;
}

/// Watches the mouse over [child] and shares the result with every [HoverText] inside it. Use it around list tiles and other
/// widgets that are not already a `Pressable`.
class HoverRegion extends StatefulWidget {
  const HoverRegion({super.key, required this.child, this.clickable = true});

  final Widget child;

  /// Shows the pointing-hand cursor.
  final bool clickable;

  @override
  State<HoverRegion> createState() => _HoverRegionState();
}

class _HoverRegionState extends State<HoverRegion> {
  bool _hovered = false;

  void _set(bool v) {
    if (_hovered != v && mounted) setState(() => _hovered = v);
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: widget.clickable ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => _set(true),
        onExit: (_) => _set(false),
        child: HoverScope(hovered: _hovered, child: widget.child),
      );
}

/// Text that is a little lighter at rest and a little heavier while the mouse is over its button or link.
///
/// Manrope is a variable font, so the change is a smooth thickening of the strokes (not a jump between two fixed weights) and the
/// letter spacing stays put; the line does not reflow because the extra weight is small.
class HoverText extends StatelessWidget {
  const HoverText(
    this.text, {
    super.key,
    required this.style,
    this.hoverWeight,
    this.maxLines,
    this.overflow,
    this.textAlign,
    this.softWrap,
  });

  final String text;

  /// The resting style (its weight is the resting weight).
  final TextStyle style;

  /// The weight while hovered; by default 100 heavier than the resting weight (500 -> 600).
  final FontWeight? hoverWeight;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;
  final bool? softWrap;

  static FontWeight _heavier(FontWeight w) => FontWeight.values[(w.value ~/ 100).clamp(0, FontWeight.values.length - 1)];

  @override
  Widget build(BuildContext context) {
    final hovered = HoverScope.of(context);
    final resting = style.fontWeight ?? FontWeight.w400;
    final heavy = hoverWeight ?? _heavier(resting);
    TextStyle at(FontWeight w) => style.copyWith(fontWeight: w, fontVariations: [FontVariation('wght', w.value.toDouble())]);

    // The heavier lettering is a little wider. Reserve that width from the start, so thickening the text never nudges the
    // words next to it (it would otherwise shift a whole row of links by a pixel or two).
    final painter = TextPainter(
      text: TextSpan(text: text, style: at(heavy)),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: maxLines,
    )..layout();
    final reserved = painter.width.ceilToDouble();
    painter.dispose();

    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: reserved),
      child: AnimatedDefaultTextStyle(
        style: at(hovered ? heavy : resting),
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        maxLines: maxLines,
        overflow: overflow ?? TextOverflow.clip,
        textAlign: textAlign,
        softWrap: softWrap ?? true,
        child: Text(text, maxLines: maxLines, overflow: overflow, textAlign: textAlign, softWrap: softWrap),
      ),
    );
  }
}

/// The resting weights used for interactive text: lighter than before, so the hover thickening is noticeable.
class HoverWeights {
  const HoverWeights._();

  static const FontWeight link = FontWeight.w500;
  static const FontWeight button = FontWeight.w600;
  static const String family = AppTextStyles.fontFamily;
}
