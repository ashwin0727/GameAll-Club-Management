import 'access_pages.g.dart';

export 'access_pages.g.dart';

/// None = the page does not exist for the person. View = read only. Edit = everything on the page (incl. export).
enum AccessLevel { none, view, edit }

/// What the role editor shows. [custom] = holds some, but not all, of the Edit keys (e.g. a role built before the page
/// matrix existed), so it reads as "custom" instead of silently becoming Edit or View.
enum EditorLevel { none, view, edit, custom }

AccessPage? accessPageFor(String key) {
  for (final p in accessPages) {
    if (p.key == key) return p;
  }
  return null;
}

/// Every permission key the matrix manages. Keys outside this set (legacy / unmanaged) are preserved on save.
final Set<String> managedAccessKeys = {
  coachingOwnOnly,
  for (final p in accessPages) ...[...p.viewKeys, ...p.editKeys, ...p.extraKeys],
};

/// The level a person effectively has on a page, for gating the UI. Owners have everything. View needs every View key;
/// Edit means "can change something here" — any of the page's Edit keys, so a role with partial edit rights still gets
/// the buttons its own keys allow (each action is also gated by its specific key).
AccessLevel accessLevelFor(AccessPage page, Set<String> held, {required bool isOwner}) {
  if (isOwner) return AccessLevel.edit;
  if (!page.viewKeys.every(held.contains)) return AccessLevel.none;
  if (page.canEdit && page.editKeys.any(held.contains)) return AccessLevel.edit;
  return AccessLevel.view;
}

EditorLevel editorLevelFor(AccessPage page, Set<String> held) {
  if (!page.viewKeys.every(held.contains)) return EditorLevel.none;
  if (!page.canEdit || page.editKeys.isEmpty) return EditorLevel.view;
  final have = page.editKeys.where(held.contains).length;
  if (have == 0) return EditorLevel.view;
  return have == page.editKeys.length ? EditorLevel.edit : EditorLevel.custom;
}

/// Rewrites [held] so [page] is at [level]. Other pages and unmanaged keys are untouched.
Set<String> withPageLevel(Set<String> held, AccessPage page, AccessLevel level) {
  final next = {...held};
  next.removeAll([...page.viewKeys, ...page.editKeys]);
  if (level == AccessLevel.none) {
    next.removeAll(page.extraKeys);
  } else {
    next.addAll(page.viewKeys);
    if (level == AccessLevel.edit) next.addAll(page.editKeys);
  }
  return next;
}

/// The pages shown in each menu group, in menu order.
List<({String label, List<AccessPage> pages})> get accessGroups {
  final out = <({String label, List<AccessPage> pages})>[];
  for (final p in accessPages) {
    final i = out.indexWhere((g) => g.label == p.group);
    if (i < 0) {
      out.add((label: p.group, pages: [p]));
    } else {
      out[i].pages.add(p);
    }
  }
  return out;
}

// ── Which page guards each app screen ──────────────────────────────────────

const _routes = <(String, String)>[
  ('/dashboard', accessPageHome),
  ('/bookings', accessPageCalendar),
  ('/tournaments', accessPageTournaments),
  ('/guest-bookings', accessPageGuestBookings),
  ('/guests', accessPageGuestPlayers),
  ('/memberships/schedule', accessPageMembershipSchedule),
  ('/memberships/plans', accessPageMembershipPlans),
  ('/memberships', accessPageMembershipDashboard),
  ('/membership-sessions', accessPageMembershipSessions),
  ('/coaching/programs', accessPageCoachingPrograms),
  ('/coaching/students', accessPageCoachingStudents),
  ('/coaching/enrollments', accessPageCoachingStudents),
  ('/coaching/sessions', accessPageCoachingSessions),
  ('/coaching/schedule', accessPageCoachingSchedule),
  ('/coaching/reports', accessPageCoachingReports),
  ('/coaching', accessPageCoachingOverview),
  ('/maintenance/issue-categories', accessPageMaintenanceCategories),
  ('/maintenance', accessPageMaintenance),
  ('/finance/transactions', accessPageFinanceTransactions),
  ('/finance/pending-payments', accessPageFinancePayments),
  ('/finance/expenses', accessPageFinanceExpenses),
  ('/finance/daily-closing', accessPageFinanceDailyClosing),
  ('/finance/profit-loss', accessPageFinancePnl),
  ('/finance', accessPageFinanceOverview),
  ('/refunds', accessPageRefunds),
  ('/reports/court-utilization', accessPageReportCourtUtilization),
  ('/reports/revenue', accessPageReportRevenue),
  ('/reports/memberships', accessPageReportMemberships),
  ('/reports/guest-bookings', accessPageReportGuestBookings),
  ('/reports', accessPageReportOverview),
  ('/users-roles/roles', accessPageRoles),
  ('/users-roles/access-history', accessPageAccessHistory),
  ('/users-roles', accessPageStaff),
  ('/profile/facility-details', accessPageFacilitySettings),
  ('/profile/sports-courts', accessPageFacilitySettings),
  ('/profile/operating-hours', accessPageFacilitySettings),
  ('/profile/pricing-rules', accessPageFacilitySettings),
  ('/profile/edit', accessPageFacilitySettings),
  ('/profile/hub/facility', accessPageFacilitySettings),
  ('/profile/hub/payments', accessPageFacilitySettings),
];

final _writeSegment = RegExp(r'/(new|add|edit|record|bulk-success)(/|$)');

bool _under(String path, String prefix) => path == prefix || path.startsWith('$prefix/');

/// The page guarding [path] and whether the route needs Edit (create / edit sub-screens), or null when the screen isn't
/// guarded (profile, set-password, onboarding…).
({String page, bool needsEdit})? accessPageForPath(String path) {
  for (final (prefix, page) in _routes) {
    if (_under(path, prefix)) return (page: page, needsEdit: _writeSegment.hasMatch(path));
  }
  return null;
}
