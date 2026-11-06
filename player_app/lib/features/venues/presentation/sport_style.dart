import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// The tint of a sport's chip: racquet sports blue, field sports green, basketball amber, everything else violet.
Color sportColor(String? sport) {
  final s = (sport ?? '').toLowerCase();
  if (s.contains('foot') ||
      s.contains('cricket') ||
      s.contains('soccer') ||
      s.contains('futsal') ||
      s.contains('hockey'))
    return AppColors.success;
  if (s.contains('badminton') ||
      s.contains('tennis') ||
      s.contains('pickle') ||
      s.contains('padel') ||
      s.contains('squash'))
    return AppColors.blue;
  if (s.contains('basket') || s.contains('volley')) return AppColors.warning;
  return AppColors.violet;
}
