import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/data/models/membership.dart';
import 'package:gameall_club_mobile/features/memberships/members_ordering.dart';

/// The Memberships → Members tab: who is listed first, and the numbers on its card.
void main() {
  final now = DateTime(2026, 10, 8, 12);

  MembershipListRow row(String name, MembershipListStatus status, DateTime start, {DateTime? end}) => MembershipListRow(
        membershipId: 'ms_$name',
        memberId: 'm_$name',
        memberName: name,
        memberPhone: '9000000000',
        planName: 'Monthly',
        monthlyPriceInr: 1000,
        status: status,
        startDate: start,
        endDate: end ?? start.add(const Duration(days: 365)),
      );

  group('orderMembersForDisplay', () {
    test('Active members come before Inactive ones, however recently the inactive ones joined', () {
      final ordered = orderMembersForDisplay([
        row('InactiveNew', MembershipListStatus.inactive, DateTime(2026, 10, 1)),
        row('ActiveOld', MembershipListStatus.active, DateTime(2025, 1, 1)),
      ]);
      expect(ordered.map((m) => m.memberName), ['ActiveOld', 'InactiveNew']);
    });

    test('within a status the most recent joiner is first', () {
      final ordered = orderMembersForDisplay([
        row('A', MembershipListStatus.active, DateTime(2026, 1, 5)),
        row('C', MembershipListStatus.active, DateTime(2026, 9, 20)),
        row('B', MembershipListStatus.active, DateTime(2026, 5, 11)),
      ]);
      expect(ordered.map((m) => m.memberName), ['C', 'B', 'A']);
    });

    test('payment-incomplete sits between active and inactive', () {
      final ordered = orderMembersForDisplay([
        row('I', MembershipListStatus.inactive, DateTime(2026, 9, 1)),
        row('U', MembershipListStatus.paymentIncomplete, DateTime(2026, 9, 1)),
        row('A', MembershipListStatus.active, DateTime(2026, 9, 1)),
      ]);
      expect(ordered.map((m) => m.memberName), ['A', 'U', 'I']);
    });

    test('a tie on start date goes to the later end date', () {
      final ordered = orderMembersForDisplay([
        row('Short', MembershipListStatus.active, DateTime(2026, 9, 1), end: DateTime(2026, 12, 1)),
        row('Long', MembershipListStatus.active, DateTime(2026, 9, 1), end: DateTime(2027, 9, 1)),
      ]);
      expect(ordered.map((m) => m.memberName), ['Long', 'Short']);
    });

    test('does not reorder the list it was given', () {
      final input = [
        row('Old', MembershipListStatus.active, DateTime(2025, 1, 1)),
        row('New', MembershipListStatus.active, DateTime(2026, 9, 1)),
      ];
      orderMembersForDisplay(input);
      expect(input.first.memberName, 'Old');
    });

    test('an empty list stays empty', () => expect(orderMembersForDisplay(const []), isEmpty));
  });

  group('isExpiringSoon', () {
    test('an active membership ending within 30 days is expiring', () {
      expect(isExpiringSoon(row('A', MembershipListStatus.active, DateTime(2026, 1, 1), end: now.add(const Duration(days: 10))), now), isTrue);
    });
    test('ending in 31+ days is not', () {
      expect(isExpiringSoon(row('A', MembershipListStatus.active, DateTime(2026, 1, 1), end: now.add(const Duration(days: 45))), now), isFalse);
    });
    test('one that has already ended is not "expiring soon"', () {
      expect(isExpiringSoon(row('A', MembershipListStatus.active, DateTime(2026, 1, 1), end: now.subtract(const Duration(days: 1))), now), isFalse);
    });
    test('only active memberships count', () {
      expect(isExpiringSoon(row('A', MembershipListStatus.inactive, DateTime(2026, 1, 1), end: now.add(const Duration(days: 5))), now), isFalse);
    });
  });

  group('countMembers', () {
    final rows = [
      row('A1', MembershipListStatus.active, DateTime(2026, 1, 1), end: now.add(const Duration(days: 7))), // expiring
      row('A2', MembershipListStatus.active, DateTime(2026, 2, 1), end: now.add(const Duration(days: 200))),
      row('A3', MembershipListStatus.active, DateTime(2026, 3, 1), end: now.add(const Duration(days: 20))), // expiring
      row('I1', MembershipListStatus.inactive, DateTime(2025, 1, 1)),
      row('U1', MembershipListStatus.paymentIncomplete, DateTime(2026, 8, 1)),
    ];

    test('splits the members into active, inactive and expiring', () {
      final c = countMembers(rows, now);
      expect(c.total, 5);
      expect(c.active, 3);
      expect(c.inactive, 1);
      expect(c.expiring, 2);
    });

    test("uses the facility's full count as the total when the list was capped", () {
      expect(countMembers(rows, now, total: 186).total, 186);
    });
  });

  group('utilizationPercent', () {
    AssignableBatch batch(int capacity, int enrolled) => AssignableBatch(
          batchId: 'b$capacity$enrolled',
          name: 'B',
          planId: null,
          courtId: 'c',
          courtName: 'Court',
          facilitySportId: 's',
          sportName: 'Badminton',
          daysOfWeek: const [1],
          startTime: '07:00',
          endTime: '08:00',
          capacity: capacity,
          enrolledCount: enrolled,
          spare: (capacity - enrolled).clamp(0, capacity),
        );

    test('is filled seats over total seats across every batch', () {
      expect(utilizationPercent([batch(10, 5), batch(10, 10)]), 75);
    });
    test('rounds to a whole percent', () => expect(utilizationPercent([batch(3, 1)]), 33));
    test('is null when there are no seats at all', () {
      expect(utilizationPercent(const []), isNull);
      expect(utilizationPercent([batch(0, 0)]), isNull);
    });
    test('never exceeds 100', () => expect(utilizationPercent([batch(2, 5)]), 100));
  });
}
