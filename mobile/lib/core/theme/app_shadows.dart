import 'package:flutter/material.dart';

/// Centralized elevation. Cards default to flat + border (see AppTheme's
/// cardTheme) — "surface hierarchy via border" reads cleaner on mobile than
/// a floating box per card. These soft shadows are reserved for surfaces
/// that genuinely sit above the page: bottom sheets, dialogs, a selected
/// booking slot.
class AppShadows {
  const AppShadows._();

  static const List<BoxShadow> soft = [
    BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 4)),
  ];

  static const List<BoxShadow> elevated = [
    BoxShadow(color: Color(0x1F000000), blurRadius: 24, offset: Offset(0, 8)),
  ];

  /// The GameAll Green "focus ring" glow (spec: "Focused: GameAll Green
  /// glow/ring") — used behind a focused input or a selected booking slot,
  /// never as a permanent/idle decoration.
  static List<BoxShadow> focusGlow(Color primary) => [
    BoxShadow(color: primary.withValues(alpha: 0.28), blurRadius: 16, spreadRadius: 1),
  ];
}