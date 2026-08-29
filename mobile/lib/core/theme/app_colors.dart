import 'package:flutter/material.dart';

/// GameAll Design System 2026 — brand palette.
///
/// [AppColors] stays a plain static class (not context-aware) for backward
/// compatibility: every screen written before this redesign references
/// `AppColors.xxx` directly rather than `Theme.of(context)`, and rewriting
/// every one of those call sites is out of scope for this pass (see
/// [AppColorTokens] below for the properly theme-aware path new/redesigned
/// screens should use instead). These statics are fixed to the DARK theme's
/// values, since dark is this design system's primary direction (spec:
/// "Dark theme is the primary visual direction") — every screen not yet
/// migrated to [AppColorTokens] renders correctly against `AppTheme.dark()`
/// and only needs a follow-up pass to become properly light/dark-aware.
class AppColors {
  const AppColors._();

  // ── Brand ──────────────────────────────────────────────────────────────
  static const Color primary = Color(0xFF00F08A); // GameAll Green
  static const Color primaryDark = Color(0xFF00C773);
  static const Color onPrimary = Color(0xFF07101F); // Deep Navy — dark text on green (spec: "Dark text where contrast is appropriate")
  static const Color electricBlue = Color(0xFF5B6CFF);
  static const Color violet = Color(0xFF8B5CF6);

  // ── Status ─────────────────────────────────────────────────────────────
  static const Color success = Color(0xFF00D084);
  static const Color warning = Color(0xFFFFB020);
  static const Color destructive = Color(0xFFFF4D67);
  static const Color info = Color(0xFF5B6CFF);

  // ── Surfaces (dark — the default) ─────────────────────────────────────
  static const Color background = Color(0xFF07101F); // Surface 0 — Deep Navy
  static const Color card = Color(0xFF0C1628); // Surface 1 — Dark Surface
  static const Color cardElevated = Color(0xFF111D31); // Surface 2 — Elevated Surface
  static const Color surfaceModal = Color(0xFF16233A); // Surface 3 — bottom sheets/dialogs
  static const Color surfaceFloating = Color(0xFF1C2B45); // Surface 4 — floating controls

  /// Legacy alias — most existing screens reach for `AppColors.mutedBackground`
  /// for a subtly-tinted input/chip fill; keep it pointed at the same
  /// surface a freshly-written screen would use.
  static const Color mutedBackground = cardElevated;

  // ── Text ───────────────────────────────────────────────────────────────
  static const Color foreground = Color(0xFFF8FAFC); // Text Primary Dark
  static const Color muted = Color(0xFFAAB5C7); // Text Secondary Dark

  // ── Borders ────────────────────────────────────────────────────────────
  static const Color border = Color(0xFF20304A); // Border Dark
}

/// The theme-aware token set — everything [AppColors] can't express because
/// it differs between light and dark. New/redesigned screens should prefer
/// `context.tokens.xxx` over the static `AppColors.xxx` so they render
/// correctly in BOTH themes rather than only the dark default.
@immutable
class AppColorTokens extends ThemeExtension<AppColorTokens> {
  const AppColorTokens({
    required this.surface0,
    required this.surface1,
    required this.surface2,
    required this.surface3,
    required this.surface4,
    required this.textPrimary,
    required this.textSecondary,
    required this.borderColor,
    required this.primary,
    required this.onPrimary,
    required this.success,
    required this.warning,
    required this.destructive,
    required this.info,
    required this.electricBlue,
    required this.violet,
  });

  final Color surface0;
  final Color surface1;
  final Color surface2;
  final Color surface3;
  final Color surface4;
  final Color textPrimary;
  final Color textSecondary;
  final Color borderColor;
  final Color primary;
  final Color onPrimary;
  final Color success;
  final Color warning;
  final Color destructive;
  final Color info;
  final Color electricBlue;
  final Color violet;

