import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart' show AppColorTokensX;
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';

/// Full-bleed dark background with the green radial glow from the auth
/// mockups — a deep navy base lit from the upper-left by GameAll Green.
class AuthGradientBackground extends StatelessWidget {
  const AuthGradientBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return DecoratedBox(
      decoration: BoxDecoration(color: tokens.surface0),
      child: Stack(
        children: [
          Positioned(
            top: -160,
            left: -120,
            child: _Glow(color: tokens.primary.withValues(alpha: 0.22), size: 420),
          ),
          Positioned(
            top: 40,
            right: -160,
            child: _Glow(color: tokens.primary.withValues(alpha: 0.10), size: 360),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        height: size,
        width: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}

/// Auth screen body. The header + form block ([top]) is nudged down from
/// the top edge and the CTA + footer block ([bottom]) sits toward the
/// bottom, with breathing room between them — the vertical rhythm of the
/// mockups. Collapses gracefully and scrolls when the keyboard is up or
/// the form is tall.
class AuthLayout extends StatelessWidget {
  const AuthLayout({super.key, required this.top, required this.bottom});

  final List<Widget> top;
  final List<Widget> bottom;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header + form block, vertically centred in the space above the
        // pinned CTA. Scrolls when the keyboard is up or the form is tall.
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  // Content sits low — flush above the pinned button, with
                  // the empty space kept above the header instead of below
                  // the form.
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...top,
                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ),
          ),
        ),
        ...bottom,
        const SizedBox(height: AppSpacing.lg2),
      ],
    );
  }
}

/// The bright-green gradient pill CTA from the auth mockups, with a soft
/// green glow. Mirrors [PrimaryButton]'s loading/disabled behaviour.
class AuthGradientButton extends StatelessWidget {
  const AuthGradientButton({
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
    final tokens = context.tokens;
    final disabled = isLoading || onPressed == null;
    return Opacity(
      opacity: disabled ? 0.6 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.lerp(tokens.primary, Colors.white, 0.16)!,
              tokens.primary,
            ],
          ),
          boxShadow: disabled
              ? null
              : [
                  BoxShadow(
                    color: tokens.primary.withValues(alpha: 0.55),
                    blurRadius: 36,
                    spreadRadius: -4,
                    offset: const Offset(0, 10),
                  ),
                ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            onTap: disabled ? null : onPressed,
            child: Container(
              height: _kAuthButtonHeight,
              width: double.infinity,
              alignment: Alignment.center,
              child: isLoading
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: tokens.onPrimary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          loadingLabel ?? label,
                          style: TextStyle(
                            color: tokens.onPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      label,
                      style: TextStyle(
                        color: tokens.onPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

const double _kAuthButtonHeight = 56;

/// The lower-emphasis "mobile" alternative button — same tall pill as
/// [AuthGradientButton] but an outlined dark surface, per the mockups.
class AuthOutlineButton extends StatelessWidget {
  const AuthOutlineButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Material(
      color: tokens.surface1,
      shape: StadiumBorder(side: BorderSide(color: tokens.borderColor)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Container(
          height: _kAuthButtonHeight,
          width: double.infinity,
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: tokens.textPrimary),
              const SizedBox(width: AppSpacing.md),
              Text(
                label,
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The "or" rule between the primary CTA and the mobile alternative.
class AuthOrDivider extends StatelessWidget {
  const AuthOrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final line = Expanded(child: Divider(color: tokens.borderColor));
    return Row(
      children: [
        line,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Text('or', style: TextStyle(color: tokens.textSecondary)),
        ),
        line,
      ],
    );
  }
}

/// "Already have an account? Log in" / "New here? Create an account".
class AuthFooterPrompt extends StatelessWidget {
  const AuthFooterPrompt({
    super.key,
    required this.prompt,
    required this.action,
    required this.onTap,
  });

  final String prompt;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(prompt, style: TextStyle(color: tokens.textSecondary)),
        const SizedBox(width: AppSpacing.xs),
        GestureDetector(
          onTap: onTap,
          child: Text(
            action,
            style: TextStyle(color: tokens.primary, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

/// Segmented password-strength indicator. Purely visual feedback — the
/// actual acceptance rule stays with [Validators.password].
class PasswordStrengthMeter extends StatelessWidget {
  const PasswordStrengthMeter({super.key, required this.password});

  final String password;

  static const _labels = ['', 'Too short', 'Fair', 'Good', 'Strong'];

  int get _score {
    if (password.isEmpty) return 0;
    if (password.length < 8) return 1;
    var checks = 0;
    if (password.contains(RegExp(r'[A-Z]'))) checks++;
    if (password.contains(RegExp(r'[a-z]'))) checks++;
    if (password.contains(RegExp(r'[0-9]'))) checks++;
    if (password.contains(RegExp(r'[^A-Za-z0-9]'))) checks++;
    if (password.length >= 12) checks++;
    return checks <= 1 ? 2 : (checks <= 3 ? 3 : 4);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final score = _score;
    final active = score == 0 ? 0 : (score == 1 ? 1 : score - 1); // filled segments (0..3)
    final color = switch (score) {
      0 || 1 => tokens.destructive,
      2 => tokens.warning,
      3 => tokens.info,
      _ => tokens.primary,
    };
    return Row(
      children: [
        for (var i = 0; i < 4; i++) ...[
          Expanded(
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                color: i < active ? color : tokens.surface2,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
          ),
          if (i < 3) const SizedBox(width: AppSpacing.sm),
        ],
        const SizedBox(width: AppSpacing.md),
        Text(
          password.isEmpty ? '' : _labels[score],
          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

/// A branded rounded app-mark, shown at the top of the Log in screen.
class AuthBrandMark extends StatelessWidget {
  const AuthBrandMark({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      height: 56,
      width: 56,
      decoration: BoxDecoration(
        color: tokens.primary,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Icon(Icons.schedule, color: tokens.onPrimary, size: 30),
    );
  }
}

void showComingSoon(BuildContext context, String feature) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text('$feature is coming soon.')));
}
