import 'package:flutter/animation.dart';

/// Centralized motion system — subtle by design (spec: "Subtle motion >
/// excessive animation"). Every micro-interaction (slot selection, button
/// press, card tap) uses one of these durations/curves rather than a
/// one-off value invented per screen.
class AppMotion {
  const AppMotion._();

  /// Micro-interaction — spec range 150-200ms.
  static const Duration fast = Duration(milliseconds: 160);

  /// Screen/component transition — spec range 200-300ms.
  static const Duration normal = Duration(milliseconds: 240);

  /// Major visual transition — spec range 300-450ms.
  static const Duration slow = Duration(milliseconds: 380);

  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeOutBack;
}