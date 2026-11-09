import 'package:flutter/material.dart';

/// The GameAll Player colour tokens. One palette, defined once; widgets read the theme-aware [AppPalette] (`context.palette`) and
/// never hard-code a colour, so Dark and Light share one set of widgets.
class AppColors {
  const AppColors._();

  // Dark surfaces
  static const Color darkBackground = Color(0xFF050C19);
  static const Color darkSecondary = Color(0xFF09162A);
  static const Color darkSurface = Color(0xFF10213B);
  static const Color darkElevated = Color(0xFF162B49);

  // Brand
  static const Color cyan = Color(0xFF08BDF5);
  static const Color blue = Color(0xFF2878FF);
  static const Color violet = Color(0xFF7954F6);
  static const Color purple = Color(0xFFB65AF6);

  // Dark text and borders
  static const Color darkPrimaryText = Color(0xFFF5F8FF);
  static const Color darkSecondaryText = Color(0xFFAAB8D0);
  static const Color darkMutedText = Color(0xFF71839F);
  static const Color darkBorder = Color(0xFF263B59);

  // Light
  static const Color lightBackground = Color(0xFFF7F9FD);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSecondary = Color(0xFFEEF3FB);
  static const Color lightPrimaryText = Color(0xFF101B32);
  static const Color lightSecondaryText = Color(0xFF62718A);
  static const Color lightMutedText = Color(0xFF8A97AD);
  static const Color lightBorder = Color(0xFFE1E8F2);

  // Status
  static const Color success = Color(0xFF2ED993);
  static const Color warning = Color(0xFFFFC061);
  static const Color danger = Color(0xFFFF6B82);

  /// The brand gradient: used only for the main calls to action, the selected sport and the centre navigation button.
  static const LinearGradient brandGradient = LinearGradient(
    colors: [cyan, blue, violet],
  );

  /// Blue to violet, for the selected sport chip and the quick-action button.
  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [blue, violet],
  );
}

/// Everything that differs between the dark and the light theme.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.brightness,
    required this.background,
    required this.secondaryBackground,
    required this.surface,
    required this.elevated,
    required this.primaryText,
    required this.secondaryText,
    required this.mutedText,
    required this.border,
    required this.primary,
    required this.accent,
    required this.highlight,
  });

  final Brightness brightness;
  final Color background;
  final Color secondaryBackground;
  final Color surface;
  final Color elevated;
  final Color primaryText;
  final Color secondaryText;
  final Color mutedText;
  final Color border;

  /// Electric blue.
  final Color primary;

  /// Violet.
  final Color accent;

  /// Cyan (in light mode a slightly deeper cyan, so it stays readable on white).
  final Color highlight;

  bool get isDark => brightness == Brightness.dark;

  static const AppPalette dark = AppPalette(
    brightness: Brightness.dark,
    background: AppColors.darkBackground,
    secondaryBackground: AppColors.darkSecondary,
    surface: AppColors.darkSurface,
    elevated: AppColors.darkElevated,
    primaryText: AppColors.darkPrimaryText,
    secondaryText: AppColors.darkSecondaryText,
    mutedText: AppColors.darkMutedText,
    border: AppColors.darkBorder,
    primary: AppColors.blue,
    accent: AppColors.violet,
    highlight: AppColors.cyan,
  );

  static const AppPalette light = AppPalette(
    brightness: Brightness.light,
    background: AppColors.lightBackground,
    secondaryBackground: AppColors.lightSecondary,
    surface: AppColors.lightSurface,
    elevated: AppColors.lightSecondary,
    primaryText: AppColors.lightPrimaryText,
    secondaryText: AppColors.lightSecondaryText,
    mutedText: AppColors.lightMutedText,
    border: AppColors.lightBorder,
    primary: AppColors.blue,
    accent: AppColors.violet,
    highlight: Color(0xFF0597C8),
  );

  @override
  AppPalette copyWith({
    Brightness? brightness,
    Color? background,
    Color? secondaryBackground,
    Color? surface,
    Color? elevated,
    Color? primaryText,
    Color? secondaryText,
    Color? mutedText,
    Color? border,
    Color? primary,
    Color? accent,
    Color? highlight,
  }) {
    return AppPalette(
      brightness: brightness ?? this.brightness,
      background: background ?? this.background,
      secondaryBackground: secondaryBackground ?? this.secondaryBackground,
      surface: surface ?? this.surface,
      elevated: elevated ?? this.elevated,
      primaryText: primaryText ?? this.primaryText,
      secondaryText: secondaryText ?? this.secondaryText,
      mutedText: mutedText ?? this.mutedText,
      border: border ?? this.border,
      primary: primary ?? this.primary,
      accent: accent ?? this.accent,
      highlight: highlight ?? this.highlight,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      brightness: t < 0.5 ? brightness : other.brightness,
      background: Color.lerp(background, other.background, t)!,
      secondaryBackground: Color.lerp(
        secondaryBackground,
        other.secondaryBackground,
        t,
      )!,
      surface: Color.lerp(surface, other.surface, t)!,
      elevated: Color.lerp(elevated, other.elevated, t)!,
      primaryText: Color.lerp(primaryText, other.primaryText, t)!,
      secondaryText: Color.lerp(secondaryText, other.secondaryText, t)!,
      mutedText: Color.lerp(mutedText, other.mutedText, t)!,
      border: Color.lerp(border, other.border, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      highlight: Color.lerp(highlight, other.highlight, t)!,
    );
  }
}

extension AppPaletteContext on BuildContext {
  /// The current theme's palette.
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.dark;
}
