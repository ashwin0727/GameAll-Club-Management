import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../theme/app_text_styles.dart';
import 'hover_scope.dart';
import 'pressable.dart';

/// The one call-to-action style of the Player app. Pick the kind, not the colours.
enum GameAllButtonKind {
  /// Brand gradient: only for the main action on a screen.
  gradient,

  /// Solid electric blue: the everyday button.
  solid,

  /// Outlined: a quieter second action.
  secondary,
}

class GameAllButton extends StatelessWidget {
  const GameAllButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.kind = GameAllButtonKind.solid,
    this.expand = false,
    this.height = AppDimensions.buttonHeight,
  });

  const GameAllButton.gradient({super.key, required this.label, required this.onPressed, this.icon, this.expand = false, this.height = AppDimensions.buttonHeight})
      : kind = GameAllButtonKind.gradient;

  const GameAllButton.secondary({super.key, required this.label, required this.onPressed, this.icon, this.expand = false, this.height = AppDimensions.buttonHeight})
      : kind = GameAllButtonKind.secondary;

  final String label;

  /// Null disables the button.
  final VoidCallback? onPressed;
  final IconData? icon;
  final GameAllButtonKind kind;
  final bool expand;
  final double height;

  bool get _enabled => onPressed != null;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final radius = BorderRadius.circular(AppDimensions.buttonRadius);

    final Color textColor;
    final Decoration decoration;
    if (!_enabled) {
      textColor = p.mutedText;
      decoration = BoxDecoration(borderRadius: radius, color: p.elevated.withValues(alpha: p.isDark ? 0.6 : 1));
    } else {
      switch (kind) {
        case GameAllButtonKind.gradient:
          textColor = Colors.white;
          decoration = BoxDecoration(
            borderRadius: radius,
            gradient: AppColors.brandGradient,
            boxShadow: [BoxShadow(color: AppColors.blue.withValues(alpha: 0.30), blurRadius: 16, offset: const Offset(0, 6))],
          );
        case GameAllButtonKind.solid:
          textColor = Colors.white;
          decoration = BoxDecoration(borderRadius: radius, color: AppColors.blue);
        case GameAllButtonKind.secondary:
          textColor = p.primaryText;
          decoration = BoxDecoration(borderRadius: radius, border: Border.all(color: p.border), color: p.surface.withValues(alpha: p.isDark ? 0.5 : 1));
      }
    }

    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(child: HoverText(label, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: AppTextStyles.button(textColor))),
        if (icon != null) ...[
          const SizedBox(width: 8),
          Icon(icon, color: textColor, size: 18),
        ],
      ],
    );

    return Semantics(
      button: true,
      enabled: _enabled,
      label: label,
      child: ExcludeSemantics(
        child: Pressable(
          onTap: onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: height,
            width: expand ? double.infinity : null,
            constraints: const BoxConstraints(minWidth: AppDimensions.minTouchTarget),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: decoration,
            child: content,
          ),
        ),
      ),
    );
  }
}
