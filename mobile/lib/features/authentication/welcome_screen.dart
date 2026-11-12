import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/app_routes.dart';
import 'auth_widgets.dart' show AuthFooterPrompt;

const introPurple = Color(0xFF4817C2);
const _ink = Color(0xFF171717);

/// The soft white-to-lilac ground shared by the welcome and intro pages.
const introBackground = BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Colors.white, Color(0xFFFBF9FF), Color(0xFFF3ECFF)],
  ),
);

/// The little progress dots under the picture: [index] of [count] is the long, purple one.
class IntroDots extends StatelessWidget {
  const IntroDots({super.key, required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            height: 8,
            width: i == index ? 22 : 8,
            decoration: BoxDecoration(
              color: i == index ? introPurple : const Color(0xFFD8CCF3),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
      ],
    );
  }
}

/// How many pages the welcome-and-intro run has in total: this welcome page, then the intro pages.
const introTotalSteps = 3;

/// The page a signed-out visitor sees first, between the splash and the login: the GameAll wordmark, the facility picture and a
/// one-line pitch. "Get Started" is for someone new and opens the short intro that ends at Create Account; "Log In" is for
/// someone who already has an account.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: DecoratedBox(
        decoration: introBackground,
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 20),
              Image.asset('assets/images/gameall_logo_light.png', height: 34),
              Expanded(
                // Scrolls instead of overflowing on a short phone or a large font size.
                child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: constraints.maxHeight),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ConstrainedBox(
                              constraints: BoxConstraints(maxHeight: constraints.maxHeight * 0.5),
                              child: Image.asset('assets/images/facility_welcome.png', fit: BoxFit.contain),
                            ),
                            const SizedBox(height: 22),
                            const Text(
                              'Run Your Sports Facility Smarter',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, height: 1.2, color: _ink),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Manage bookings, memberships, courts, and payouts — all in one place.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 16, height: 1.4, color: Color(0xFF2B2B2B)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const IntroDots(count: introTotalSteps, index: 0),
              const SizedBox(height: 22),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: SizedBox(
                  width: double.infinity,
                  height: 58,
                  child: FilledButton(
                    key: const ValueKey('welcome-get-started'),
                    onPressed: () => context.push(AppRoutes.intro),
                    style: FilledButton.styleFrom(
                      backgroundColor: introPurple,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text('Get Started', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
                        ),
                        SizedBox(width: 10),
                        Icon(Icons.arrow_forward_rounded, size: 23),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              AuthFooterPrompt(
                prompt: 'Already have an account?',
                action: 'Log In',
                actionKey: const ValueKey('welcome-log-in'),
                onTap: () => context.go(AppRoutes.signIn),
              ),
              const SizedBox(height: 14),
            ],
          ),
        ),
      ),
    );
  }
}
