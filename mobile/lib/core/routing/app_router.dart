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
import '../../features/bookings/guest_bookings_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/finance/expenses_screen.dart';
import '../../features/finance/expense_details_screen.dart';
import '../../features/finance/daily_closing_screen.dart';
import '../../features/finance/profit_loss_screen.dart';
import '../../features/staff/staff_list_screen.dart';
import '../../features/staff/add_staff_screen.dart';
import '../../features/staff/staff_details_screen.dart';
import '../../features/staff/roles_screen.dart';
import '../../features/staff/role_editor_screen.dart';
import '../../features/staff/access_history_screen.dart';
import '../../features/staff/set_password_screen.dart';
import '../../features/finance/finance_screen.dart';
import '../../features/finance/money_screen.dart';
import '../../features/finance/pending_payments_screen.dart';
import '../../features/finance/record_payment_screen.dart';
import '../../features/finance/transaction_details_screen.dart';
import '../../features/finance/transactions_screen.dart';
import '../../features/guests/guests_screen.dart';
import '../../features/memberships/create_membership_screen.dart';
import '../../features/memberships/members_screen.dart';
import '../../features/memberships/memberships_screen.dart';
import '../../features/membership_sessions/membership_sessions_screen.dart';
import '../../features/onboarding/courts_setup_screen.dart';
import '../../features/onboarding/onboarding_welcome_screen.dart';
import '../../features/onboarding/payments_screen.dart';
import '../../features/onboarding/facility_details_screen.dart';
import '../../features/onboarding/operating_hours_screen.dart';
import '../../features/onboarding/pricing_screen.dart';
import '../../features/onboarding/setup_summary_screen.dart';
import '../../features/onboarding/sports_setup_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/refunds/refunds_screen.dart';
import '../../features/reports/booking_report_screen.dart';
import '../../features/reports/court_utilization_report_screen.dart';
import '../../features/reports/guest_booking_report_screen.dart';
import '../../features/reports/membership_report_screen.dart';
import '../../features/reports/reports_hub_screen.dart';
import '../../features/reports/reports_overview_screen.dart';
import '../../features/reports/revenue_report_screen.dart';
import '../../features/maintenance/maintenance_overview_screen.dart';
import '../../features/maintenance/maintenance_tickets_screen.dart';
import '../../features/maintenance/create_maintenance_ticket_screen.dart';
import '../../features/maintenance/maintenance_ticket_detail_screen.dart';
import '../../features/maintenance/maintenance_court_schedule_screen.dart';
import '../../features/maintenance/maintenance_issue_categories_screen.dart';
import 'app_routes.dart';
import 'onboarding_route_resolver.dart';
import 'page_transitions.dart';

