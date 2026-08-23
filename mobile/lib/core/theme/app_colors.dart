import 'package:flutter/material.dart';

/// Mirrors the web app's palette (see tailwind.config.ts) so the mobile app
/// reads as the same product, not a different one.
class AppColors {
  const AppColors._();

  static const Color primary = Color(0xFF16A34A);
  static const Color primaryDark = Color(0xFF15803D);
  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFD97706);
  static const Color destructive = Color(0xFFDC2626);

  static const Color background = Color(0xFFFFFFFF);
  static const Color foreground = Color(0xFF0F172A);
  static const Color muted = Color(0xFF64748B);
  static const Color mutedBackground = Color(0xFFF1F5F9);
  static const Color border = Color(0xFFE2E8F0);
  static const Color card = Color(0xFFFFFFFF);
}