import '../../data/models/membership.dart';

// The rules behind the Memberships → Members tab, kept free of widgets so they can be tested.

int _statusRank(MembershipListStatus s) => switch (s) {
      MembershipListStatus.active => 0,
      MembershipListStatus.paymentIncomplete => 1,
      MembershipListStatus.inactive => 2,
    };

/// Members as the tab lists them: Active first, then payment-incomplete, then Inactive — and within
/// each group the most recent joiner first (latest start date; ties go to the later end date).
List<MembershipListRow> orderMembersForDisplay(List<MembershipListRow> rows) {
  return [...rows]..sort((a, b) {
      final byStatus = _statusRank(a.status).compareTo(_statusRank(b.status));
      if (byStatus != 0) return byStatus;
      final byStart = b.startDate.compareTo(a.startDate);
      if (byStart != 0) return byStart;
      return b.endDate.compareTo(a.endDate);
    });
}

/// Whether an active membership runs out within the next [days] days.
bool isExpiringSoon(MembershipListRow m, DateTime now, {int days = 30}) =>
    m.status == MembershipListStatus.active && m.endDate.isAfter(now) && m.endDate.isBefore(now.add(Duration(days: days)));

class MemberCounts {
  const MemberCounts({required this.total, required this.active, required this.inactive, required this.expiring});

  final int total;
  final int active;
  final int inactive;
  final int expiring;
}

/// The headline figures on the Members card. [total] is the facility's full member count (which can
/// exceed [rows] if the list was capped); active / inactive / expiring come from the rows themselves.
MemberCounts countMembers(List<MembershipListRow> rows, DateTime now, {int? total}) => MemberCounts(
      total: total ?? rows.length,
      active: rows.where((m) => m.status == MembershipListStatus.active).length,
      inactive: rows.where((m) => m.status == MembershipListStatus.inactive).length,
      expiring: rows.where((m) => isExpiringSoon(m, now)).length,
    );

/// Average slot usage across all session batches, 0–100, or null when there are no seats to fill.
int? utilizationPercent(List<AssignableBatch> batches) {
  final seats = batches.fold<int>(0, (sum, b) => sum + b.capacity);
  if (seats <= 0) return null;
  final filled = batches.fold<int>(0, (sum, b) => sum + b.enrolledCount);
  return (filled / seats * 100).round().clamp(0, 100);
}

/// "Payment Pending": every membership's unpaid balance, plus one more period of the plan's price for a
/// renewal whose date has passed with nothing owed against it. A membership with an unpaid balance is counted
/// once, by that balance. [owedMinor] maps membership id -> outstanding minor units (Pending Payments).
({int amountInr, int count}) membershipPending(
  List<MembershipListRow> rows,
  Map<String, int> owedMinor,
  DateTime now,
) {
  var amount = 0.0;
  var count = 0;
  for (final m in rows) {
    final minor = owedMinor[m.membershipId] ?? 0;
    if (minor > 0) {
      amount += minor / 100;
      count++;
    } else if (m.status == MembershipListStatus.inactive && m.endDate.isBefore(now)) {
      amount += m.monthlyPriceInr;
      count++;
    }
  }
  return (amountInr: amount.round(), count: count);
}
