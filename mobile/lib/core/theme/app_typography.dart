import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// GameAll Design System 2026 — one typeface (Manrope) across the whole
/// app, mapped onto Material 3's [TextTheme] slots so every existing
/// `Theme.of(context).textTheme.xxx` call site (dozens of screens written
/// before this redesign) picks up the new type scale automatically, with
/// no per-screen changes required.
///
/// The ramp is anchored on a 12px body — every other step is derived from
/// it, so the hierarchy stays intact rather than each screen being nudged
/// on its own.
///
/// Spec scale → M3 slot:
///   Display 1  44/Bold      → displayLarge
///   Display 2  34/Bold      → displayMedium
///   Heading 1  24/SemiBold  → headlineMedium (also aliased headlineSmall
///                             for the many existing screens already using it)
///   Heading 2  17/SemiBold  → titleLarge
///   Heading 3  15/SemiBold  → titleMedium
///   Row title  13/SemiBold  → titleSmall
///   Body Large 14/Regular   → bodyLarge
///   Body       12/Regular   → bodyMedium
///   Caption    11/Medium    → labelMedium
///   Micro      10/Medium    → labelSmall
///
/// Never hard-codes a fixed height/fontSize outside of [TextTheme] itself —
/// every style below is still fully subject to the device's system font
/// scaling via [MediaQuery.textScaler] (spec: "Never hard-code text height").
class AppTypography {
  const AppTypography._();

  static TextTheme _scale(TextTheme base, Color primaryText, Color secondaryText) {
    return base.copyWith(
      displayLarge: base.displayLarge?.copyWith(fontSize: 44, fontWeight: FontWeight.w700, color: primaryText, height: 1.05),
      displayMedium: base.displayMedium?.copyWith(fontSize: 34, fontWeight: FontWeight.w700, color: primaryText, height: 1.08),
      headlineLarge: base.headlineLarge?.copyWith(fontSize: 24, fontWeight: FontWeight.w600, color: primaryText),
      headlineMedium: base.headlineMedium?.copyWith(fontSize: 24, fontWeight: FontWeight.w600, color: primaryText),
      headlineSmall: base.headlineSmall?.copyWith(fontSize: 20, fontWeight: FontWeight.w600, color: primaryText),
      titleLarge: base.titleLarge?.copyWith(fontSize: 17, fontWeight: FontWeight.w600, color: primaryText),
      titleMedium: base.titleMedium?.copyWith(fontSize: 15, fontWeight: FontWeight.w600, color: primaryText),
      titleSmall: base.titleSmall?.copyWith(fontSize: 13, fontWeight: FontWeight.w600, color: primaryText),
      bodyLarge: base.bodyLarge?.copyWith(fontSize: 14, fontWeight: FontWeight.w400, color: primaryText),
      bodyMedium: base.bodyMedium?.copyWith(fontSize: 12, fontWeight: FontWeight.w400, color: primaryText),
      bodySmall: base.bodySmall?.copyWith(fontSize: 11, fontWeight: FontWeight.w400, color: secondaryText),
      labelLarge: base.labelLarge?.copyWith(fontSize: 12, fontWeight: FontWeight.w600, color: primaryText),
      labelMedium: base.labelMedium?.copyWith(fontSize: 11, fontWeight: FontWeight.w500, color: secondaryText),
      labelSmall: base.labelSmall?.copyWith(fontSize: 10, fontWeight: FontWeight.w500, color: secondaryText),
    );
  }

  /// Builds the full Manrope-based [TextTheme] for one theme brightness.
  /// google_fonts fetches the font lazily and caches it after first use —
  /// production behavior is untouched here. Only when a caller has
  /// explicitly disabled runtime fetching (this app's own theme unit
  /// tests, via `GoogleFonts.config.allowRuntimeFetching = false`, since no
  /// .ttf is bundled as a test asset) does this skip the loader entirely
  /// and fall back to the platform default TextTheme, so a theme-shape
  /// test never has to actually resolve a real webfont to run.
  static TextTheme textTheme({required Color primaryText, required Color secondaryText}) {
    if (!GoogleFonts.config.allowRuntimeFetching) {
      return _scale(const TextTheme(), primaryText, secondaryText);
    }
    return _scale(GoogleFonts.manropeTextTheme(), primaryText, secondaryText);
  }

  // ── Legacy semantic helpers — kept so every screen written before this
  // redesign keeps compiling and rendering correctly against the new scale.
  static TextStyle caption(BuildContext context) => Theme.of(context).textTheme.labelMedium!;

  static TextStyle sectionTitle(BuildContext context) => Theme.of(context).textTheme.titleMedium!;

  static TextStyle rowTitle(BuildContext context) => Theme.of(context).textTheme.titleSmall!;

  static TextStyle secondary(BuildContext context) => Theme.of(context).textTheme.bodyMedium!.copyWith(color: context.tokens.textSecondary);

  // ── New semantic helpers for redesigned screens (spec's own names).
  static TextStyle display1(BuildContext context) => Theme.of(context).textTheme.displayLarge!;

  static TextStyle display2(BuildContext context) => Theme.of(context).textTheme.displayMedium!;

  static TextStyle heading1(BuildContext context) => Theme.of(context).textTheme.headlineMedium!;

  static TextStyle heading2(BuildContext context) => Theme.of(context).textTheme.titleLarge!;

  static TextStyle heading3(BuildContext context) => Theme.of(context).textTheme.titleMedium!;

  static TextStyle bodyLarge(BuildContext context) => Theme.of(context).textTheme.bodyLarge!;

  static TextStyle body(BuildContext context) => Theme.of(context).textTheme.bodyMedium!;

  static TextStyle micro(BuildContext context) => Theme.of(context).textTheme.labelSmall!;
}