/// `false` until the cold-start splash clip has finished (or timed out). The
/// router holds every route on [AppRoutes.splash] while it's `false`, so the
/// branded video always plays through once. [SplashScreen] flips it.
final splashGate = ValueNotifier<bool>(false);

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: Listenable.merge([_SessionListenable(ref), splashGate]),
    redirect: (context, state) {
      final session = ref.read(sessionControllerProvider);
      final path = state.matchedLocation;

      // Stay on the splash until BOTH the session has resolved AND the
      // splash clip has played out — then everything else routes normally.
      if (session.isLoading || !splashGate.value) {
        return path == AppRoutes.splash ? null : AppRoutes.splash;
      }

      final isAuthRoute = path == AppRoutes.signIn ||
          path == AppRoutes.createAccount ||
          path == AppRoutes.emailVerification ||
          path == AppRoutes.forgotPassword;

      if (!session.isAuthenticated) {
        return isAuthRoute ? null : AppRoutes.signIn;
      }

      // A staff account created by an administrator must set its own password
      // before anything else — the router keeps them here until it clears.
      if (session.user!.mustResetPassword) {
        return path == AppRoutes.setPassword ? null : AppRoutes.setPassword;
      }

      if (path == AppRoutes.splash || isAuthRoute) {
        return OnboardingRouteResolver.entryRouteFor(session.facility);
      }

      // Reaching /dashboard with onboarding still incomplete resumes the
      // correct step instead of showing a dashboard for a facility that
      // isn't fully configured yet (item 28).
      if (path == AppRoutes.dashboard &&
          session.facility?.onboardingStep != OnboardingStep.completed) {
        return OnboardingRouteResolver.entryRouteFor(session.facility);
      }

      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        pageBuilder: (context, state) =>
            fadeThrough(state, const SplashScreen()),
      ),
      GoRoute(
        path: AppRoutes.signIn,
        pageBuilder: (context, state) =>
            fadeThrough(state, const SignInScreen()),
      ),
      GoRoute(
        path: AppRoutes.createAccount,
        pageBuilder: (context, state) =>
            slideOver(state, const CreateAccountScreen()),
      ),
      GoRoute(
        path: AppRoutes.emailVerification,
        pageBuilder: (context, state) => slideOver(
          state,
          EmailVerificationScreen(
            email: state.uri.queryParameters['email'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.forgotPassword,
        pageBuilder: (context, state) =>
            slideOver(state, const ForgotPasswordScreen()),
      ),
      GoRoute(
        path: AppRoutes.onboardingWelcome,
        pageBuilder: (context, state) =>
            slideOver(state, const OnboardingWelcomeScreen()),
      ),
      GoRoute(
        path: AppRoutes.onboardingFacility,
        pageBuilder: (context, state) =>
            slideOver(state, const FacilityDetailsScreen()),
      ),
      GoRoute(
        path: AppRoutes.onboardingSportsCourts,
        pageBuilder: (context, state) =>
            slideOver(state, const SportsSetupScreen()),
      ),
      GoRoute(
        path: AppRoutes.onboardingSports,
        pageBuilder: (context, state) =>
            slideOver(state, const SportsSetupScreen()),
      ),
      GoRoute(
        path: AppRoutes.onboardingCourts,
        pageBuilder: (context, state) =>
            slideOver(state, const CourtsSetupScreen()),
      ),
      GoRoute(
        path: AppRoutes.onboardingOperatingHours,
        pageBuilder: (context, state) =>
            slideOver(state, const OperatingHoursScreen()),
      ),
      GoRoute(
        path: AppRoutes.onboardingPricing,
        pageBuilder: (context, state) =>
            slideOver(state, const PricingScreen()),
      ),
      GoRoute(
        path: AppRoutes.onboardingPayments,
        pageBuilder: (context, state) =>
            slideOver(state, const PaymentsScreen()),
      ),
      GoRoute(
        path: AppRoutes.onboardingComplete,
        pageBuilder: (context, state) =>
            fadeThrough(state, const SetupSummaryScreen()),
      ),
      GoRoute(
        path: AppRoutes.dashboard,
        pageBuilder: (context, state) =>
            fadeThrough(state, const DashboardScreen()),
      ),
      GoRoute(
        path: AppRoutes.bookings,
        pageBuilder: (context, state) =>
            fadeThrough(state, const BookingsScreen()),
      ),
      GoRoute(
        path: AppRoutes.guestBookings,
        pageBuilder: (context, state) =>
            slideOver(state, const GuestBookingsScreen()),
      ),
      GoRoute(
        path: AppRoutes.guests,
        pageBuilder: (context, state) =>
            slideOver(state, const GuestsScreen()),
      ),
      GoRoute(
        path: AppRoutes.memberships,
        pageBuilder: (context, state) => fadeThrough(
          state,
          MembersScreen(
            openPlans: state.uri.queryParameters['new'] == 'plan',
            openNew: state.uri.queryParameters['new'] == 'membership',
          ),
        ),
      ),
      GoRoute(
        path: '/memberships/manage',
        pageBuilder: (context, state) =>
            fadeThrough(state, const MembershipsScreen()),
      ),
      GoRoute(
        path: AppRoutes.membershipsNew,
        pageBuilder: (context, state) =>
            slideOver(state, const CreateMembershipScreen()),
      ),
      GoRoute(
        path: AppRoutes.membershipSessions,
        pageBuilder: (context, state) =>
            fadeThrough(state, const MembershipSessionsScreen()),
      ),
      GoRoute(
        path: AppRoutes.refunds,
        pageBuilder: (context, state) =>
            slideOver(state, const RefundsScreen()),
      ),
      GoRoute(
        path: AppRoutes.finance,
        pageBuilder: (context, state) =>
            fadeThrough(state, const MoneyScreen()),
      ),
      GoRoute(
        path: '/finance/overview',
        pageBuilder: (context, state) =>
            fadeThrough(state, const FinanceScreen()),
      ),
      GoRoute(
        path: AppRoutes.financeTransactions,
        pageBuilder: (context, state) =>
            slideOver(state, const TransactionsScreen()),
      ),
      GoRoute(
        path: AppRoutes.financeTransactionDetails,
        pageBuilder: (context, state) => slideOver(
          state,
          TransactionDetailsScreen(
              transactionId: state.pathParameters['transactionId']!),
        ),
      ),
      GoRoute(
        path: AppRoutes.financeExpenses,
        pageBuilder: (context, state) =>
            slideOver(state, const ExpensesScreen()),
      ),
      GoRoute(
        path: AppRoutes.financeExpenseDetails,
        pageBuilder: (context, state) => slideOver(
          state,
          ExpenseDetailsScreen(expenseId: state.pathParameters['expenseId']!),
        ),
      ),
      GoRoute(
        path: AppRoutes.financeDailyClosing,
        pageBuilder: (context, state) =>
            slideOver(state, const DailyClosingScreen()),
      ),
      GoRoute(
        path: AppRoutes.financeProfitLoss,
        pageBuilder: (context, state) =>
            slideOver(state, const ProfitLossScreen()),
      ),
      GoRoute(
        path: AppRoutes.financePendingPayments,
        pageBuilder: (context, state) =>
            slideOver(state, const PendingPaymentsScreen()),
      ),
      GoRoute(
        path: AppRoutes.financeRecordPayment,
        pageBuilder: (context, state) => slideOver(
          state,
          RecordPaymentScreen(sourceId: state.pathParameters['sourceId']!),
        ),
      ),
      GoRoute(
        path: AppRoutes.profile,
        pageBuilder: (context, state) =>
            slideOver(state, const ProfileScreen()),
      ),
      GoRoute(
        path: AppRoutes.setPassword,
        pageBuilder: (context, state) =>
            fadeThrough(state, const SetPasswordScreen()),
      ),
      GoRoute(
        path: AppRoutes.usersRoles,
        pageBuilder: (context, state) =>
            fadeThrough(state, const StaffListScreen()),
      ),
      GoRoute(
        path: AppRoutes.staffAdd,
        pageBuilder: (context, state) =>
            slideOver(state, const AddStaffScreen()),
      ),
      GoRoute(
        path: AppRoutes.staffDetails,
        pageBuilder: (context, state) => slideOver(
          state,
          StaffDetailsScreen(userId: state.pathParameters['userId']!),
        ),
      ),
      GoRoute(
        path: AppRoutes.roles,
        pageBuilder: (context, state) =>
            slideOver(state, const RolesScreen()),
      ),
      GoRoute(
        path: AppRoutes.roleNew,
        pageBuilder: (context, state) => slideOver(
          state,
          RoleEditorScreen(templateId: state.uri.queryParameters['template']),
        ),
      ),
      GoRoute(
        path: AppRoutes.roleEditor,
        pageBuilder: (context, state) => slideOver(
          state,
          RoleEditorScreen(roleId: state.pathParameters['roleId']),
        ),
      ),
      GoRoute(
        path: AppRoutes.accessHistory,
        pageBuilder: (context, state) =>
            slideOver(state, const AccessHistoryScreen()),
      ),
      GoRoute(path: AppRoutes.reports, builder: (context, state) => const ReportsHubScreen()),
      GoRoute(
        path: AppRoutes.reportsOverview,
        builder: (context, state) => ReportsOverviewScreen(initialQuery: state.uri.queryParameters),
      ),
      GoRoute(
        path: AppRoutes.reportsBookings,
        builder: (context, state) => BookingReportScreen(initialQuery: state.uri.queryParameters),
      ),
      GoRoute(
        path: AppRoutes.reportsCourtUtilization,
        builder: (context, state) => CourtUtilizationReportScreen(initialQuery: state.uri.queryParameters),
      ),
      GoRoute(
        path: AppRoutes.reportsRevenue,
        builder: (context, state) => RevenueReportScreen(initialQuery: state.uri.queryParameters),
      ),
      GoRoute(
        path: AppRoutes.reportsMemberships,
        builder: (context, state) => MembershipReportScreen(initialQuery: state.uri.queryParameters),
      ),
      GoRoute(
        path: AppRoutes.reportsGuestBookings,
        builder: (context, state) => GuestBookingReportScreen(initialQuery: state.uri.queryParameters),
      ),
      GoRoute(path: AppRoutes.maintenance, builder: (context, state) => const MaintenanceOverviewScreen()),
      GoRoute(path: AppRoutes.maintenanceTickets, builder: (context, state) => const MaintenanceTicketsScreen()),
      GoRoute(path: AppRoutes.maintenanceTicketNew, builder: (context, state) => const CreateMaintenanceTicketScreen()),
      GoRoute(
        path: AppRoutes.maintenanceTicketDetail,
        builder: (context, state) => MaintenanceTicketDetailScreen(ticketId: state.pathParameters['ticketId']!),
      ),
      GoRoute(path: AppRoutes.maintenanceCourtSchedule, builder: (context, state) => const MaintenanceCourtScheduleScreen()),
      GoRoute(path: AppRoutes.maintenanceIssueCategories, builder: (context, state) => const MaintenanceIssueCategoriesScreen()),
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