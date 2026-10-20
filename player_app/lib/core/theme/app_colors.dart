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
  static const Color primary = Color(0xFF00F08A); // GameAll Green (dark ground)
  static const Color primaryDark = Color(0xFF00C77A);
  static const Color onPrimary = Color(0xFF06110B); // near-black green — dark text/icons on green fills
  static const Color electricBlue = Color(0xFF7E93FF);
  static const Color violet = Color(0xFFA98CFF);

  // ── Status ─────────────────────────────────────────────────────────────
  static const Color success = Color(0xFF2ED993);
  static const Color warning = Color(0xFFFFC061);
  static const Color destructive = Color(0xFFFF6B82);
  static const Color info = Color(0xFF7E93FF);

  // ── Surfaces (dark — the default) ─────────────────────────────────────
  // Neutral graphite near-black ground — no colour cast (tried a green
  // tint to match the hero photography; it read as weird/off, reverted).
  static const Color background = Color(0xFF0E0E10); // Surface 0 — near-black graphite
  static const Color card = Color(0xFF17171A); // Surface 1 — cards
  static const Color cardElevated = Color(0xFF1F1F23); // Surface 2 — nav, chips, quiet tiles
  static const Color surfaceModal = Color(0xFF27272C); // Surface 3 — bottom sheets/dialogs
  static const Color surfaceFloating = Color(0xFF313136); // Surface 4 — floating controls

  /// Legacy alias — most existing screens reach for `AppColors.mutedBackground`
  /// for a subtly-tinted input/chip fill; keep it pointed at the same
  /// surface a freshly-written screen would use.
  static const Color mutedBackground = cardElevated;

  // ── Text ───────────────────────────────────────────────────────────────
  static const Color foreground = Color(0xFFF4F7FA); // Text Primary Dark
  static const Color muted = Color(0xFF93A1B3); // Text Secondary Dark

  // ── Borders ────────────────────────────────────────────────────────────
  static const Color border = Color(0xFF2E2E33); // Border Dark — neutral graphite hairline
}

