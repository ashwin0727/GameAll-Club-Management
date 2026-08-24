import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/features/membership_sessions/capacity.dart';

/// Mirrors src/features/membership-sessions/capacity.test.ts — every case
/// ported 1:1 so the two clients agree on the exact same derived-capacity
/// arithmetic and display-state priority order.
void main() {
  group('deriveMembershipCapacity', () {
    test('computes unused and guest-available capacity from the four raw counts', () {
      final capacity =
          deriveMembershipCapacity(capacity: 5, releasedCapacity: 0, memberBookedCount: 3, guestBookedCount: 0);
      expect(capacity.unusedCapacity, 2);
      expect(capacity.guestAvailableCapacity, 0);
    });

    test('distinguishes allocated capacity from actual usage — never conflates the two (spec §41)', () {
      final capacity =
          deriveMembershipCapacity(capacity: 5, releasedCapacity: 2, memberBookedCount: 3, guestBookedCount: 2);
      expect(capacity.capacity, 5);
      expect(capacity.memberBookedCount, 3);
      expect(capacity.releasedCapacity, 2);
      expect(capacity.guestBookedCount, 2);
      expect(capacity.unusedCapacity, 2);
      expect(capacity.guestAvailableCapacity, 0);
    });
  });

  group('maxReleasable', () {
    test("is the unused capacity minus what's already released", () {
      final capacity =
          deriveMembershipCapacity(capacity: 5, releasedCapacity: 0, memberBookedCount: 3, guestBookedCount: 0);
      expect(maxReleasable(capacity), 2);
    });

    test('is zero once every unused slot has been released', () {
      final capacity =
          deriveMembershipCapacity(capacity: 5, releasedCapacity: 2, memberBookedCount: 3, guestBookedCount: 0);
      expect(maxReleasable(capacity), 0);
    });

    test('is zero when membership capacity is fully used (spec §10)', () {
      final capacity =
          deriveMembershipCapacity(capacity: 5, releasedCapacity: 0, memberBookedCount: 5, guestBookedCount: 0);
      expect(maxReleasable(capacity), 0);
    });
  });

  group('maxRestorable', () {
    test('is the full released amount when no guest has booked yet', () {
      final capacity =
          deriveMembershipCapacity(capacity: 5, releasedCapacity: 2, memberBookedCount: 3, guestBookedCount: 0);
      expect(maxRestorable(capacity), 2);
    });

    test('is reduced by however many guests already booked (spec §18/§19)', () {
      final capacity =
          deriveMembershipCapacity(capacity: 5, releasedCapacity: 2, memberBookedCount: 3, guestBookedCount: 1);
      expect(maxRestorable(capacity), 1);
    });

    test('is zero once every released slot is guest-booked', () {
      final capacity =
          deriveMembershipCapacity(capacity: 5, releasedCapacity: 2, memberBookedCount: 3, guestBookedCount: 2);
      expect(maxRestorable(capacity), 0);
    });
  });

  group('computeSlotDisplayState', () {
    test('is membershipAllocated when nothing has happened yet', () {
      final capacity =
          deriveMembershipCapacity(capacity: 5, releasedCapacity: 0, memberBookedCount: 0, guestBookedCount: 0);
      expect(computeSlotDisplayState(capacity), MembershipSlotDisplayState.membershipAllocated);
    });

    test('is membershipPartiallyUsed once some but not all members have booked', () {
      final capacity =
          deriveMembershipCapacity(capacity: 5, releasedCapacity: 0, memberBookedCount: 3, guestBookedCount: 0);
      expect(computeSlotDisplayState(capacity), MembershipSlotDisplayState.membershipPartiallyUsed);
    });

    test('is membershipFull once every capacity slot is member-booked', () {
      final capacity =
          deriveMembershipCapacity(capacity: 5, releasedCapacity: 0, memberBookedCount: 5, guestBookedCount: 0);
      expect(computeSlotDisplayState(capacity), MembershipSlotDisplayState.membershipFull);
    });

    test("is releasedForGuest once the owner releases capacity that hasn't all been guest-booked", () {
      final capacity =
          deriveMembershipCapacity(capacity: 5, releasedCapacity: 2, memberBookedCount: 3, guestBookedCount: 0);
      expect(computeSlotDisplayState(capacity), MembershipSlotDisplayState.releasedForGuest);
    });

    test('is guestBooked once every released slot is taken by a guest', () {
      final capacity =
          deriveMembershipCapacity(capacity: 5, releasedCapacity: 2, memberBookedCount: 3, guestBookedCount: 2);
      expect(computeSlotDisplayState(capacity), MembershipSlotDisplayState.guestBooked);
    });
  });
}