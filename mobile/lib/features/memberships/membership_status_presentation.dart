import '../../data/models/membership.dart';
import '../../shared/widgets/misc.dart';

/// Pure status→(label,tone) mapping so a status is never communicated by
/// color alone. Mirrors `member-list.tsx`'s `statusLabel`/`statusTone`.

String membershipDisplayStatusLabel(MembershipDisplayStatus status) {
  switch (status) {
    case MembershipDisplayStatus.active:
      return 'Active';
    case MembershipDisplayStatus.expiringSoon:
      return 'Expiring Soon';
    case MembershipDisplayStatus.expired:
      return 'Expired';
    case MembershipDisplayStatus.cancelled:
      return 'Cancelled';
    case MembershipDisplayStatus.noMembership:
      return 'No Membership';
  }
}

StatusTone membershipDisplayStatusTone(MembershipDisplayStatus status) {
  switch (status) {
    case MembershipDisplayStatus.active:
      return StatusTone.success;
    case MembershipDisplayStatus.expiringSoon:
      return StatusTone.warning;
    case MembershipDisplayStatus.expired:
      return StatusTone.danger;
    case MembershipDisplayStatus.cancelled:
      return StatusTone.neutral;
    case MembershipDisplayStatus.noMembership:
      return StatusTone.neutral;
  }
}