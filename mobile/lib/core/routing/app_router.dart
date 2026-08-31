import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/models/facility.dart';
import '../../features/authentication/create_account_screen.dart';
import '../../features/authentication/email_verification_screen.dart';
import '../../features/authentication/forgot_password_screen.dart';
import '../../features/authentication/session_controller.dart';
import '../../features/authentication/sign_in_screen.dart';
import '../../features/authentication/splash_screen.dart';
import '../../features/bookings/bookings_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/finance/finance_screen.dart';
import '../../features/finance/transactions_screen.dart';
import '../../features/guests/guests_screen.dart';
import '../../features/memberships/create_membership_screen.dart';
import '../../features/memberships/memberships_screen.dart';
import '../../features/membership_sessions/membership_sessions_screen.dart';
import '../../features/onboarding/courts_setup_screen.dart';
import '../../features/onboarding/facility_details_screen.dart';
import '../../features/onboarding/operating_hours_screen.dart';
import '../../features/onboarding/pricing_screen.dart';
import '../../features/onboarding/setup_summary_screen.dart';
import '../../features/onboarding/sports_setup_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/refunds/refunds_screen.dart';
import 'app_routes.dart';
import 'onboarding_route_resolver.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: _SessionListenable(ref),
    redirect: (context, state) {
      final session = ref.read(sessionControllerProvider);
      final path = state.matchedLocation;

      // The splash screen alone owns the "still resolving session" period
      // and performs its own navigation once ready — every other route
      // waits for a real answer rather than guessing.
      if (session.isLoading) {
        return path == AppRoutes.splash ? null : AppRoutes.splash;
      }

      final isAuthRoute = path == AppRoutes.signIn ||
          path == AppRoutes.createAccount ||
          path == AppRoutes.emailVerification ||
          path == AppRoutes.forgotPassword;

      if (!session.isAuthenticated) {
        return isAuthRoute ? null : AppRoutes.signIn;
      }

      if (path == AppRoutes.splash || isAuthRoute) {
        return OnboardingRouteResolver.routeFor(session.facility);
      }

      // Reaching /dashboard with onboarding still incomplete resumes the
      // correct step instead of showing a dashboard for a facility that
      // isn't fully configured yet (item 28).
      if (path == AppRoutes.dashboard &&
          session.facility?.onboardingStep != OnboardingStep.completed) {
        return OnboardingRouteResolver.routeFor(session.facility);
      }

      return null;
    },
    routes: [
      GoRoute(path: AppRoutes.splash, builder: (context, state) => const SplashScreen()),
      GoRoute(path: AppRoutes.signIn, builder: (context, state) => const SignInScreen()),
      GoRoute(
        path: AppRoutes.createAccount,
        builder: (context, state) => const CreateAccountScreen(),
      ),
      GoRoute(
        path: AppRoutes.emailVerification,
        builder: (context, state) => EmailVerificationScreen(
          email: state.uri.queryParameters['email'] ?? '',
        ),
      ),
      GoRoute(
        path: AppRoutes.forgotPassword,
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: AppRoutes.onboardingFacility,
        builder: (context, state) => const FacilityDetailsScreen(),
      ),
      GoRoute(
        path: AppRoutes.onboardingSports,
        builder: (context, state) => const SportsSetupScreen(),
      ),
      GoRoute(
        path: AppRoutes.onboardingCourts,
        builder: (context, state) => const CourtsSetupScreen(),
      ),
      GoRoute(
        path: AppRoutes.onboardingOperatingHours,
        builder: (context, state) => const OperatingHoursScreen(),
      ),
      GoRoute(
        path: AppRoutes.onboardingPricing,
        builder: (context, state) => const PricingScreen(),
      ),
      GoRoute(
        path: AppRoutes.onboardingComplete,
        builder: (context, state) => const SetupSummaryScreen(),
      ),
      GoRoute(path: AppRoutes.dashboard, builder: (context, state) => const DashboardScreen()),
      GoRoute(path: AppRoutes.bookings, builder: (context, state) => const BookingsScreen()),
      GoRoute(path: AppRoutes.guests, builder: (context, state) => const GuestsScreen()),
      GoRoute(path: AppRoutes.memberships, builder: (context, state) => const MembershipsScreen()),
      GoRoute(path: AppRoutes.membershipsNew, builder: (context, state) => const CreateMembershipScreen()),
      GoRoute(
        path: AppRoutes.membershipSessions,
        builder: (context, state) => const MembershipSessionsScreen(),
      ),
      GoRoute(path: AppRoutes.refunds, builder: (context, state) => const RefundsScreen()),
      GoRoute(path: AppRoutes.finance, builder: (context, state) => const FinanceScreen()),
      GoRoute(
        path: AppRoutes.financeTransactions,
        builder: (context, state) => const TransactionsScreen(),
      ),
      GoRoute(path: AppRoutes.profile, builder: (context, state) => const ProfileScreen()),
    ],
  );
});

/// Bridges Riverpod's session state into go_router's `Listenable`-based
/// refresh mechanism, so a sign-in/sign-out re-evaluates `redirect` without
/// the app needing its own separate navigation-state plumbing.
class _SessionListenable extends ChangeNotifier {
  _SessionListenable(this._ref) {
    _ref.listen(sessionControllerProvider, (previous, next) {
      notifyListeners();
    });
  }

  final Ref _ref;
}