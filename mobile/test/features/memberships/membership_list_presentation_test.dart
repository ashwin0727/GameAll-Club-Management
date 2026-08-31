import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/data/models/membership.dart';
import 'package:gameall_club_mobile/features/memberships/membership_list_presentation.dart';
import 'package:gameall_club_mobile/shared/widgets/misc.dart';

/// Mirrors `memberships-page.tsx`'s `statusBadge` / `expiryHint`.
void main() {
  group('membershipListStatus label + tone', () {
    test('every status maps to a label and a non-null tone', () {
      for (final status in MembershipListStatus.values) {
        expect(membershipListStatusLabel(status), isNotEmpty);
        expect(membershipListStatusTone(status), isA<StatusTone>());
      }
      expect(membershipListStatusTone(MembershipListStatus.active), StatusTone.success);
      expect(membershipListStatusTone(MembershipListStatus.expiringSoon), StatusTone.warning);
      expect(membershipListStatusTone(MembershipListStatus.expired), StatusTone.danger);
      expect(membershipListStatusTone(MembershipListStatus.cancelled), StatusTone.neutral);
    });
  });

  group('membershipExpiryHint boundaries', () {
    test('cancelled short-circuits regardless of days left', () {
      final hint = membershipExpiryHint(MembershipListStatus.cancelled, 40);
      expect(hint.text, 'Cancelled');
      expect(hint.tone, StatusTone.neutral);
    });

    test('negative days -> expired N days ago (danger)', () {
      final hint = membershipExpiryHint(MembershipListStatus.expired, -3);
      expect(hint.text, 'Expired 3 days ago');
      expect(hint.tone, StatusTone.danger);
    });

    test('zero days -> expires today (warning)', () {
      final hint = membershipExpiryHint(MembershipListStatus.active, 0);
      expect(hint.text, 'Expires today');
      expect(hint.tone, StatusTone.warning);
    });

    test('within 30 days -> warning, beyond -> success', () {
      expect(membershipExpiryHint(MembershipListStatus.active, 30).tone, StatusTone.warning);
      expect(membershipExpiryHint(MembershipListStatus.active, 31).tone, StatusTone.success);
    });
  });

  group('MembershipListStatus db mapping round-trips', () {
    test('to/from db string', () {
      for (final status in MembershipListStatus.values) {
        expect(membershipListStatusFromDb(membershipListStatusToDb(status)!), status);
      }
      expect(membershipListStatusToDb(null), isNull);
    });
  });
}