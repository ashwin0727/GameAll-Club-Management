import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/data/models/dashboard.dart';
import 'package:gameall_club_mobile/data/models/operating_hours.dart';
import 'package:gameall_club_mobile/features/dashboard/dashboard_calculator.dart';

// The database now adds up the revenue chart and booked court time. These tests prove the screen shows the same thing whether it
// is built from every payment / booking row (the old way) or from the database's totals (the new way).
void main() {
  group('revenue chart from database totals', () {
    final now = DateTime(2026, 10, 29, 12);
    ({String status, int amountInr, DateTime createdAt, String? bookingId, String? membershipId, String? coachingEnrollmentId}) pay(
      int amount,
      DateTime at, {
      String status = 'paid',
      String? bookingId,
      String? membershipId,
      String? coachingEnrollmentId,
    }) => (
          status: status,
          amountInr: amount,
          createdAt: at,
          bookingId: bookingId,
          membershipId: membershipId,
          coachingEnrollmentId: coachingEnrollmentId,
        );

    void expectSame(RevenueOverview a, RevenueOverview b) {
      expect(a.monthLabel, b.monthLabel);
      expect(a.totalInr, b.totalInr);
      expect(a.changePercent, b.changePercent);
      expect(a.points.map((p) => '${p.date}:${p.amountInr}').toList(), b.points.map((p) => '${p.date}:${p.amountInr}').toList());
      expect(
        a.breakdown.map((s) => '${s.key}:${s.amountInr}:${s.count}:${s.unavailable}').toList(),
        b.breakdown.map((s) => '${s.key}:${s.amountInr}:${s.count}:${s.unavailable}').toList(),
      );
    }

    test('gives the same panel as the row-by-row calculation', () {
      final viaRows = DashboardCalculator.buildRevenueOverview([
        pay(1000, DateTime(2026, 10, 10, 10), bookingId: 'b1'),
        pay(500, DateTime(2026, 10, 11, 10), bookingId: 'b2'),
        pay(900, DateTime(2026, 10, 15, 10), membershipId: 'm1'),
        pay(400, DateTime(2026, 10, 15, 11)),
        pay(250, DateTime(2026, 10, 20, 10), coachingEnrollmentId: 'c1'),
        pay(300, DateTime(2026, 10, 12, 10), status: 'created', bookingId: 'b1'),
        pay(700, DateTime(2026, 9, 15, 10), bookingId: 'b3'),
      ], now, 0);
      final viaTotals = DashboardCalculator.buildRevenueOverviewFromTotals(
        totalInr: 3050,
        previousTotalInr: 700,
        byDay: {'2026-10-10': 1000, '2026-10-11': 500, '2026-10-15': 1300, '2026-10-20': 250},
        breakdown: {
          'bookings': (count: 2, inr: 1500),
          'memberships': (count: 1, inr: 900),
          'coaching': (count: 1, inr: 250),
          'other': (count: 1, inr: 400),
        },
        now: now,
        monthOffset: 0,
      );
      expectSame(viaTotals, viaRows);
    });

    test('a month with no revenue still draws a zero-filled series', () {
      final viaRows = DashboardCalculator.buildRevenueOverview(const [], now, 1);
      final viaTotals = DashboardCalculator.buildRevenueOverviewFromTotals(
        totalInr: 0,
        previousTotalInr: 0,
        byDay: const {},
        breakdown: const {},
        now: now,
        monthOffset: 1,
      );
      expectSame(viaTotals, viaRows);
    });
  });

  group('utilization from database minutes', () {
    final days = [for (var d = 0; d < 7; d++) OperatingDay(dayOfWeek: d, isClosed: false, is24Hours: false, slots: const [OperatingTimeSlot(startTime: '06:00', endTime: '22:00', crossesMidnight: false, displayOrder: 0)])];
    final areas = [(id: 'c1', name: 'Court 1', facilitySportId: 'fs1'), (id: 'c2', name: 'Court 2', facilitySportId: 'fs1')];
    final period = DateRange(from: DateTime(2026, 10, 5), to: DateTime(2026, 10, 7));
    UtilizationSummary compute({required List<({String playingAreaId, DateTime startTime, DateTime endTime, String status})> bookings, Map<String, double>? minutes}) =>
        DashboardCalculator.computeUtilization(
          playingAreas: areas,
          facilitySports: const [(id: 'fs1', sportId: 's1')],
          sports: const [(id: 's1', name: 'Badminton')],
          facilityOperatingDays: days,
          bookings: bookings,
          bookedMinutesByArea: minutes,
          period: period,
        );

    test('matches the booking-by-booking calculation', () {
      final viaRows = compute(bookings: [
        (playingAreaId: 'c1', startTime: DateTime(2026, 10, 5, 10), endTime: DateTime(2026, 10, 5, 12), status: 'confirmed'),
        (playingAreaId: 'c1', startTime: DateTime(2026, 10, 6, 18), endTime: DateTime(2026, 10, 6, 19), status: 'confirmed'),
        (playingAreaId: 'c2', startTime: DateTime(2026, 10, 6, 8), endTime: DateTime(2026, 10, 6, 9, 30), status: 'confirmed'),
        (playingAreaId: 'c2', startTime: DateTime(2026, 10, 6, 9), endTime: DateTime(2026, 10, 6, 11), status: 'cancelled'),
      ]);
      final viaMinutes = compute(bookings: const [], minutes: {'c1': 180, 'c2': 90});
      expect(viaMinutes.overallPercent, viaRows.overallPercent);
      expect(
        viaMinutes.bySport.expand((s) => s.courts).map((c) => '${c.playingAreaId}:${c.utilizationPercent}').toList(),
        viaRows.bySport.expand((s) => s.courts).map((c) => '${c.playingAreaId}:${c.utilizationPercent}').toList(),
      );
    });

    test('ignores the booking list when minutes are given', () {
      final u = compute(
        bookings: [(playingAreaId: 'c1', startTime: DateTime(2026, 10, 5, 10), endTime: DateTime(2026, 10, 5, 12), status: 'confirmed')],
        minutes: const {},
      );
      expect(u.overallPercent, 0);
    });
  });
}
