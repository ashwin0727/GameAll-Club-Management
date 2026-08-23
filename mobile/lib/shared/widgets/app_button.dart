import 'package:flutter/material.dart';

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
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final String? loadingLabel;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: isLoading ? null : onPressed,
      child: isLoading
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    loadingLabel ?? label,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            )
          : Text(label, overflow: TextOverflow.ellipsis),
    );
  }
}

class SecondaryButton extends StatelessWidget {
  const SecondaryButton({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      child: Text(label, overflow: TextOverflow.ellipsis),
    );
  }
}