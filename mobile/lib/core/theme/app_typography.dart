import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Semantic typography built on top of the Material 3 text theme already
/// configured in [AppTheme] — screens should reach for these instead of
/// hand-rolling one-off `TextStyle(fontSize: 11, color: AppColors.muted)`
/// calls, which had drifted across the app (bookings, guests, dashboard all
/// wrote a slightly different version of the same "metadata" style).
///
/// This never disables or overrides text scaling — every style here is
/// still subject to the device's system font-size setting, since it's
/// derived from [Theme.of(context).textTheme] rather than a fixed size.
class AppTypography {
  const AppTypography._();

  /// Small muted label — a slot time caption, a card's metadata line, a
  /// list row's secondary detail.
  static TextStyle caption(BuildContext context) {
    return Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.muted) ??
        const TextStyle(fontSize: 11, color: AppColors.muted);
  }

  /// A card/section's primary label.
  static TextStyle sectionTitle(BuildContext context) => Theme.of(context).textTheme.titleMedium!;

  /// A list row's primary text.
  static TextStyle rowTitle(BuildContext context) => Theme.of(context).textTheme.titleSmall!;

  /// Muted body text — secondary description under a title.
  static TextStyle secondary(BuildContext context) {
    return Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.muted) ??
        const TextStyle(color: AppColors.muted);
  }
}