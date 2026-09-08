import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../authentication/auth_widgets.dart';

/// The dark shell every redesigned onboarding step sits in — the navy +
/// green-glow background from the mockups, a segmented progress header with
/// a Skip/Later affordance, a scrolling title/subtitle/body, and a pinned
/// CTA area at the bottom.
///
/// Forces [AppTheme.dark] regardless of the owner's Appearance setting: the
/// mockups are a single committed dark treatment.
class OnboardingScaffold extends StatelessWidget {
  const OnboardingScaffold({
    super.key,
    required this.stepIndex,
    this.stepCount = 5,
    required this.title,
    this.subtitle,
    required this.children,
    required this.footer,
    this.onBack,
    this.onSkip,
    this.skipLabel = 'Skip',
  });

  /// 0-based index of the current step within [stepCount].
  final int stepIndex;
  final int stepCount;
  final String title;
  final String? subtitle;
  final List<Widget> children;

  /// The pinned bottom area — typically an [AuthGradientButton].
  final Widget footer;
  final VoidCallback? onBack;

  /// When null, the Skip/Later link is hidden.
  final VoidCallback? onSkip;
  final String skipLabel;

  /// Built once — [AppTheme.dark] is pure and [ThemeData] is immutable, so
  /// rebuilding it on every keystroke would just be wasted work.
  static final ThemeData _darkTheme = AppTheme.dark();

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _darkTheme,
      child: Builder(
        builder: (context) {
          final tokens = context.tokens;
          return Scaffold(
            body: AuthGradientBackground(
              child: SafeArea(
                child: Column(
                  children: [
                    _Header(
                      stepIndex: stepIndex,
                      stepCount: stepCount,
                      onBack: onBack,
                      onSkip: onSkip,
                      skipLabel: skipLabel,
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg2,
                          AppSpacing.xl,
                          AppSpacing.lg2,
                          AppSpacing.xl,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w800,
                                height: 1.05,
                                color: tokens.textPrimary,
                              ),
                            ),
                            if (subtitle != null) ...[
                              const SizedBox(height: AppSpacing.md),
                              Text(
                                subtitle!,
                                style: TextStyle(
                                  fontSize: 15,
                                  height: 1.4,
                                  color: tokens.textSecondary,
                                ),
                              ),
                            ],
                            const SizedBox(height: AppSpacing.xl),
                            ...children,
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg2,
                        AppSpacing.md,
                        AppSpacing.lg2,
                        AppSpacing.lg,
                      ),
                      child: footer,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.stepIndex,
    required this.stepCount,
    required this.onBack,
    required this.onSkip,
    required this.skipLabel,
  });

  final int stepIndex;
  final int stepCount;
  final VoidCallback? onBack;
  final VoidCallback? onSkip;
  final String skipLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.lg2,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          if (onBack != null)
            _RoundIconButton(
              icon: Icons.chevron_left,
              // Prefer popping the real navigation stack so the on-screen
              // back button and the Android system back behave identically;
              // fall back to the explicit route only when there's nothing to
              // pop (e.g. the step was resumed directly on app launch).
              onTap: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  onBack!();
                }
              },
            )
          else
            const SizedBox(width: 40),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Row(
              children: [
                for (var i = 0; i < stepCount; i++) ...[
                  Expanded(
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: i <= stepIndex
                            ? tokens.primary
                            : tokens.textPrimary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                    ),
                  ),
                  if (i < stepCount - 1) const SizedBox(width: 6),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          if (onSkip != null)
            GestureDetector(
              onTap: onSkip,
              behavior: HitTestBehavior.opaque,
              child: Text(
                skipLabel,
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            )
          else
            const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Material(
      color: tokens.surface2,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 40,
          width: 40,
          child: Icon(icon, color: tokens.textPrimary, size: 24),
        ),
      ),
    );
  }
}
