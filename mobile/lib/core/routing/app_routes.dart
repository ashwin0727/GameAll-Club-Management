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

  static const onboardingWelcome = '/onboarding/welcome';
  static const onboardingFacility = '/onboarding/facility';

  /// The redesigned flow merges Sports and Courts into one step. The two
  /// legacy routes below still back the interim two-screen chain until the
  /// merged screen lands (onboarding-redesign sub-project 2).
  static const onboardingSportsCourts = '/onboarding/sports-courts';
  static const onboardingSports = '/onboarding/sports';
  static const onboardingCourts = '/onboarding/courts';
  static const onboardingOperatingHours = '/onboarding/operating-hours';
  static const onboardingPricing = '/onboarding/pricing';
  static const onboardingPayments = '/onboarding/payments';
  static const onboardingComplete = '/onboarding/complete';

  static const dashboard = '/dashboard';
  static const bookings = '/bookings';
  static const guestBookings = '/guest-bookings';
  static const guests = '/guests';

  /// Mirrors the web's NAV_ITEMS "Memberships" entry (src/lib/constants.ts)
  /// — the membership list at /memberships, the full create form at
  /// /memberships/new.
  static const memberships = '/memberships';
  static const membershipsNew = '/memberships/new';

  static const membershipSessions = '/membership-sessions';
  static const refunds = '/refunds';

  /// Mirrors the web's NAV_ITEMS "Finance" entry at /finance (src/lib/
  /// constants.ts). The transactions list is its own screen on mobile —
  /// the web reaches it at /finance/transactions.
  static const finance = '/finance';
  static const financeTransactions = '/finance/transactions';

  /// The full Transaction Details page — `:transactionId` is a payment id.
  static const financeTransactionDetails = '/finance/transactions/:transactionId';
  static const financeExpenses = '/finance/expenses';

  /// The full Expense Details page — `:expenseId` is an expenses id.
  static const financeExpenseDetails = '/finance/expenses/:expenseId';
  static const financePendingPayments = '/finance/pending-payments';

  /// End-of-day cash reconciliation. Web's /finance/daily-closing.
  static const financeDailyClosing = '/finance/daily-closing';

  /// Owner-level Profit & Loss. Web's /finance/profit-loss.
  static const financeProfitLoss = '/finance/profit-loss';

  /// The standalone Record Payment page — `:sourceId` is a booking or
  /// membership id. Reached from Pending Payments.
  static const financeRecordPayment = '/finance/pending-payments/:sourceId/record';

  /// Reports & Analytics. Web's NAV_ITEMS "Reports" section is a sidebar
  /// group; mobile has no sidebar, so `/reports` is a hub of six cards and
  /// each report is its own screen. Paths otherwise mirror the web.
  static const reports = '/reports';
  static const reportsOverview = '/reports/overview';
  static const reportsBookings = '/reports/bookings';
  static const reportsCourtUtilization = '/reports/court-utilization';
  static const reportsRevenue = '/reports/revenue';
  static const reportsMemberships = '/reports/memberships';
  static const reportsGuestBookings = '/reports/guest-bookings';

  /// Maintenance & Court Operations. Web's NAV_ITEMS "Maintenance" sidebar
  /// group; mobile has no sidebar, so `/maintenance` is the Overview and
  /// each section is its own screen, same pattern as Finance/Reports.
  static const maintenance = '/maintenance';
  static const maintenanceTickets = '/maintenance/tickets';
  static const maintenanceTicketNew = '/maintenance/tickets/new';

  /// `:ticketId` is a maintenance_tickets id.
  static const maintenanceTicketDetail = '/maintenance/tickets/:ticketId';
  static const maintenanceCourtSchedule = '/maintenance/court-schedule';
  static const maintenanceIssueCategories = '/maintenance/issue-categories';

  /// Staff / Roles / Permissions. Web's NAV_ITEMS "Users & Roles" group;
  /// mobile has no sidebar, so `/users-roles` is the Staff list and each
  /// section is its own screen, same pattern as Finance/Reports/Maintenance.
  static const usersRoles = '/users-roles';
  static const staffAdd = '/users-roles/staff/add';

  /// `:userId` is a profiles id.
  static const staffDetails = '/users-roles/staff/:userId';
  static const roles = '/users-roles/roles';
  static const roleNew = '/users-roles/roles/new';

  /// `:roleId` is a roles id.
  static const roleEditor = '/users-roles/roles/:roleId/edit';
  static const accessHistory = '/users-roles/access-history';

  /// Forced first-sign-in password reset for an admin-created staff account.
  static const setPassword = '/set-password';

  static const profile = '/profile';
}