import '../../data/models/facility.dart';
import 'app_routes.dart';

/// Pure state-transition logic — mirrors the web app's per-facility
/// onboarding_step gating: never send a facility with a further-along step
/// back to an earlier screen (item 28: "Do not send a completed user back
/// to onboarding unnecessarily").
class OnboardingRouteResolver {
  const OnboardingRouteResolver._();

  /// Where a fresh entry into the app (post-login, splash, or a stray hit on
  /// /dashboard) should land while onboarding is unfinished: the welcome
  /// screen every time, until the facility is fully configured.
  static String entryRouteFor(Facility? facility) {
    if (facility?.onboardingStep == OnboardingStep.completed) {
      return AppRoutes.dashboard;
    }
    return AppRoutes.onboardingWelcome;
  }

  static String routeFor(Facility? facility) {
    if (facility == null) return AppRoutes.onboardingFacility;

    switch (facility.onboardingStep) {
      case OnboardingStep.facilityDetails:
        return AppRoutes.onboardingFacility;
      case OnboardingStep.sportsCourts:
        return AppRoutes.onboardingSportsCourts;
      case OnboardingStep.pricing:
        return AppRoutes.onboardingPricing;
      case OnboardingStep.operatingHours:
        return AppRoutes.onboardingOperatingHours;
      case OnboardingStep.payments:
        return AppRoutes.onboardingPayments;
      case OnboardingStep.completed:
        return AppRoutes.dashboard;
    }
  }
}