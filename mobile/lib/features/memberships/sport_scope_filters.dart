/// The Memberships pages follow the "All Sports" selector. A plan's sport lives on its court-access slots (batches);
/// mirrors src/features/memberships/sport-scope.ts on the web. `sports` is null for All Sports — nothing is filtered.
library;

import '../../data/models/membership.dart';

/// Plans that have at least one slot, none of them on a sport in scope. A plan with no slots at all is NOT in this
/// set — it can have real, paying members before any court time is set up for it.
Set<String> _planIdsOnOtherSportOnly(List<AssignableBatch> batches, Set<String> inScope) {
  final sportsByPlan = <String, Set<String>>{};
  for (final b in batches) {
    final planId = b.planId;
    if (planId == null) continue;
    (sportsByPlan[planId] ??= <String>{}).add(b.facilitySportId);
  }
  return {
    for (final e in sportsByPlan.entries)
      if (!e.value.any(inScope.contains)) e.key,
  };
}

List<MembershipPlan> plansForSports(List<MembershipPlan> plans, List<AssignableBatch> batches, Set<String>? sports) {
  if (sports == null) return plans;
  final excluded = _planIdsOnOtherSportOnly(batches, sports);
  return plans.where((p) => !excluded.contains(p.id)).toList();
}

/// Membership rows whose plan isn't clearly tied to a sport that is out of scope.
List<MembershipListRow> membershipRowsForSports(List<MembershipListRow> rows, List<AssignableBatch> batches, Set<String>? sports) {
  if (sports == null) return rows;
  final excluded = _planIdsOnOtherSportOnly(batches, sports);
  return rows.where((r) => r.planId == null || !excluded.contains(r.planId)).toList();
}

List<AssignableBatch> batchesForSports(List<AssignableBatch> batches, Set<String>? sports) =>
    sports == null ? batches : batches.where((b) => sports.contains(b.facilitySportId)).toList();

/// The hub's headline numbers worked out from the sport-scoped rows (the database summary is facility-wide).
MembershipPageSummary scopedMembershipSummary(List<MembershipListRow> rows) {
  final live = rows.where((r) => r.status != MembershipListStatus.inactive).toList();
  final incomplete = rows.where((r) => r.status == MembershipListStatus.paymentIncomplete).length;
  return MembershipPageSummary(
    totalMembers: rows.length,
    activeMembers: live.length,
    activePctOfTotal: rows.isEmpty ? 0 : live.length / rows.length * 100,
    paymentIncompleteMembers: incomplete,
    revenueInr: live.fold(0, (sum, r) => sum + r.monthlyPriceInr),
  );
}
