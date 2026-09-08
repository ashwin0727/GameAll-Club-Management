import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/onboarding_route_resolver.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../authentication/session_controller.dart';
import '../authentication/auth_widgets.dart';

/// The branded intro shown before the facility-setup wizard — explains what
/// GameAll does, then hands off to the current onboarding step. Re-appears on
/// every launch until onboarding is complete.
class OnboardingWelcomeScreen extends ConsumerWidget {
  const OnboardingWelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Theme(
      data: AppTheme.dark(),
      child: Builder(
        builder: (context) {
          final tokens = context.tokens;
          return Scaffold(
            body: AuthGradientBackground(
              child: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) => SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.lg2),
                          child: ConstrainedBox(
                            constraints:
                                BoxConstraints(minHeight: constraints.maxHeight),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: AppSpacing.xl),
                                Container(
                                  height: 68,
                                  width: 68,
                                  decoration: BoxDecoration(
                                    color: tokens.primary,
                                    borderRadius:
                                        BorderRadius.circular(AppRadius.lg),
                                  ),
                                  child: Icon(Icons.schedule,
                                      color: tokens.onPrimary, size: 36),
                                ),
                                const SizedBox(height: AppSpacing.xl),
                                Text(
                                  'One place to\nrun the club',
                                  style: TextStyle(
                                    fontSize: 42,
                                    fontWeight: FontWeight.w800,
                                    height: 1.08,
                                    color: tokens.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.lg),
                                Text(
                                  'Courts, guests, memberships and money in one '
                                  'app. No booking register, no payment thread, '
                                  'no spreadsheet that never agrees with the '
                                  'cashbook.',
                                  style: TextStyle(
                                    fontSize: 17,
                                    height: 1.5,
                                    color: tokens.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.xl),
                                _FeatureCard(
                                  icon: Icons.calendar_today,
                                  tint: tokens.primary,
                                  title: 'Every court, live',
                                  description:
                                      'Book a slot on the court side and the '
                                      'front desk sees it instantly.',
                                ),
                                const SizedBox(height: AppSpacing.md),
                                _FeatureCard(
                                  icon: Icons.people_outline,
                                  tint: tokens.violet,
                                  title: 'Members and guests',
                                  description:
                                      'Recurring plans, coaching batches and '
                                      'walk-ins on one roster.',
                                ),
                                const SizedBox(height: AppSpacing.md),
                                _FeatureCard(
                                  icon: Icons.credit_card,
                                  tint: tokens.primary,
                                  title: 'Money that reconciles',
                                  description:
                                      'Payments, refunds and expenses land on '
                                      'one finance view automatically.',
                                ),
                                const SizedBox(height: AppSpacing.xl),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg2, AppSpacing.md, AppSpacing.lg2, AppSpacing.lg),
                      child: Column(
                        children: [
                          AuthGradientButton(
                            label: 'Set up my facility  ›',
                            onPressed: () {
                              final facility =
                                  ref.read(sessionControllerProvider).facility;
                              context.push(
                                  OnboardingRouteResolver.routeFor(facility));
                            },
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            'Takes about 6 minutes. You can stop and come back.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 14, color: tokens.textSecondary),
                          ),
                        ],
                      ),
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

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.tint,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final Color tint;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: tokens.surface1,
        border: Border.all(color: tokens.borderColor),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 44,
            width: 44,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(icon, color: tint, size: 22),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: tokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: tokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
