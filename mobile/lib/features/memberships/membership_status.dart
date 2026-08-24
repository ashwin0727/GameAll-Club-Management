import '../../data/models/membership.dart';

/// Port of src/features/memberships/status.ts — single source of truth for
/// "is this membership active / expiring / expired" on mobile. Never
/// re-derive this in a widget or expect the DB to store it; status is a
/// function of (raw DB status, end_date, now), computed here once.

const int expiringSoonDays = 7;

DateTime _endOfDay(DateTime d) {
  return d.isUtc
      ? DateTime.utc(d.year, d.month, d.day, 23, 59, 59, 999)
      : DateTime(d.year, d.month, d.day, 23, 59, 59, 999);
}

/// A member is a facility customer record independent of any membership —
/// passing null [status]/[endDate] (never assigned a plan) is a normal,
/// valid input, not an error case; it returns [MembershipDisplayStatus.noMembership].
/// [now] defaults to `DateTime.now()` when omitted.
MembershipDisplayStatus computeMembershipStatus({
  required MembershipStatus? status,
  required DateTime? endDate,
  DateTime? now,
}) {
  if (status == null || endDate == null) return MembershipDisplayStatus.noMembership;
  if (status == MembershipStatus.cancelled) return MembershipDisplayStatus.cancelled;

  final days = daysUntilExpiry(endDate, now);
  if (days < 0) return MembershipDisplayStatus.expired;
  if (days <= expiringSoonDays) return MembershipDisplayStatus.expiringSoon;
  return MembershipDisplayStatus.active;
}

/// [now] defaults to `DateTime.now()` when omitted.
int daysUntilExpiry(DateTime endDate, [DateTime? now]) {
  final n = now ?? DateTime.now();
  final end = _endOfDay(endDate);
  final diffMs = end.difference(n).inMilliseconds;
  return (diffMs / (24 * 60 * 60 * 1000)).ceil();
}

/// Adds `durationDays` to `startDate` — matches the server-side computation
/// in the `create_membership` RPC, used here only to preview the end date
/// client-side before confirming.
DateTime computeMembershipEndDate(DateTime startDate, int durationDays) {
  return startDate.isUtc
      ? DateTime.utc(startDate.year, startDate.month, startDate.day).add(Duration(days: durationDays))
      : DateTime(startDate.year, startDate.month, startDate.day).add(Duration(days: durationDays));
}