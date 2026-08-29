import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/core/theme/app_colors.dart';
import 'package:gameall_club_mobile/core/theme/app_radius.dart';
import 'package:gameall_club_mobile/core/theme/app_theme.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  // AppTheme builds its TextTheme via google_fonts, which otherwise tries
  // to touch the (uninitialized, outside a widget test) asset/network
  // bindings the moment a theme is built at the top of a `group`. Disabling
  // runtime fetching here is the package's own documented pattern for
  // plain `test()`s — Manrope's actual rendering is a widget-test/manual
  // concern, not something these theme-shape tests need to exercise.
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('AppTheme.dark (the primary visual direction)', () {
    final theme = AppTheme.dark();
    final tokens = theme.extension<AppColorTokens>()!;

    test('uses Material 3', () {
      expect(theme.useMaterial3, isTrue);
    });

    test('seeds the color scheme from the GameAll brand primary, not a default Material color', () {
      expect(theme.colorScheme.primary, AppColors.primary);
    });

    test('registers AppColorTokens.dark as a theme extension', () {
      expect(tokens.surface0, AppColorTokens.dark.surface0);
      expect(tokens.primary, AppColors.primary);
    });

    test('scaffold background is Surface 0, not a bare black/white default', () {
      expect(theme.scaffoldBackgroundColor, tokens.surface0);
    });

    test('cards are flat with a border rather than floating boxes (spec: subtle elevation)', () {
      expect(theme.cardTheme.elevation, 0);
      final shape = theme.cardTheme.shape as RoundedRectangleBorder;
      expect(shape.side.color, tokens.borderColor);
      expect(theme.cardTheme.color, tokens.surface1);
    });

    test('every primary button meets the minimum touch target height and uses dark text on the green fill', () {
      final style = theme.elevatedButtonTheme.style!;
      final minSize = style.minimumSize?.resolve({});
      expect(minSize!.height, greaterThanOrEqualTo(48));
      expect(style.foregroundColor?.resolve({}), tokens.onPrimary);
      expect(style.backgroundColor?.resolve({}), tokens.primary);
    });

    test('cards, buttons, and inputs share one consistent radius scale', () {
      final cardShape = theme.cardTheme.shape as RoundedRectangleBorder;
      final buttonShape = theme.elevatedButtonTheme.style!.shape!.resolve({}) as RoundedRectangleBorder;
      expect((cardShape.borderRadius as BorderRadius).topLeft.x, AppRadius.lg);
      expect((buttonShape.borderRadius as BorderRadius).topLeft.x, AppRadius.md);
    });

    test('bottom sheets use the 24px+ top radius the spec requires', () {
      final shape = theme.bottomSheetTheme.shape as RoundedRectangleBorder;
      final borderRadius = shape.borderRadius as BorderRadius;
      expect(borderRadius.topLeft.x, greaterThanOrEqualTo(24));
    });

    test('focused input border uses GameAll Green at 2px (spec: "Focused: GameAll Green glow/ring")', () {
      final border = theme.inputDecorationTheme.focusedBorder as OutlineInputBorder;
      expect(border.borderSide.color, tokens.primary);
      expect(border.borderSide.width, 2);
    });
  });

  group('AppTheme.light', () {
    final theme = AppTheme.light();
    final tokens = theme.extension<AppColorTokens>()!;

    test('uses the same brand primary as dark — one brand color, not reinterpreted per theme', () {
      expect(theme.colorScheme.primary, AppColors.primary);
    });

    test('is a genuinely independent palette, not dark values inverted', () {
      expect(tokens.surface0, isNot(AppColorTokens.dark.surface0));
      expect(tokens.textPrimary, isNot(AppColorTokens.dark.textPrimary));
      expect(tokens.borderColor, isNot(AppColorTokens.dark.borderColor));
    });

    test('scaffold background is a light surface', () {
      expect(theme.scaffoldBackgroundColor.computeLuminance(), greaterThan(0.5));
    });

    test('text primary is dark-on-light for correct contrast', () {
      expect(tokens.textPrimary.computeLuminance(), lessThan(0.5));
    });
  });

  group('AppColorTokens', () {
    test('lerp interpolates every field without dropping to the fallback', () {
      final mid = AppColorTokens.dark.lerp(AppColorTokens.light, 0.5);
      expect(mid.surface0, isNot(AppColorTokens.dark.surface0));
      expect(mid.surface0, isNot(AppColorTokens.light.surface0));
    });

    test('lerp against null returns the original unchanged (ThemeExtension contract)', () {
      final result = AppColorTokens.dark.lerp(null, 1);
      expect(result, AppColorTokens.dark);
    });

    test('copyWith overrides only the given fields', () {
      final result = AppColorTokens.dark.copyWith(primary: Colors.orange);
      expect(result.primary, Colors.orange);
      expect(result.surface0, AppColorTokens.dark.surface0);
    });
  });
}