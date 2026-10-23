import type { PageKey } from "./catalog.generated";

/**
 * Which page-access entry guards each dashboard URL. The first match wins, so more specific prefixes come first. A URL
 * that matches nothing (e.g. /profile/personal, /profile/support) is open to every signed-in staff member.
 */
const ROUTES: { prefix: string; page: PageKey }[] = [
  { prefix: "/dashboard", page: "HOME" },
  { prefix: "/calendar", page: "CALENDAR" },
  { prefix: "/tournaments", page: "TOURNAMENTS" },
  { prefix: "/guest-bookings", page: "GUEST_BOOKINGS" },
  { prefix: "/guests", page: "GUEST_PLAYERS" },
  { prefix: "/memberships/v1/schedule", page: "MEMBERSHIP_SCHEDULE" },
  { prefix: "/memberships/v1/plans", page: "MEMBERSHIP_PLANS" },
  { prefix: "/memberships", page: "MEMBERSHIP_DASHBOARD" },
  { prefix: "/membership-sessions", page: "MEMBERSHIP_SESSIONS" },
  { prefix: "/coaching/programs", page: "COACHING_PROGRAMS" },
  { prefix: "/coaching/students", page: "COACHING_STUDENTS" },
  { prefix: "/coaching/enrollments", page: "COACHING_STUDENTS" },
  { prefix: "/coaching/sessions", page: "COACHING_SESSIONS" },
  { prefix: "/coaching/schedule", page: "COACHING_SCHEDULE" },
  { prefix: "/coaching/reports", page: "COACHING_REPORTS" },
  { prefix: "/coaching", page: "COACHING_OVERVIEW" },
  { prefix: "/maintenance/issue-categories", page: "MAINTENANCE_CATEGORIES" },
  { prefix: "/maintenance", page: "MAINTENANCE" },
  { prefix: "/finance/transactions", page: "FINANCE_TRANSACTIONS" },
  { prefix: "/finance/pending-payments", page: "FINANCE_PAYMENTS" },
  { prefix: "/finance/expenses", page: "FINANCE_EXPENSES" },
  { prefix: "/finance/daily-closing", page: "FINANCE_DAILY_CLOSING" },
  { prefix: "/finance/profit-loss", page: "FINANCE_PNL" },
  { prefix: "/finance", page: "FINANCE_OVERVIEW" },
  { prefix: "/refunds", page: "REFUNDS" },
  { prefix: "/reports/court-utilization", page: "REPORT_COURT_UTILIZATION" },
  { prefix: "/reports/revenue", page: "REPORT_REVENUE" },
  { prefix: "/reports/memberships", page: "REPORT_MEMBERSHIPS" },
  { prefix: "/reports/guest-bookings", page: "REPORT_GUEST_BOOKINGS" },
  { prefix: "/reports/bookings", page: "REPORT_OVERVIEW" },
  { prefix: "/reports", page: "REPORT_OVERVIEW" },
  { prefix: "/users-roles/staff", page: "STAFF" },
  { prefix: "/users-roles/roles", page: "ROLES" },
  { prefix: "/users-roles/access-history", page: "ACCESS_HISTORY" },
  { prefix: "/profile/facility", page: "FACILITY_SETTINGS" },
  { prefix: "/profile/payments", page: "FACILITY_SETTINGS" },
];

/** Sub-pages that create or change something need Edit, not just View. */
const WRITE_SEGMENT = /\/(new|add|edit|record|bulk-success)(\/|$)/;

function under(path: string, prefix: string): boolean {
  return path === prefix || path.startsWith(prefix + "/");
}

export function pageForPath(path: string): { page: PageKey; needs: "view" | "edit" } | null {
  const hit = ROUTES.find((r) => under(path, r.prefix));
  if (!hit) return null;
  return { page: hit.page, needs: WRITE_SEGMENT.test(path) ? "edit" : "view" };
}

/** The sidebar entry (by href) → page key, so the menu and the route guard can never disagree. */
export function pageForHref(href: string): PageKey | null {
  return pageForPath(href)?.page ?? null;
}
