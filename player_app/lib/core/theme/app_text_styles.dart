import 'package:flutter/material.dart';

/// The Manrope type scale of the Player app. The font is bundled (assets/fonts), so it renders the same offline, on the web and
/// on every phone. Colours come from the palette, so the same style is correct in Dark and Light.
///
/// Every style stays subject to the system font scale (nothing is fixed-height).
class AppTextStyles {
  const AppTextStyles._();

  static const String fontFamily = 'Manrope';

  /// Manrope is a variable font: the weight is an axis of one file, so the weight is passed both as the Flutter weight and as the
  /// `wght` variation. Material widgets that only set a [FontWeight] are mapped by the pubspec font declaration.
  static TextStyle _style(double size, FontWeight weight, Color color, {double? height, double? letterSpacing}) => TextStyle(
        fontFamily: fontFamily,
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
        letterSpacing: letterSpacing,
        fontVariations: [FontVariation('wght', weight.value.toDouble())],
      );

  static TextStyle greeting(Color c) => _style(26, FontWeight.w700, c, height: 1.2);
  static TextStyle heroHeading(Color c) => _style(25, FontWeight.w800, c, height: 1.15);
  static TextStyle desktopHeroHeading(Color c) => _style(52, FontWeight.w800, c, height: 1.08);
  static TextStyle sectionHeading(Color c) => _style(19, FontWeight.w700, c);
  static TextStyle cardHeading(Color c) => _style(15, FontWeight.w700, c, height: 1.25);
  static TextStyle shortcutHeading(Color c) => _style(14, FontWeight.w600, c, height: 1.25);
  static TextStyle body(Color c) => _style(14, FontWeight.w500, c, height: 1.4);
  static TextStyle support(Color c) => _style(13, FontWeight.w400, c, height: 1.4);
  static TextStyle button(Color c) => _style(14, FontWeight.w600, c);
  static TextStyle navLabel(Color c) => _style(11, FontWeight.w500, c);
  static TextStyle meta(Color c) => _style(11, FontWeight.w500, c);
  static TextStyle eyebrow(Color c) => _style(11, FontWeight.w700, c, letterSpacing: 2.2);

  /// A Material [TextTheme] built on the same scale, so widgets that read `Theme.of(context).textTheme` look right too.
  static TextTheme textTheme(Color primary, Color secondary) => TextTheme(
        headlineMedium: greeting(primary),
        titleLarge: sectionHeading(primary),
        titleMedium: cardHeading(primary),
        titleSmall: shortcutHeading(primary),
        bodyLarge: body(primary),
        bodyMedium: body(primary),
        bodySmall: support(secondary),
        labelLarge: button(primary),
        labelMedium: navLabel(secondary),
        labelSmall: meta(secondary),
      );
}
