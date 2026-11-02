import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_dimensions.dart';
import 'app_text_styles.dart';

/// Dark (the primary direction) and Light themes. Both are built by one function from an [AppPalette], so they cannot drift apart.
class AppTheme {
  const AppTheme._();

  static ThemeData dark() => _build(AppPalette.dark);
  static ThemeData light() => _build(AppPalette.light);

  static ThemeData _build(AppPalette p) {
    final scheme = (p.isDark ? const ColorScheme.dark() : const ColorScheme.light()).copyWith(
      primary: p.primary,
      secondary: p.isDark ? p.highlight : p.accent,
      surface: p.surface,
      onSurface: p.primaryText,
      onPrimary: Colors.white,
      outline: p.border,
      error: AppColors.danger,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: p.brightness,
      fontFamily: AppTextStyles.fontFamily,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.background,
      canvasColor: p.background,
      // Hovering or pressing never shades a surface; interactive text changes weight instead (see HoverText).
      hoverColor: Colors.transparent,
      highlightColor: Colors.transparent,
      splashColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,
      textButtonTheme: TextButtonThemeData(style: ButtonStyle(overlayColor: WidgetStateProperty.all(Colors.transparent))),
      listTileTheme: const ListTileThemeData(),
      dividerColor: p.border,
      textTheme: AppTextStyles.textTheme(p.primaryText, p.secondaryText),
      extensions: [p],
      cardTheme: CardThemeData(
        color: p.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: AppDimensions.cardBorderRadius, side: BorderSide(color: p.border)),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: p.background,
        foregroundColor: p.primaryText,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.secondaryBackground,
        modalBackgroundColor: p.secondaryBackground,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.elevated,
        contentTextStyle: AppTextStyles.body(p.primaryText),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
