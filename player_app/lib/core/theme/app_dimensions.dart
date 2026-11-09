import 'package:flutter/material.dart';

/// Spacing, radii and sizes of the GameAll Play design (logical pixels). The mobile design is built on a 390dp-wide screen.
class AppDimensions {
  const AppDimensions._();

  static const double screenPadding = 16;
  static const double sectionSpacing = 20;
  static const double cardSpacing = 12;

  static const double cardRadius = 18;
  static const double buttonRadius = 24;
  static const double searchRadius = 25;
  static const double chipRadius = 13;

  static const double buttonHeight = 48;
  static const double minTouchTarget = 48;
  static const double searchHeight = 50;
  static const double heroHeight = 230;
  static const double shortcutHeight = 145;
  static const double sportIconBox = 44;
  static const double bottomNavHeight = 72;
  static const double quickButton = 52;

  /// Screens wider than this show the desktop (web) layout instead of the phone layout.
  static const double desktopBreakpoint = 840;

  /// The widest the phone layout is allowed to get when it is shown on a tablet or a narrow browser window.
  static const double phoneMaxWidth = 560;

  /// The side margin of the wide (web) layout, shared by the brand bar and the page body so they line up: about 5% of the
  /// window width, never less than 32 or more than 120.
  static double desktopSidePadding(double width) =>
      (width * 0.05).clamp(32.0, 120.0);

  static const BorderRadius cardBorderRadius = BorderRadius.all(
    Radius.circular(cardRadius),
  );
}