/// The theme-aware token set — everything [AppColors] can't express because
/// it differs between light and dark. New/redesigned screens should prefer
/// `context.tokens.xxx` over the static `AppColors.xxx` so they render
/// correctly in BOTH themes rather than only the dark default.
@immutable
class AppColorTokens extends ThemeExtension<AppColorTokens> {
  const AppColorTokens({
    required this.brightness,
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

  final Brightness brightness;
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

  bool get isLight => brightness == Brightness.light;

  /// A SOLID (fully opaque) accent-tinted card fill. Replaces the washed
  /// translucent gradients that read as "barely coloured" on a light
  /// ground — the tint is alpha-blended onto [surface1] so the card is a
  /// definite colour in both themes, like a filled button is.
  Color accentFill(Color accent) => Color.alphaBlend(
        accent.withValues(alpha: isLight ? 0.12 : 0.14), surface1);

  /// A slightly stronger solid tint — for the top of a card or a header
  /// band where a touch more presence is wanted.
  Color accentFillStrong(Color accent) => Color.alphaBlend(
        accent.withValues(alpha: isLight ? 0.20 : 0.22), surface1);

  /// A solid, opaque border that matches [accentFill].
  Color accentEdge(Color accent) => Color.alphaBlend(
        accent.withValues(alpha: isLight ? 0.55 : 0.45), surface1);

  /// Solid fill for a small pill / icon chip sitting on an accent card.
  Color accentChip(Color accent) => Color.alphaBlend(
        accent.withValues(alpha: isLight ? 0.18 : 0.22), surface1);

  /// A solid accent fill — the accent colour, deepened just enough that
  /// WHITE text and icons always read on it (WCAG-AA). Already-deep
  /// accents pass through unchanged. The point of the deepening is
  /// consistency: every solid accent card in the app then uses ONE
  /// content colour (white) instead of some tiles white and some black.
  Color accentSolid(Color accent) {
    // The "attention / money owed" accent gets a dedicated marigold fill in
    // BOTH themes. The `warning` token itself is tuned to be legible as
    // TEXT (a deep mustard on white, a pale amber on black) and neither
    // value works as a card fill — the light one reads as muddy brown, the
    // dark one is too pale to take a label. Marigold is the fill; it is the
    // one accent that carries dark ink rather than white (see [onAccent]),
    // because white on gold is ~1.7:1 and simply unreadable.
    if (accent == warning) return const Color(0xFFF7BD4E);

    if (isLight) {
      // Light-mode accent tokens are deep for text legibility; used as a
      // full card fill they read as a dark slab. Ease ~18% toward white —
      // the card stays clearly coloured but lighter, and white labels and
      // icons still pass AA (they are bold).
      return Color.lerp(accent, const Color(0xFFFFFFFF), 0.18)!;
    }
    // Dark mode: deepen a too-bright accent until white text reads on it.
    if (accent.computeLuminance() <= 0.32) return accent;
    final hsl = HSLColor.fromColor(accent);
    var l = hsl.lightness;
    var deep = accent;
    while (l > 0.14) {
      l -= 0.03;
      deep = hsl.withLightness(l).toColor();
      if (deep.computeLuminance() <= 0.30) break;
    }
    return deep;
  }

  /// Content colour (text / icons) for anything sitting on [accentSolid].
  ///
  /// Derived from the FILL, not the token, so it is right by construction:
  /// [accentSolid] makes every accent dark enough for white except the
  /// marigold "attention" fill, which gets a warm near-black instead
  /// (7.9:1). One rule, no per-call-site guessing.
  Color onAccent(Color accent) => accentSolid(accent).computeLuminance() > 0.42
      ? const Color(0xFF3D2C06)
      : const Color(0xFFFFFFFF);

  /// Dark — the primary visual direction. Neutral graphite near-black
  /// ground with clean surface steps — no colour cast — the brand green
  /// stays canonical.
  static const dark = AppColorTokens(
    brightness: Brightness.dark,
    surface0: Color(0xFF0E0E10),
    surface1: Color(0xFF17171A),
    surface2: Color(0xFF1F1F23),
    surface3: Color(0xFF27272C),
    surface4: Color(0xFF313136),
    textPrimary: Color(0xFFF4F7FA),
    textSecondary: Color(0xFF93A1B3),
    borderColor: Color(0xFF2E2E33),
    primary: Color(0xFF00F08A),
    onPrimary: Color(0xFF06110B),
    success: Color(0xFF2ED993),
    warning: Color(0xFFFFC061),
    destructive: Color(0xFFFF6B82),
    info: Color(0xFF7E93FF),
    electricBlue: Color(0xFF7E93FF),
    violet: Color(0xFFA98CFF),
  );

  /// Light — a properly designed companion, not an inversion. Cool-paper
  /// ground so true-white cards lift off it; a recessed surface-2 for
  /// chips/nav; every accent deepened to clear WCAG-AA on white. The brand
  /// green becomes a deep emerald here — same identity, legible as text and
  /// as a fill; `onPrimary` stays the dark green-black in both themes so a
  /// green button reads identically light or dark.
  static const light = AppColorTokens(
    brightness: Brightness.light,
    surface0: Color(0xFFF1F4F8),
    surface1: Color(0xFFFFFFFF),
    surface2: Color(0xFFE9EDF3),
    surface3: Color(0xFFFFFFFF),
    surface4: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF111A28),
    textSecondary: Color(0xFF5A6A7E),
    borderColor: Color(0xFFDDE3EB),
    primary: Color(0xFF00A15C),
    onPrimary: Color(0xFF06110B),
    success: Color(0xFF0A8F55),
    warning: Color(0xFF9A5B00),
    destructive: Color(0xFFD01A3D),
    info: Color(0xFF3B4ED6),
    electricBlue: Color(0xFF3B4ED6),
    violet: Color(0xFF6C3FD0),
  );

  @override
  AppColorTokens copyWith({
    Brightness? brightness,
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
      brightness: brightness ?? this.brightness,
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
      brightness: t < 0.5 ? brightness : other.brightness,
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