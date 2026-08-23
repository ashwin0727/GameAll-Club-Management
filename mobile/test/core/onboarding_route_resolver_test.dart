import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/core/routing/app_routes.dart';
import 'package:gameall_club_mobile/core/routing/onboarding_route_resolver.dart';
import 'package:gameall_club_mobile/data/models/facility.dart';

Facility _facility(OnboardingStep step) {
  return Facility(
    id: 'facility-1',
    ownerId: 'owner-1',
    name: 'GameAll Sports Arena',
    type: FacilityType.multiSport,
    businessEmail: 'owner@example.com',
    businessPhone: '9876543210',
    address: const FacilityAddress(
      line1: '123 Anna Salai',
      area: 'Ambattur',
      city: 'Chennai',
      state: 'Tamil Nadu',
      country: 'India',
      pinCode: '600053',
    ),
    status: 'ACTIVE',
    onboardingStep: step,
  );
}

void main() {
  group('OnboardingRouteResolver.routeFor', () {
    test('no facility resumes at Facility Details', () {
      expect(OnboardingRouteResolver.routeFor(null), AppRoutes.onboardingFacility);
    });

    test('resumes each incomplete step at its own screen, never further along', () {
      expect(
        OnboardingRouteResolver.routeFor(_facility(OnboardingStep.sports)),
        AppRoutes.onboardingSports,
      );
      expect(
        OnboardingRouteResolver.routeFor(_facility(OnboardingStep.courts)),
        AppRoutes.onboardingCourts,
      );
      expect(
        OnboardingRouteResolver.routeFor(_facility(OnboardingStep.operatingHours)),
        AppRoutes.onboardingOperatingHours,
      );
      expect(
        OnboardingRouteResolver.routeFor(_facility(OnboardingStep.pricing)),
        AppRoutes.onboardingPricing,
      );
    });

    test('a completed facility goes straight to the dashboard, not back to onboarding', () {
      expect(
        OnboardingRouteResolver.routeFor(_facility(OnboardingStep.completed)),
        AppRoutes.dashboard,
      );
    });
  });
}