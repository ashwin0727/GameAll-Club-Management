import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/onboarding_route_resolver.dart';
import '../authentication/session_controller.dart';
import 'setup_ui.dart';

/// The intro shown before the facility-setup steps — a light page with the GameAll logo, what the setup covers and a "Get Started"
/// button that hands off to the current onboarding step. Re-appears on every launch until onboarding is complete.
class OnboardingWelcomeScreen extends ConsumerWidget {
  const OnboardingWelcomeScreen({super.key});

  static const List<String> checklist = [
    'Add your facility details',
    'Configure sports and courts',
    'Set operating hours and pricing',
    'Add payout information',
    'Choose a plan and go live',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SetupPage(
      footer: SetupButton(
        label: 'Get Started',
        primary: true,
        trailingIcon: Icons.arrow_forward,
        onPressed: () {
          final facility = ref.read(sessionControllerProvider).facility;
          context.push(OnboardingRouteResolver.routeFor(facility));
        },
      ),
      children: [
        Text('Set Up Your Facility', style: setupText(size: 30, weight: FontWeight.w700, height: 1.1)),
        const SizedBox(height: 8),
        Text('Get your venue live on GameAll in a few simple steps.', style: setupText(size: 15, color: SetupColors.secondary, height: 1.4)),
        const SizedBox(height: 20),
        SetupCard(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Semantics(
                  label: 'A sports arena with badminton, football, basketball, tennis and cricket icons',
                  child: Image.asset('assets/images/facility_welcome.png', fit: BoxFit.contain, filterQuality: FilterQuality.high),
                ),
              ),
              const Divider(height: 24, color: SetupColors.border),
              for (final item in checklist)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(
                    children: [
                      Container(
                        height: 28,
                        width: 28,
                        decoration: BoxDecoration(color: SetupColors.activeBg, borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.check, size: 16, color: SetupColors.primary),
                      ),
                      const SizedBox(width: 14),
                      Expanded(child: Text(item, style: setupText(size: 15, weight: FontWeight.w500))),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Center(child: Text('Takes about 6 minutes. You can stop and come back.', style: setupText(size: 13, color: SetupColors.secondary))),
      ],
    );
  }
}
