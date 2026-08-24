import 'package:flutter/animation.dart';

/// Centralized motion system — subtle by design (spec: "Subtle motion >
/// excessive animation"). Every micro-interaction (slot selection, button
/// press, card tap) uses one of these durations/curves rather than a
/// one-off value invented per screen.
class AppMotion {
  const AppMotion._();

  static const Duration fast = Duration(milliseconds: 120);
  static const Duration normal = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 320);

  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeOutBack;
}