  static const dark = AppColorTokens(
    surface0: Color(0xFF07101F),
    surface1: Color(0xFF0C1628),
    surface2: Color(0xFF111D31),
    surface3: Color(0xFF16233A),
    surface4: Color(0xFF1C2B45),
    textPrimary: Color(0xFFF8FAFC),
    textSecondary: Color(0xFFAAB5C7),
    borderColor: Color(0xFF20304A),
    primary: Color(0xFF00F08A),
    onPrimary: Color(0xFF07101F),
    success: Color(0xFF00D084),
    warning: Color(0xFFFFB020),
    destructive: Color(0xFFFF4D67),
    info: Color(0xFF5B6CFF),
    electricBlue: Color(0xFF5B6CFF),
    violet: Color(0xFF8B5CF6),
  );

  static const light = AppColorTokens(
    surface0: Color(0xFFF8FAFC),
    surface1: Color(0xFFFFFFFF),
    surface2: Color(0xFFF1F5F9),
    surface3: Color(0xFFFFFFFF),
    surface4: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF101828),
    textSecondary: Color(0xFF667085),
    borderColor: Color(0xFFE4E7EC),
    // Same GameAll Green in both themes — one brand color, never
    // reinterpreted per-theme (spec gives a single canonical hex). Its
    // on-primary pairing (dark text/icons on top) keeps it legible as a
    // button/badge fill against white exactly as it does against navy.
    primary: Color(0xFF00F08A),
    onPrimary: Color(0xFF07101F),
    success: Color(0xFF00A76A),
    warning: Color(0xFFB25E00),
    destructive: Color(0xFFE0193F),
    info: Color(0xFF3D4FE0),
    electricBlue: Color(0xFF3D4FE0),
    violet: Color(0xFF7C4DE0),
  );

  @override
  AppColorTokens copyWith({
    Color? surface0,
    Color? surface1,
    Color? surface2,
    Color? surface3,
    Color? surface4,
    Color? textPrimary,
    Color? textSecondary,
    Color? borderColor,
    Color? primary,
    Color? onPrimary,
    Color? success,
    Color? warning,
    Color? destructive,
    Color? info,
    Color? electricBlue,
    Color? violet,
  }) {
    return AppColorTokens(
      surface0: surface0 ?? this.surface0,
      surface1: surface1 ?? this.surface1,
      surface2: surface2 ?? this.surface2,
      surface3: surface3 ?? this.surface3,
      surface4: surface4 ?? this.surface4,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      borderColor: borderColor ?? this.borderColor,
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      destructive: destructive ?? this.destructive,
      info: info ?? this.info,
      electricBlue: electricBlue ?? this.electricBlue,
      violet: violet ?? this.violet,
    );
  }

  @override
  AppColorTokens lerp(ThemeExtension<AppColorTokens>? other, double t) {
    if (other is! AppColorTokens) return this;
    return AppColorTokens(
      surface0: Color.lerp(surface0, other.surface0, t)!,
      surface1: Color.lerp(surface1, other.surface1, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      surface3: Color.lerp(surface3, other.surface3, t)!,
      surface4: Color.lerp(surface4, other.surface4, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      borderColor: Color.lerp(borderColor, other.borderColor, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      destructive: Color.lerp(destructive, other.destructive, t)!,
      info: Color.lerp(info, other.info, t)!,
      electricBlue: Color.lerp(electricBlue, other.electricBlue, t)!,
      violet: Color.lerp(violet, other.violet, t)!,
    );
  }
}

/// Ergonomic, theme-aware access: `context.tokens.surface2`,
/// `context.tokens.textSecondary`, etc. Falls back to [AppColorTokens.dark]
/// only if a screen somehow renders outside of [AppTheme] entirely (should
/// never happen in practice — both `AppTheme.light()`/`.dark()` always
/// register this extension).
extension AppColorTokensX on BuildContext {
  AppColorTokens get tokens => Theme.of(this).extension<AppColorTokens>() ?? AppColorTokens.dark;
}