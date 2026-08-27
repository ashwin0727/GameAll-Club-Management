/// Centralized route paths — mirrors the web app's URL structure 1:1 so
/// the two clients stay conceptually aligned, and keeps room for the
/// modules named in item 65 (bookings/members/finance/reports) without a
/// routing rewrite.
class AppRoutes {
  const AppRoutes._();

  static const splash = '/splash';
  static const signIn = '/sign-in';
  static const createAccount = '/create-account';
  static const emailVerification = '/email-verification';
  static const forgotPassword = '/forgot-password';

  static const onboardingFacility = '/onboarding/facility';
  static const onboardingSports = '/onboarding/sports';
  static const onboardingCourts = '/onboarding/courts';
  static const onboardingOperatingHours = '/onboarding/operating-hours';
  static const onboardingPricing = '/onboarding/pricing';
  static const onboardingComplete = '/onboarding/complete';

  static const dashboard = '/dashboard';
  static const bookings = '/bookings';
  static const guests = '/guests';
  static const members = '/members';
  static const membershipSessions = '/membership-sessions';
  static const refunds = '/refunds';
}