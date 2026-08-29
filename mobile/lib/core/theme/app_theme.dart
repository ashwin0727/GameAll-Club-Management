import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_radius.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

/// GameAll Design System 2026 — one centralized Material 3 theme, built
/// twice (light + dark) from the same [AppColorTokens] source so both
/// stay in lockstep. Dark is the primary visual direction (spec); light is
/// a proper, independently-tuned palette rather than a naive inversion.
class AppTheme {
  const AppTheme._();

  static ThemeData light() => _build(AppColorTokens.light, Brightness.light);

  static ThemeData dark() => _build(AppColorTokens.dark, Brightness.dark);

  static ThemeData _build(AppColorTokens tokens, Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: tokens.primary,
      brightness: brightness,
      primary: tokens.primary,
      onPrimary: tokens.onPrimary,
      surface: tokens.surface1,
      onSurface: tokens.textPrimary,
      error: tokens.destructive,
    );

    final textTheme = AppTypography.textTheme(primaryText: tokens.textPrimary, secondaryText: tokens.textSecondary);
    final base = ThemeData(colorScheme: colorScheme, useMaterial3: true, brightness: brightness, textTheme: textTheme);

    return base.copyWith(
      scaffoldBackgroundColor: tokens.surface0,
      extensions: [tokens],
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: tokens.surface0,
        foregroundColor: tokens.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: tokens.surface1,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: tokens.borderColor),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: tokens.primary,
          foregroundColor: tokens.onPrimary,
          disabledBackgroundColor: tokens.primary.withValues(alpha: 0.35),
          disabledForegroundColor: tokens.onPrimary.withValues(alpha: 0.6),
          minimumSize: const Size.fromHeight(AppSpacing.huge),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
          textStyle: textTheme.labelLarge?.copyWith(fontSize: 15, fontWeight: FontWeight.w700),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(AppSpacing.huge),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          side: BorderSide(color: tokens.borderColor),
          foregroundColor: tokens.textPrimary,
          backgroundColor: tokens.surface2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, AppSpacing.huge),
          foregroundColor: tokens.primary,
          textStyle: textTheme.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(AppSpacing.huge, AppSpacing.huge),
          foregroundColor: tokens.textPrimary,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: tokens.surface2,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        labelStyle: TextStyle(color: tokens.textSecondary),
        hintStyle: TextStyle(color: tokens.textSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: tokens.borderColor),
        ),
        // GameAll Green ring on focus (spec §"Borders": "Focused: GameAll
        // Green glow/ring") — a clearly stronger 2px border stands in for a
        // literal glow here since InputBorder can't paint a soft shadow.
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: tokens.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: tokens.destructive),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: tokens.destructive, width: 2),
        ),
      ),
      dividerTheme: DividerThemeData(color: tokens.borderColor, space: 1, thickness: 1),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: tokens.surface1,
        selectedItemColor: tokens.primary,
        unselectedItemColor: tokens.textSecondary,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: tokens.surface1,
        indicatorColor: tokens.primary.withValues(alpha: 0.16),
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return textTheme.labelSmall?.copyWith(color: selected ? tokens.primary : tokens.textSecondary, fontWeight: selected ? FontWeight.w700 : FontWeight.w500);
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(color: selected ? tokens.primary : tokens.textSecondary);
        }),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: tokens.surface2,
        selectedColor: tokens.primary.withValues(alpha: 0.16),
        labelStyle: TextStyle(color: tokens.textPrimary),
        secondaryLabelStyle: TextStyle(color: tokens.onPrimary),
        side: BorderSide(color: tokens.borderColor),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          side: BorderSide(color: tokens.borderColor),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: tokens.surface3,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: tokens.surface3,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xxl)),
        ),
        showDragHandle: true,
        dragHandleColor: tokens.borderColor,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: tokens.surface4,
        contentTextStyle: TextStyle(color: tokens.textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: tokens.primary),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? tokens.onPrimary : tokens.textSecondary),
        trackColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? tokens.primary : tokens.surface2),
      ),
    );
  }
}