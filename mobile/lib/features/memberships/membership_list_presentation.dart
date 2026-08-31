import '../../data/models/membership.dart';
import '../../shared/widgets/misc.dart';

/// Pure status/expiry -> (label, tone, text) mappings for the Memberships
/// list, so a row is never communicated by colour alone and the boundaries
/// (expired / today / ≤30 days / >30 days) match `memberships-page.tsx`'s
/// `statusBadge` / `expiryHint`.

String membershipListStatusLabel(MembershipListStatus status) {
  switch (status) {
    case MembershipListStatus.active:
      return 'Active';
    case MembershipListStatus.expiringSoon:
      return 'Expiring Soon';
    case MembershipListStatus.expired:
      return 'Expired';
    case MembershipListStatus.cancelled:
      return 'Cancelled';
  }
}

StatusTone membershipListStatusTone(MembershipListStatus status) {
  switch (status) {
    case MembershipListStatus.active:
      return StatusTone.success;
    case MembershipListStatus.expiringSoon:
      return StatusTone.warning;
    case MembershipListStatus.expired:
      return StatusTone.danger;
    case MembershipListStatus.cancelled:
      return StatusTone.neutral;
  }
}

class MembershipExpiryHint {
  const MembershipExpiryHint(this.text, this.tone);

  final String text;
  final StatusTone tone;
}

MembershipExpiryHint membershipExpiryHint(MembershipListStatus status, int daysLeft) {
  if (status == MembershipListStatus.cancelled) return const MembershipExpiryHint('Cancelled', StatusTone.neutral);
  if (daysLeft < 0) return MembershipExpiryHint('Expired ${daysLeft.abs()} days ago', StatusTone.danger);
  if (daysLeft == 0) return const MembershipExpiryHint('Expires today', StatusTone.warning);
  return MembershipExpiryHint('$daysLeft days left', daysLeft <= 30 ? StatusTone.warning : StatusTone.success);
}