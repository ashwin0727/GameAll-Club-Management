import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/core/routing/app_routes.dart';
import 'package:gameall_club_mobile/features/onboarding/setup_ui.dart';
import 'package:go_router/go_router.dart';

/// Back on a setup step walks back one step at a time, even when the person was sent straight to a late step from Get Started.
void main() {
  Future<GoRouter> boot(WidgetTester tester) async {
    Widget step(String label, String fallback) => Builder(
          builder: (c) => Scaffold(body: Center(child: TextButton(onPressed: () => goBackOr(c, fallback), child: Text(label)))),
        );
    final router = GoRouter(
      initialLocation: AppRoutes.onboardingWelcome,
      routes: [
        GoRoute(path: AppRoutes.onboardingWelcome, builder: (_, _) => step('welcome', AppRoutes.onboardingWelcome)),
        GoRoute(path: AppRoutes.onboardingFacility, builder: (_, _) => step('facility', AppRoutes.onboardingWelcome)),
        GoRoute(path: AppRoutes.onboardingSportsCourts, builder: (_, _) => step('sports', AppRoutes.onboardingFacility)),
        GoRoute(path: AppRoutes.onboardingOperatingHours, builder: (_, _) => step('hours', AppRoutes.onboardingSportsCourts)),
        GoRoute(path: AppRoutes.onboardingPricing, builder: (_, _) => step('pricing', AppRoutes.onboardingOperatingHours)),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    return router;
  }

  Future<void> back(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets('resumed straight on step 4: Back goes 4 → 3 → 2 → 1 → Get Started, not Get Started at once', (tester) async {
    final router = await boot(tester);
    router.push(AppRoutes.onboardingPricing); // Get Started sends a returning owner to their last step
    await tester.pumpAndSettle();

    await back(tester, 'pricing');
    expect(find.text('hours'), findsOneWidget);
    await back(tester, 'hours');
    expect(find.text('sports'), findsOneWidget);
    await back(tester, 'sports');
    expect(find.text('facility'), findsOneWidget);
    await back(tester, 'facility');
    expect(find.text('welcome'), findsOneWidget);
  });

  testWidgets('walking forward step by step: Back returns to each previous step', (tester) async {
    final router = await boot(tester);
    router.push(AppRoutes.onboardingFacility);
    await tester.pumpAndSettle();
    router.push(AppRoutes.onboardingSportsCourts);
    await tester.pumpAndSettle();
    router.push(AppRoutes.onboardingOperatingHours);
    await tester.pumpAndSettle();

    await back(tester, 'hours');
    expect(find.text('sports'), findsOneWidget);
    await back(tester, 'sports');
    expect(find.text('facility'), findsOneWidget);
  });

  testWidgets('opened with nothing underneath: Back still opens the previous step', (tester) async {
    final router = await boot(tester);
    router.go(AppRoutes.onboardingPricing);
    await tester.pumpAndSettle();
    await back(tester, 'pricing');
    expect(find.text('hours'), findsOneWidget);
  });
}
