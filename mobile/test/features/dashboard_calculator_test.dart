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

  group('buildTodaysSchedule', () {
    test('marks a slot BOOKED only when an active booking overlaps it', () {
      final now = DateTime(2026, 8, 24, 10); // a Monday
      final schedule = DashboardCalculator.buildTodaysSchedule(
        playingAreas: [(id: 'court-1', name: 'Court 1', facilitySportId: 'fs-1')],
        facilitySports: [(id: 'fs-1', sportId: 'sport-1')],
        sports: [(id: 'sport-1', name: 'Badminton')],
        facilityOperatingDays: [_openDay(1, start: '06:00', end: '12:00')],
        bookings: [
          (
            playingAreaId: 'court-1',
            startTime: DateTime(2026, 8, 24, 6),
            endTime: DateTime(2026, 8, 24, 7),
            status: 'confirmed',
          ),
        ],
        now: now,
      );
      expect(schedule, hasLength(1));
      expect(schedule.first.status, ScheduleSlotStatus.booked);
    });

    test('is empty when the facility is closed today', () {
      final schedule = DashboardCalculator.buildTodaysSchedule(
        playingAreas: [(id: 'court-1', name: 'Court 1', facilitySportId: 'fs-1')],
        facilitySports: [(id: 'fs-1', sportId: 'sport-1')],
        sports: [(id: 'sport-1', name: 'Badminton')],
        facilityOperatingDays: [_closedDay(1)],
        bookings: const [],
        now: DateTime(2026, 8, 24, 10),
      );
      expect(schedule, isEmpty);
    });
  });
}