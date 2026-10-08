import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/data/models/guest_booking_dashboard.dart';
import 'package:gameall_club_mobile/features/bookings/potential_members.dart';
import 'package:gameall_club_mobile/features/memberships/member_schedule.dart';

/// Potential Members and Membership Schedule — the pure logic, with the same expectations as the
/// web's potential-members.ts / member-schedule.ts so both apps agree on who qualifies.
void main() {
  final now = DateTime(2026, 10, 7, 12);

  GuestBookingRow booking(String phone, String name, DateTime start, {String court = 'Court 1', int paid = 50000, String status = 'confirmed'}) =>
      GuestBookingRow(
        bookingId: '${phone}_${start.toIso8601String()}',
        code: 'GBK',
        guestName: name,
        guestPhone: phone,
        courtName: court,
        startTime: start,
        endTime: start.add(const Duration(hours: 1)),
        partySize: 1,
        amountMinor: paid,
        paidMinor: paid,
        currency: 'INR',
        paymentStatus: 'PAID',
        status: status,
      );

  List<GuestBookingRow> history(String phone, String name, int count, {String court = 'Court 1'}) =>
      [for (var i = 1; i <= count; i++) booking(phone, name, now.subtract(Duration(days: i * 5)), court: court)];

  group('phoneKey', () {
    test('uses the last ten digits', () => expect(phoneKey('+91 98765 43210'), '9876543210'));
    test('rejects numbers too short to be real', () => expect(phoneKey('12345'), isNull));
    test('handles null', () => expect(phoneKey(null), isNull));
  });

  group('buildGuestProfiles / potentialMembers', () {
    test('a guest with 3+ bookings who is not a member is a potential member', () {
      final profiles = buildGuestProfiles(history('9876543210', 'Asha', 3), {}, now);
      expect(profiles.single.bookings, 3);
      expect(potentialMembers(profiles), hasLength(1));
    });

    test('fewer than 3 bookings is not enough', () {
      expect(potentialMembers(buildGuestProfiles(history('9876543210', 'Asha', 2), {}, now)), isEmpty);
    });

    test('a guest whose phone matches a current member is a member, not a potential one', () {
      final profiles = buildGuestProfiles(history('9876543210', 'Asha', 5), {'9876543210'}, now);
      expect(profiles.single.isMember, isTrue);
      expect(potentialMembers(profiles), isEmpty);
    });

    test('cancelled bookings never count', () {
      final rows = [
        ...history('9876543210', 'Asha', 2),
        booking('9876543210', 'Asha', now.subtract(const Duration(days: 40)), status: 'cancelled'),
      ];
      expect(buildGuestProfiles(rows, {}, now).single.bookings, 2);
    });

    test('the same number written two ways is one guest', () {
      final rows = [
        booking('9876543210', 'Asha', now.subtract(const Duration(days: 1))),
        booking('+91 98765 43210', 'Asha', now.subtract(const Duration(days: 2))),
        booking('098765-43210', 'Asha', now.subtract(const Duration(days: 3))),
      ];
      final profiles = buildGuestProfiles(rows, {}, now);
      expect(profiles, hasLength(1));
      expect(profiles.single.bookings, 3);
    });

    test('money is summed and the favourite court wins', () {
      final rows = [
        booking('9876543210', 'Asha', now.subtract(const Duration(days: 1)), court: 'Court 2', paid: 30000),
        booking('9876543210', 'Asha', now.subtract(const Duration(days: 2)), court: 'Court 2', paid: 30000),
        booking('9876543210', 'Asha', now.subtract(const Duration(days: 3)), court: 'Court 1', paid: 40000),
      ];
      final p = buildGuestProfiles(rows, {}, now).single;
      expect(p.totalSpentMinor, 100000);
      expect(p.preferredCourt, 'Court 2');
    });

    test('Frequent if they booked in the last 30 days, otherwise Returning', () {
      expect(buildGuestProfiles(history('9876543210', 'A', 3), {}, now).single.label, 'Frequent');
      final old = [for (var i = 0; i < 3; i++) booking('9111111111', 'B', now.subtract(Duration(days: 60 + i)))];
      expect(buildGuestProfiles(old, {}, now).single.label, 'Returning');
    });
  });

  group('segmentStats', () {
    test('counts the segment and the share of frequent guests it makes up', () {
      final guests = [
        ...buildGuestProfiles(history('9000000001', 'A', 3), {}, now),
        ...buildGuestProfiles(history('9000000002', 'B', 5), {}, now),
        ...buildGuestProfiles(history('9000000003', 'C', 4), {'9000000003'}, now), // a member
        ...buildGuestProfiles(history('9000000004', 'D', 1), {}, now), // too few bookings
      ];
      final s = segmentStats(guests);
      expect(s.count, 2);
      expect(s.avgBookings, 4);
      expect(s.conversionPercent, closeTo(2 / 3 * 100, 0.001)); // 2 of the 3 guests with 3+ bookings
    });

    test('an empty list is all zeros', () {
      final s = segmentStats(const []);
      expect([s.count, s.conversionPercent, s.avgBookings, s.monthlyRevenueMinor], [0, 0, 0, 0]);
    });
  });

  group('filterPotential / sortByBookings', () {
    final guests = potentialMembers([
      ...buildGuestProfiles(history('9000000001', 'Asha Rao', 3, court: 'Court 1'), {}, now),
      ...buildGuestProfiles(history('9000000002', 'Bala Kumar', 6, court: 'Court 2'), {}, now),
      ...buildGuestProfiles(history('9000000003', 'Chitra Devi', 10, court: 'Court 2'), {}, now),
    ]);

    test('by name', () => expect(filterPotential(guests, const PotentialFilters(search: 'bala'), now).map((g) => g.name), ['Bala Kumar']));
    test('by phone digits', () => expect(filterPotential(guests, const PotentialFilters(search: '0003'), now).map((g) => g.name), ['Chitra Devi']));
    test('by preferred court', () => expect(filterPotential(guests, const PotentialFilters(court: 'Court 2'), now), hasLength(2)));
    test('by minimum bookings', () => expect(filterPotential(guests, const PotentialFilters(minBookings: 5), now), hasLength(2)));
    test('by total spent', () {
      final names = filterPotential(guests, const PotentialFilters(minSpentMinor: 250000), now).map((g) => g.name).toSet();
      expect(names, {'Bala Kumar', 'Chitra Devi'});
    });
    test('most bookings first by default, ascending on request', () {
      expect(sortByBookings(guests, descending: true).map((g) => g.bookings), [10, 6, 3]);
      expect(sortByBookings(guests, descending: false).map((g) => g.bookings), [3, 6, 10]);
    });
  });

  group('groupMemberSchedules', () {
    MemberScheduleRow row(String member, String name, String batch, String court, List<int> days, {String? membershipId}) => MemberScheduleRow(
          memberId: member,
          fullName: name,
          phone: '9000000000',
          status: 'ACTIVE',
          membershipId: membershipId,
          batchId: batch,
          batchName: batch,
          courtId: court,
          courtName: court,
          facilitySportId: 's1',
          sportName: 'Badminton',
          daysOfWeek: days,
          startTime: '07:00',
          endTime: '08:00',
        );

    test('one entry per member, sorted by name, with every slot', () {
      final grouped = groupMemberSchedules([
        row('m2', 'Zoya', 'b1', 'Court 1', [1]),
        row('m1', 'Anil', 'b1', 'Court 1', [1, 3]),
        row('m1', 'Anil', 'b2', 'Court 2', [5]),
      ]);
      expect(grouped.map((m) => m.fullName), ['Anil', 'Zoya']);
      expect(grouped.first.slots, hasLength(2));
      expect(grouped.first.courts.map((c) => c.name), ['Court 1', 'Court 2']);
    });

    test("prefers any non-null membership id across a member's batches", () {
      final grouped = groupMemberSchedules([
        row('m1', 'Anil', 'b1', 'Court 1', [1]),
        row('m1', 'Anil', 'b2', 'Court 1', [2], membershipId: 'ms1'),
      ]);
      expect(grouped.single.membershipId, 'ms1');
    });

    test('a slot recurs on the right weekday (Dart Mon=1…Sun=7 vs database Sun=0…Sat=6)', () {
      final s = groupMemberSchedules([row('m1', 'A', 'b1', 'c', [0, 1])]).single.slots.single; // Sun, Mon
      expect(s.occursOn(DateTime(2026, 10, 5)), isTrue); // Monday
      expect(s.occursOn(DateTime(2026, 10, 4)), isTrue); // Sunday
      expect(s.occursOn(DateTime(2026, 10, 6)), isFalse); // Tuesday
    });

    test('preferred time bands morning vs evening', () {
      final m = MemberScheduleSummary(memberId: 'm', fullName: 'A', phone: '1', status: 'ACTIVE', membershipId: null, slots: [
        const MemberBatchSlot(batchId: 'b1', batchName: 'b', courtId: 'c', courtName: 'c', daysOfWeek: [1], startTime: '07:00', endTime: '08:00'),
        const MemberBatchSlot(batchId: 'b2', batchName: 'b', courtId: 'c', courtName: 'c', daysOfWeek: [2], startTime: '18:00', endTime: '19:00'),
      ]);
      expect(m.preferredTime, 'Morning (07:00 – 08:00), Evening (18:00 – 19:00)');
    });
  });
}
