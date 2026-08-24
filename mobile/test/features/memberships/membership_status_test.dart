import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/data/models/membership.dart';
import 'package:gameall_club_mobile/features/memberships/membership_status.dart';

void main() {
  final now = DateTime.utc(2026, 8, 23, 12, 0, 0);

  group('computeMembershipStatus', () {
    test('is cancelled regardless of dates when the DB status is cancelled', () {
      expect(
        computeMembershipStatus(status: MembershipStatus.cancelled, endDate: DateTime.utc(2027, 1, 1), now: now),
        MembershipDisplayStatus.cancelled,
      );
      expect(
        computeMembershipStatus(status: MembershipStatus.cancelled, endDate: DateTime.utc(2020, 1, 1), now: now),
        MembershipDisplayStatus.cancelled,
      );
    });

    test('is expired once the end date has passed', () {
      expect(
        computeMembershipStatus(status: MembershipStatus.active, endDate: DateTime.utc(2026, 8, 1), now: now),
        MembershipDisplayStatus.expired,
      );
    });

    test('is expiringSoon within the warning window', () {
      expect(
        computeMembershipStatus(status: MembershipStatus.active, endDate: DateTime.utc(2026, 8, 28), now: now),
        MembershipDisplayStatus.expiringSoon,
      );
      expect(
        computeMembershipStatus(status: MembershipStatus.active, endDate: DateTime.utc(2026, 8, 23), now: now),
        MembershipDisplayStatus.expiringSoon,
      );
    });

    test('is active well before expiry', () {
      expect(
        computeMembershipStatus(status: MembershipStatus.active, endDate: DateTime.utc(2026, 12, 1), now: now),
        MembershipDisplayStatus.active,
      );
    });

    test('is noMembership for a member who has never been assigned a plan', () {
      expect(computeMembershipStatus(status: null, endDate: null, now: now), MembershipDisplayStatus.noMembership);
    });
  });

  group('daysUntilExpiry', () {
    test('returns a positive count for a future date', () {
      expect(daysUntilExpiry(DateTime.utc(2026, 8, 30), DateTime.utc(2026, 8, 23)), greaterThan(0));
    });

    test('returns a negative count for a past date', () {
      expect(daysUntilExpiry(DateTime.utc(2026, 8, 1), DateTime.utc(2026, 8, 23)), lessThan(0));
    });
  });

  group('computeMembershipEndDate', () {
    test('adds duration_days to the start date', () {
      expect(computeMembershipEndDate(DateTime.utc(2026, 1, 1), 30), DateTime.utc(2026, 1, 31));
    });

    test('handles month/year rollovers', () {
      expect(computeMembershipEndDate(DateTime.utc(2026, 12, 15), 365), DateTime.utc(2027, 12, 15));
    });
  });
}