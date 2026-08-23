import '../../data/models/facility.dart';
import 'app_routes.dart';

/// Pure state-transition logic — mirrors the web app's per-facility
/// onboarding_step gating: never send a facility with a further-along step
/// back to an earlier screen (item 28: "Do not send a completed user back
/// to onboarding unnecessarily").
class OnboardingRouteResolver {
  const OnboardingRouteResolver._();

  static String routeFor(Facility? facility) {
    if (facility == null) return AppRoutes.onboardingFacility;

    switch (facility.onboardingStep) {
      case OnboardingStep.facilityDetails:
        return AppRoutes.onboardingFacility;
      case OnboardingStep.sports:
        return AppRoutes.onboardingSports;
      case OnboardingStep.courts:
        return AppRoutes.onboardingCourts;
      case OnboardingStep.operatingHours:
        return AppRoutes.onboardingOperatingHours;
      case OnboardingStep.pricing:
        return AppRoutes.onboardingPricing;
      case OnboardingStep.completed:
        return AppRoutes.dashboard;
    }
  }
}