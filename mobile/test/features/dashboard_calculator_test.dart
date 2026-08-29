import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/data/models/dashboard.dart';
import 'package:gameall_club_mobile/data/models/operating_hours.dart';
import 'package:gameall_club_mobile/features/dashboard/dashboard_calculator.dart';

OperatingDay _openDay(int dow, {String start = '06:00', String end = '23:00'}) {
  return OperatingDay(
    dayOfWeek: dow,
    isClosed: false,
    is24Hours: false,
    slots: [OperatingTimeSlot(startTime: start, endTime: end, crossesMidnight: false, displayOrder: 0)],
  );
}

OperatingDay _closedDay(int dow) =>
    OperatingDay(dayOfWeek: dow, isClosed: true, is24Hours: false, slots: const []);

void main() {
  group('resolveDateRange', () {
    test('TODAY spans exactly 24 hours with a comparable previous day', () {
      final now = DateTime(2026, 8, 24, 15);
      final resolved = DashboardCalculator.resolveDateRange(DateRangePreset.today, now);
      expect(resolved.current.to.difference(resolved.current.from), const Duration(days: 1));
      expect(resolved.previous, isNotNull);
    });

    test('THIS_MONTH starts on the 1st of the current month', () {
      final now = DateTime(2026, 8, 24);
      final resolved = DashboardCalculator.resolveDateRange(DateRangePreset.thisMonth, now);
      expect(resolved.current.from.day, 1);
    });
  });

  group('computeKpiValue', () {
    test('computes a positive percent change', () {
      final kpi = DashboardCalculator.computeKpiValue(120, 100);
      expect(kpi.changePercent, 20);
    });

    test('never divides by zero', () {
      final kpi = DashboardCalculator.computeKpiValue(50, 0);
      expect(kpi.changePercent, isNull);
    });

    test('has no comparison when there is no previous period', () {
      final kpi = DashboardCalculator.computeKpiValue(50, null);
      expect(kpi.changePercent, isNull);
      expect(kpi.previousValue, isNull);
    });
  });

  group('operatingMinutesForDay + computeUtilizationPercent', () {
    test('a closed day has zero available minutes', () {
      expect(DashboardCalculator.operatingMinutesForDay(_closedDay(1)), 0);
    });

    test('a 24-hour day has 1440 available minutes', () {
      final day = OperatingDay(dayOfWeek: 1, isClosed: false, is24Hours: true, slots: const []);
      expect(DashboardCalculator.operatingMinutesForDay(day), 1440);
    });

    test('utilization is 0% with no available time, not a division error', () {
      expect(DashboardCalculator.computeUtilizationPercent(60, 0), 0);
    });

    test('utilization is capped at 100%', () {
      expect(DashboardCalculator.computeUtilizationPercent(200, 100), 100);
    });
  });

  group('toUtilizationBookings (membership session usage feeds utilization, allocation alone does not)', () {
    test('converts a confirmed-usage session into a synthetic booking spanning its full duration', () {
      final result = DashboardCalculator.toUtilizationBookings([
        (courtId: 'court-1', sessionDate: '2026-08-24', startTime: '18:00:00', endTime: '19:00:00'),
      ]);
      final booking = result.single;
      expect(booking.playingAreaId, 'court-1');
      expect(booking.status, 'confirmed');
      expect(DashboardCalculator.bookingDurationMinutes(booking.startTime, booking.endTime), 60);
    });

    test('occupies the court once per session regardless of how many members/guests are in it', () {
      // get_membership_utilization_sessions already dedupes to one row per
      // session with any confirmed booking — the conversion must not
      // multiply that by headcount.
      final result = DashboardCalculator.toUtilizationBookings([
        (courtId: 'court-1', sessionDate: '2026-08-24', startTime: '18:00:00', endTime: '19:00:00'),
      ]);
      expect(result, hasLength(1));
    });

    test('merges into computeUtilization exactly like a real booking — spec\'s 80% partial-release scenario', () {
      final period = DateRange(from: DateTime(2026, 8, 24), to: DateTime(2026, 8, 25));
      // Capacity 5, 3 members + 1 guest confirmed (1 released slot still
      // unused) — the session occupies its single 1h slot out of a 5h open
      // window = 20% for that court, distinct from "5/5 allocated" or
      // headcount-based math.
      final membershipBookings = DashboardCalculator.toUtilizationBookings([
        (courtId: 'court-1', sessionDate: '2026-08-24', startTime: '18:00:00', endTime: '19:00:00'),
      ]);
      final result = DashboardCalculator.computeUtilization(
        playingAreas: [(id: 'court-1', name: 'Court 1', facilitySportId: 'fs-1')],
        facilitySports: [(id: 'fs-1', sportId: 'sport-1')],
        sports: [(id: 'sport-1', name: 'Badminton')],
        facilityOperatingDays: [_openDay(1, start: '18:00', end: '23:00')], // 5h open
        bookings: membershipBookings,
        period: period,
      );
      expect(result.overallPercent, 20);
    });

    test('contributes zero occupied time when nothing has actually been confirmed (allocation != usage)', () {
      final period = DateRange(from: DateTime(2026, 8, 24), to: DateTime(2026, 8, 25));
      final result = DashboardCalculator.computeUtilization(
        playingAreas: [(id: 'court-1', name: 'Court 1', facilitySportId: 'fs-1')],
        facilitySports: [(id: 'fs-1', sportId: 'sport-1')],
        sports: [(id: 'sport-1', name: 'Badminton')],
        facilityOperatingDays: [_openDay(1, start: '18:00', end: '19:00')],
        bookings: const [], // no membership session row is fed in when nobody confirmed
        period: period,
      );
      expect(result.overallPercent, 0);
    });
  });

  group('computeUtilization', () {
    test('excludes cancelled bookings from utilization', () {
      final period = DateRange(from: DateTime(2026, 8, 24), to: DateTime(2026, 8, 25));
      final result = DashboardCalculator.computeUtilization(
        playingAreas: [(id: 'court-1', name: 'Court 1', facilitySportId: 'fs-1')],
        facilitySports: [(id: 'fs-1', sportId: 'sport-1')],
        sports: [(id: 'sport-1', name: 'Badminton')],
        facilityOperatingDays: [_openDay(1, start: '06:00', end: '12:00')],
        bookings: [
          (
            playingAreaId: 'court-1',
            startTime: DateTime(2026, 8, 24, 6),
            endTime: DateTime(2026, 8, 24, 9),
            status: 'confirmed',
          ),
          (
            playingAreaId: 'court-1',
            startTime: DateTime(2026, 8, 24, 9),
            endTime: DateTime(2026, 8, 24, 12),
            status: 'cancelled',
          ),
        ],
        period: period,
      );
      expect(result.overallPercent, 50);
    });
  });

  group('summarizeMemberships', () {
    test('counts active/expired/expiring-soon/new-this-month independently', () {
      final now = DateTime(2026, 8, 24);
      final result = DashboardCalculator.summarizeMemberships([
        (status: 'active', endDate: DateTime(2026, 8, 26), createdAt: DateTime(2026, 8, 1)),
        (status: 'active', endDate: DateTime(2026, 12, 1), createdAt: DateTime(2026, 1, 1)),
        (status: 'expired', endDate: DateTime(2026, 7, 1), createdAt: DateTime(2026, 1, 1)),
      ], now);
      expect(result.active, 2);
      expect(result.expiringSoon, 1);
      expect(result.expired, 1);
      expect(result.newThisMonth, 1);
    });

    test('is all zero for an empty facility — a valid empty state', () {
      final result = DashboardCalculator.summarizeMemberships(const [], DateTime(2026, 8, 24));
      expect(result.active, 0);
      expect(result.expiringSoon, 0);
    });
  });

  group('summarizePayments', () {
    test('splits paid/created/refunded into collected/pending/refunds', () {
      final result = DashboardCalculator.summarizePayments([
        (status: 'paid', amountInr: 1000),
        (status: 'created', amountInr: 500),
        (status: 'refunded', amountInr: 200),
        (status: 'failed', amountInr: 300),
      ]);
      expect(result.collectedInr, 1000);
      expect(result.pendingInr, 500);
      expect(result.refundsInr, 200);
    });
  });

  group('buildAttentionItems', () {
    test('generates nothing when everything is healthy', () {
      final items = DashboardCalculator.buildAttentionItems(
        membershipsExpiringSoon: 0,
        paymentsPendingInr: 0,
      );
      expect(items, isEmpty);
    });

    test('generates one item per real condition', () {
      final items = DashboardCalculator.buildAttentionItems(
        membershipsExpiringSoon: 2,
        paymentsPendingInr: 500,
      );
      expect(items.map((i) => i.id), ['memberships-expiring', 'payments-pending']);
    });
  });

  group('buildScheduleTimeline', () {
    final areas = [
      (id: 'court-1', name: 'Court 1', facilitySportId: 'fs-1'),
      (id: 'court-2', name: 'Court 2', facilitySportId: 'fs-1'),
    ];
    const facilitySports = [(id: 'fs-1', sportId: 'sport-1')];
    const sports = [(id: 'sport-1', name: 'Badminton')];

    ({
      String id,
      String playingAreaId,
      DateTime startTime,
      DateTime endTime,
      String status,
      ScheduleBlockType type,
      String label,
    })
    booking(String id, String court, int startH, int endH, {ScheduleBlockType type = ScheduleBlockType.member, String status = 'confirmed'}) {
      return (
        id: id,
        playingAreaId: court,
        startTime: DateTime(2026, 8, 24, startH),
        endTime: DateTime(2026, 8, 24, endH),
        status: status,
        type: type,
        label: id,
      );
    }

    test('derives the hour axis from operating slots and positions a block by its real time', () {
      final timeline = DashboardCalculator.buildScheduleTimeline(
        playingAreas: areas,
        facilitySports: facilitySports,
        sports: sports,
        facilityOperatingDays: [_openDay(1, start: '06:00', end: '22:00')],
        bookings: [booking('Arun', 'court-1', 17, 18)],
        now: DateTime(2026, 8, 24, 10), // Monday
      );
      expect(timeline.startHour, 6);
      expect(timeline.endHour, 22);
      expect(timeline.courts, hasLength(2));
      final court1 = timeline.courts.firstWhere((c) => c.courtId == 'court-1');
      expect(court1.blocks, hasLength(1));
      expect(court1.blocks.first.startMinute, 17 * 60);
      expect(court1.blocks.first.endMinute, 18 * 60);
      expect(court1.blocks.first.lane, 0);
    });

    test('puts overlapping blocks in one court on separate lanes', () {
      final timeline = DashboardCalculator.buildScheduleTimeline(
        playingAreas: [areas[0]],
        facilitySports: facilitySports,
        sports: sports,
        facilityOperatingDays: [_openDay(1, start: '06:00', end: '22:00')],
        bookings: [
          booking('A', 'court-1', 17, 19),
          booking('B', 'court-1', 18, 20, type: ScheduleBlockType.guest),
        ],
        now: DateTime(2026, 8, 24, 10),
      );
      final court1 = timeline.courts.first;
      expect(court1.laneCount, 2);
      expect(court1.blocks.map((b) => b.lane).toSet(), {0, 1});
    });

    test('still renders every court on a default 6am-10pm axis with no operating hours', () {
      final closed = DashboardCalculator.buildScheduleTimeline(
        playingAreas: areas,
        facilitySports: facilitySports,
        sports: sports,
        facilityOperatingDays: [_closedDay(1)],
        bookings: const [],
        now: DateTime(2026, 8, 24, 10),
      );
      expect(closed.courts, hasLength(2));
      expect(closed.startHour, 6);
      expect(closed.endHour, 22);
      expect(closed.courts.every((c) => c.blocks.isEmpty), isTrue);
    });

    test('with no operating hours, still places bookings and fits the axis around them', () {
      final timeline = DashboardCalculator.buildScheduleTimeline(
        playingAreas: [areas[0]],
        facilitySports: facilitySports,
        sports: sports,
        facilityOperatingDays: [_closedDay(1)],
        bookings: [booking('G', 'court-1', 19, 20, type: ScheduleBlockType.guest)],
        now: DateTime(2026, 8, 24, 10),
      );
      expect(timeline.courts.first.blocks, hasLength(1));
      expect(timeline.startHour, lessThanOrEqualTo(19));
      expect(timeline.endHour, greaterThanOrEqualTo(20));
    });

    test('excludes cancelled bookings', () {
      final open = DashboardCalculator.buildScheduleTimeline(
        playingAreas: [areas[0]],
        facilitySports: facilitySports,
        sports: sports,
        facilityOperatingDays: [_openDay(1, start: '06:00', end: '22:00')],
        bookings: [booking('X', 'court-1', 17, 18, status: 'cancelled')],
        now: DateTime(2026, 8, 24, 10),
      );
      expect(open.courts.first.blocks, isEmpty);
    });
  });

  group('buildRevenueTrend', () {
    test('buckets paid revenue by local calendar day and zero-fills empty days', () {
      final period = DateRange(from: DateTime(2026, 8, 24), to: DateTime(2026, 8, 27));
      final trend = DashboardCalculator.buildRevenueTrend(
        [
          (status: 'paid', amountInr: 500, createdAt: DateTime(2026, 8, 24, 9)),
          (status: 'paid', amountInr: 300, createdAt: DateTime(2026, 8, 24, 18)),
          (status: 'created', amountInr: 999, createdAt: DateTime(2026, 8, 25, 10)),
          (status: 'paid', amountInr: 200, createdAt: DateTime(2026, 8, 26, 10)),
        ],
        period,
      );
      expect(trend.map((p) => p.date).toList(), ['2026-08-24', '2026-08-25', '2026-08-26']);
      expect(trend.map((p) => p.amountInr).toList(), [800, 0, 200]);
    });
  });

  group('buildRevenueOverview', () {
    final now = DateTime(2026, 8, 15);

    ({String status, int amountInr, DateTime createdAt, String? bookingId, String? membershipId}) pay(
      int amount,
      DateTime at, {
      String status = 'paid',
      String? bookingId,
      String? membershipId,
    }) => (status: status, amountInr: amount, createdAt: at, bookingId: bookingId, membershipId: membershipId);

    test('totals the selected month, compares to previous, always returns a full day series', () {
      final payments = [
        pay(1000, DateTime(2026, 7, 10)),
        pay(400, DateTime(2026, 8, 2), bookingId: 'b1'),
        pay(600, DateTime(2026, 8, 20), membershipId: 'm1'),
        pay(999, DateTime(2026, 8, 5), status: 'created'),
      ];
      final ov = DashboardCalculator.buildRevenueOverview(payments, now, 0);
      expect(ov.monthLabel, 'Aug 2026');
      expect(ov.totalInr, 1000);
      expect(ov.changePercent, 0);
      expect(ov.points, hasLength(31));
      expect(ov.points.fold<int>(0, (s, p) => s + p.amountInr), 1000);
      final byKey = {for (final s in ov.breakdown) s.key: s};
      expect(byKey[RevenueBreakdownKey.bookings]!.amountInr, 400);
      expect(byKey[RevenueBreakdownKey.bookings]!.count, 1);
      expect(byKey[RevenueBreakdownKey.memberships]!.amountInr, 600);
      expect(byKey[RevenueBreakdownKey.coaching]!.unavailable, isTrue);
    });

    test('returns a zero-filled month (non-empty) when there is no revenue', () {
      final ov = DashboardCalculator.buildRevenueOverview(const [], now, 1);
      expect(ov.monthLabel, 'Jul 2026');
      expect(ov.totalInr, 0);
      expect(ov.changePercent, isNull);
      expect(ov.points, hasLength(31));
      expect(ov.points.every((p) => p.amountInr == 0), isTrue);
    });
  });

  group('KPI helpers (sport + date scoped)', () {
    test('sumPaidRevenueInr sums paid payments, only in-scope ones under a sport', () {
      final payments = [
        (status: 'paid', amountInr: 500, bookingId: 'b1', membershipId: null),
        (status: 'paid', amountInr: 300, bookingId: null, membershipId: 'm1'),
        (status: 'paid', amountInr: 200, bookingId: 'b2', membershipId: null),
        (status: 'created', amountInr: 999, bookingId: 'b1', membershipId: null),
      ];
      expect(DashboardCalculator.sumPaidRevenueInr(payments, null), 1000);
      expect(
        DashboardCalculator.sumPaidRevenueInr(payments, (bookingIds: {'b1'}, membershipIds: {'m1'})),
        800,
      );
    });

    test('countActiveMemberships counts active, restricted to a sport when given', () {
      final memberships = [
        (id: 'm1', status: 'active'),
        (id: 'm2', status: 'active'),
        (id: 'm3', status: 'expired'),
      ];
      expect(DashboardCalculator.countActiveMemberships(memberships, null), 2);
      expect(DashboardCalculator.countActiveMemberships(memberships, {'m1', 'm3'}), 1);
    });

    test('countPaidGuestBookings counts only paid, non-cancelled guest bookings', () {
      expect(
        DashboardCalculator.countPaidGuestBookings([
          (customerType: 'GUEST', paymentStatus: 'PAID', status: 'confirmed'),
          (customerType: 'GUEST', paymentStatus: 'PENDING', status: 'confirmed'),
          (customerType: 'GUEST', paymentStatus: 'PAID', status: 'cancelled'),
          (customerType: 'MEMBER', paymentStatus: 'PAID', status: 'confirmed'),
        ]),
        1,
      );
    });
  });
}