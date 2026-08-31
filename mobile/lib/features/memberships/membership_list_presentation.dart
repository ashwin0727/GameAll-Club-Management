import '../../data/models/membership.dart';
import '../../shared/widgets/misc.dart';

/// Pure status -> (label, tone) mapping for the Memberships list, so a row is
/// never communicated by colour alone. Mirrors `memberships-page.tsx`'s
/// `statusBadge` — the payment-driven three-state model
/// (payment_not_initiated / active / inactive).

String membershipListStatusLabel(MembershipListStatus status) {
  switch (status) {
    case MembershipListStatus.active:
      return 'Active';
    case MembershipListStatus.paymentNotInitiated:
      return 'Payment Not Initiated';
    case MembershipListStatus.inactive:
      return 'Inactive';
  }
}

StatusTone membershipListStatusTone(MembershipListStatus status) {
  switch (status) {
    case MembershipListStatus.active:
      return StatusTone.success;
    case MembershipListStatus.paymentNotInitiated:
      return StatusTone.warning;
    case MembershipListStatus.inactive:
      return StatusTone.neutral;
  }
}

/// True when [date] is before today (local midnight) — the "Next Payment
/// Date" is rendered in the danger colour when it has already passed.
bool isPastDate(DateTime date, [DateTime? now]) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  return DateTime(date.year, date.month, date.day).isBefore(today);
}