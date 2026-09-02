import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';

/// Primary CTA — full-width by default (per the onboarding/auth flows),
/// disables itself while [isLoading] so a slow network can't produce a
/// double-submit (item 51 on the pricing/setup spec, applied everywhere).
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.loadingLabel,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final String? loadingLabel;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return ElevatedButton(
        onPressed: null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Flexible(child: Text(loadingLabel ?? label, overflow: TextOverflow.ellipsis)),
          ],
        ),
      );
    }
    if (icon == null) {
      return ElevatedButton(
        onPressed: onPressed,
        child: Text(label, overflow: TextOverflow.ellipsis),
      );
    }
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label, overflow: TextOverflow.ellipsis),
    );
  }
}

class SecondaryButton extends StatelessWidget {
  const SecondaryButton({super.key, required this.label, required this.onPressed, this.icon});

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    // Full-width by design: the shared theme only guarantees a minimum
    // height, so the stretch is requested here rather than inherited.
    final style = OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(AppSpacing.huge));
    if (icon == null) {
      return OutlinedButton(
        onPressed: onPressed,
        style: style,
        child: Text(label, overflow: TextOverflow.ellipsis),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: style,
      icon: Icon(icon, size: 18),
      label: Text(label, overflow: TextOverflow.ellipsis),
    );
  }
}

/// No visible container until pressed — the lowest-emphasis action (spec
/// §"Button System": "GHOST: No visible container unless hovered/pressed").
class GhostButton extends StatelessWidget {
  const GhostButton({super.key, required this.label, required this.onPressed, this.icon});

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final style = TextButton.styleFrom(
      foregroundColor: tokens.textPrimary,
      overlayColor: tokens.surface2,
      minimumSize: const Size(0, AppSpacing.huge),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      shape: const StadiumBorder(),
    );
    if (icon == null) {
      return TextButton(onPressed: onPressed, style: style, child: Text(label, overflow: TextOverflow.ellipsis));
    }
    return TextButton.icon(
      onPressed: onPressed,
      style: style,
      icon: Icon(icon, size: 18),
      label: Text(label, overflow: TextOverflow.ellipsis),
    );
  }
}

/// Reserved for destructive actions only (spec §"Button System": "DANGER:
/// Used only for destructive actions") — cancel a booking, remove a
/// member, etc. Never used as a generic secondary action.
class DangerButton extends StatelessWidget {
  const DangerButton({super.key, required this.label, required this.onPressed, this.isLoading = false});

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return ElevatedButton(
      onPressed: isLoading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: tokens.destructive,
        foregroundColor: Colors.white,
        disabledBackgroundColor: tokens.destructive.withValues(alpha: 0.35),
        minimumSize: const Size.fromHeight(AppSpacing.huge),
        shape: const StadiumBorder(),
        elevation: 0,
      ),
      child: isLoading
          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : Text(label, overflow: TextOverflow.ellipsis),
    );
  }
}