import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/data/models/membership.dart';
import 'package:gameall_club_mobile/features/memberships/membership_list_presentation.dart';
import 'package:gameall_club_mobile/shared/widgets/misc.dart';

/// Mirrors `memberships-page.tsx`'s `statusBadge` — the payment-driven
/// three-state model.
void main() {
  group('membershipListStatus label + tone', () {
    test('every status maps to a label and a tone', () {
      for (final status in MembershipListStatus.values) {
        expect(membershipListStatusLabel(status), isNotEmpty);
        expect(membershipListStatusTone(status), isA<StatusTone>());
      }
      expect(membershipListStatusLabel(MembershipListStatus.paymentIncomplete), 'Payment Incomplete');
      expect(membershipListStatusTone(MembershipListStatus.active), StatusTone.success);
      expect(membershipListStatusTone(MembershipListStatus.paymentIncomplete), StatusTone.warning);
      expect(membershipListStatusTone(MembershipListStatus.inactive), StatusTone.neutral);
    });
  });

  group('MembershipListStatus db mapping round-trips', () {
    test('to/from db string', () {
      for (final status in MembershipListStatus.values) {
        expect(membershipListStatusFromDb(membershipListStatusToDb(status)!), status);
      }
      expect(membershipListStatusToDb(null), isNull);
      expect(membershipListStatusFromDb('payment_incomplete'), MembershipListStatus.paymentIncomplete);
      expect(membershipListStatusFromDb('inactive'), MembershipListStatus.inactive);
    });
  });

  group('MembershipListSort db mapping', () {
    test('maps to the RPC sort keys', () {
      expect(membershipListSortToDb(MembershipListSort.oldest), 'oldest');
      expect(membershipListSortToDb(MembershipListSort.nextPayment), 'next_payment');
      expect(membershipListSortToDb(MembershipListSort.name), 'name');
    });
  });

  group('isPastDate', () {
    final now = DateTime(2026, 9, 1);
    test('true for a date before today, false for today or later', () {
      expect(isPastDate(DateTime(2026, 8, 31), now), isTrue);
      expect(isPastDate(DateTime(2026, 9, 1), now), isFalse);
      expect(isPastDate(DateTime(2026, 9, 2), now), isFalse);
    });
  });
}