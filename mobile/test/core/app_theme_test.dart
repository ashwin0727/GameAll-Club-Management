import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/core/theme/app_colors.dart';
import 'package:gameall_club_mobile/core/theme/app_radius.dart';
import 'package:gameall_club_mobile/core/theme/app_theme.dart';

void main() {
  group('AppTheme.light', () {
    final theme = AppTheme.light();

    test('uses Material 3', () {
      expect(theme.useMaterial3, isTrue);
    });

    test('seeds the color scheme from the GameAll brand primary, not a default Material color', () {
      expect(theme.colorScheme.primary, AppColors.primary);
    });

    test('cards are flat with a border rather than floating boxes (spec: subtle elevation)', () {
      expect(theme.cardTheme.elevation, 0);
      final shape = theme.cardTheme.shape as RoundedRectangleBorder;
      expect(shape.side.color, AppColors.border);
    });

    test('every primary button meets the minimum touch target height', () {
      final style = theme.elevatedButtonTheme.style!;
      final minSize = style.minimumSize?.resolve({});
      expect(minSize!.height, greaterThanOrEqualTo(48));
    });

    test('cards, buttons, and inputs share one consistent radius scale', () {
      final cardShape = theme.cardTheme.shape as RoundedRectangleBorder;
      final buttonShape = theme.elevatedButtonTheme.style!.shape!.resolve({}) as RoundedRectangleBorder;
      expect((cardShape.borderRadius as BorderRadius).topLeft.x, AppRadius.lg);
      expect((buttonShape.borderRadius as BorderRadius).topLeft.x, AppRadius.md);
    });
  });
}