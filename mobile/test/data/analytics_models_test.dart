import 'package:flutter_test/flutter_test.dart';
import 'package:gameall_club_mobile/data/models/analytics.dart';
import 'package:gameall_club_mobile/features/reports/analytics_filter.dart';

/// Reports & Analytics — Phase 9.1. Real `fromJson` calls with the exact
/// snake_case keys the RPCs return, so a field rename on either side breaks
/// a test. Mirrors the model-mapping half of
/// src/services/reports/supabase-reports.service.test.ts.
void main() {
  group('AnalyticsPreset', () {
    test('round-trips every value incl. the two 0056 presets', () {
      for (final p in AnalyticsPreset.values) {
        expect(AnalyticsPreset.fromJson(p.toJson()), p);
      }
      expect(AnalyticsPreset.thisQuarter.toJson(), 'THIS_QUARTER');
      expect(AnalyticsPreset.thisYear.toJson(), 'THIS_YEAR');
    });
  });

  group('AnalyticsFilter', () {
    test('CUSTOM without both dates is not complete', () {
      expect(const AnalyticsFilter(preset: AnalyticsPreset.custom).isComplete, isFalse);
      expect(
        const AnalyticsFilter(preset: AnalyticsPreset.custom, startDate: '2026-09-01', endDate: '2026-09-15')
            .isComplete,
        isTrue,
      );
      expect(const AnalyticsFilter(preset: AnalyticsPreset.thisMonth).isComplete, isTrue);
    });

    test('changing away from CUSTOM drops the explicit dates', () {
      const custom = AnalyticsFilter(
        preset: AnalyticsPreset.custom,
        startDate: '2026-09-01',
        endDate: '2026-09-15',
      );
      final next = custom.copyWith(preset: AnalyticsPreset.thisWeek);
      expect(next.startDate, isNull);
      expect(next.endDate, isNull);
    });

    test('copyWith can clear sport/court to null via an explicit null', () {
      const scoped = AnalyticsFilter(preset: AnalyticsPreset.thisMonth, facilitySportId: 'fs-1', courtId: 'c-1');
      expect(scoped.copyWith(facilitySportId: null).facilitySportId, isNull);
      expect(scoped.copyWith().facilitySportId, 'fs-1'); // untouched when omitted
    });
  });

  test('AnalyticsOverview.fromJson maps every field', () {
    final o = AnalyticsOverview.fromJson({
      'gross_revenue_minor': 12000000,
      'booking_revenue_minor': 7000000,
      'membership_revenue_minor': 5000000,
      'expenses_minor': 3500000,
      'net_revenue_minor': 8500000,
      'outstanding_minor': 1850000,
      'total_bookings': 205,
      'completed_bookings': 120,
      'cancelled_bookings': 20,
      'overall_utilization_pct': 68.0,
    });
    expect(o.grossRevenueMinor, 12000000);
    expect(o.totalBookings, 205);
    expect(o.overallUtilizationPct, 68.0);
  });

  test('BookingAnalytics + BookingTrendPoint + BookingsBySportRow + BookingSourceRow', () {
    final a = BookingAnalytics.fromJson({
      'total': 205,
      'completed': 120,
      'confirmed': 60,
      'pending': 5,
      'cancelled': 20,
      'guest_count': 130,
      'member_count': 75,
      'avg_guest_booking_value_minor': 55000,
    });
    expect(a.guestCount, 130);
    expect(a.avgGuestBookingValueMinor, 55000);

    final t = BookingTrendPoint.fromJson({'bucket_date': '2026-09-01', 'total': 8, 'completed': 5, 'cancelled': 1});
    expect(t.date, '2026-09-01');
    expect(t.total, 8);

    final s = BookingsBySportRow.fromJson({'facility_sport_id': 'fs1', 'sport_name': 'Badminton', 'booking_count': 120});
    expect(s.sportName, 'Badminton');

    final src = BookingSourceRow.fromJson({'source': 'GUEST', 'booking_count': 130});
    expect(src.source, 'GUEST');
  });

  test('utilization models', () {
    final overall = OverallUtilization.fromJson({'open_minutes': 1000, 'booked_minutes': 680, 'utilization_pct': 68.0});
    expect(overall.utilizationPct, 68.0);

    final court = CourtUtilizationRow.fromJson({
      'court_id': 'c1',
      'court_name': 'Court 1',
      'facility_sport_id': 'fs1',
      'sport_name': 'Badminton',
      'open_minutes': 600,
      'booked_minutes': 420,
      'utilization_pct': 70.0,
    });
    expect(court.courtName, 'Court 1');
    expect(court.utilizationPct, 70.0);

    final peak = PeakHourRow.fromJson({'hour': 18, 'open_minutes': 300, 'booked_minutes': 270, 'demand_pct': 90.0});
    expect(peak.hour, 18);

    final cell = HeatmapCell.fromJson({'dow': 1, 'hour': 18, 'open_minutes': 60, 'booked_minutes': 54, 'demand_pct': 90.0});
    expect(cell.dow, 1);
    expect(cell.demandPct, 90.0);
  });

  test('revenue models — RevenueSummary defaults missing expenses/outstanding to 0', () {
    final s = RevenueSummary.fromJson({'gross_revenue_minor': 100, 'refunds_minor': 0, 'net_revenue_minor': 100});
    expect(s.expensesMinor, 0);
    expect(s.outstandingMinor, 0);

    final b = ReportRevenueBreakdown.fromJson({
      'membership_revenue_minor': 6000000,
      'member_booking_revenue_minor': 500000,
      'guest_booking_revenue_minor': 4500000,
      'refunds_minor': 0,
      'net_revenue_minor': 11000000,
    });
    expect(b.guestBookingMinor, 4500000);

    final m = PaymentMethodSlice.fromJson({'payment_method': 'UPI', 'amount_minor': 5000000, 'payment_count': 20});
    expect(m.method, 'UPI');

    final bySport = RevenueBySportRow.fromJson({'facility_sport_id': 'fs1', 'sport_name': 'Badminton', 'revenue_minor': 4500000});
    expect(bySport.revenueMinor, 4500000);
  });

  test('membership models', () {
    final a = MembershipAnalytics.fromJson({
      'active_members': 84,
      'new_memberships': 12,
      'expiring_soon': 5,
      'membership_revenue_minor': 6000000,
      'paid_count': 9,
      'partially_paid_count': 2,
      'pending_count': 1,
      'outstanding_minor': 1000000,
    });
    expect(a.activeMembers, 84);

    final t = MembershipTypeRow.fromJson({'membership_type': 'INDIVIDUAL', 'plan_name': 'Monthly', 'count': 8, 'revenue_minor': 4000000});
    expect(t.membershipType, 'INDIVIDUAL');

    final s = MembershipSessionAnalytics.fromJson({
      'session_count': 40,
      'total_capacity': 500,
      'member_allocations': 360,
      'guest_released': 100,
      'guest_booked': 75,
      'remaining_released': 25,
      'unused_capacity': 65,
    });
    expect(s.unusedCapacity, 65);

    final g = GuestReleaseAnalytics.fromJson({'released': 100, 'booked': 75, 'remaining': 25, 'revenue_minor': 3800000});
    expect(g.remaining, 25);
  });

  test('guest booking models', () {
    final a = GuestBookingAnalytics.fromJson({
      'total': 120,
      'completed': 90,
      'confirmed': 20,
      'pending': 3,
      'cancelled': 7,
      'revenue_minor': 4500000,
      'avg_booking_value_minor': 50000,
      'collected_minor': 4500000,
      'outstanding_minor': 500000,
      'collection_rate_pct': 90.0,
    });
    expect(a.collectionRatePct, 90.0);

    final s = GuestBookingsBySportRow.fromJson({'facility_sport_id': 'fs1', 'sport_name': 'Badminton', 'booking_count': 80, 'revenue_minor': 3000000});
    expect(s.bookingCount, 80);

    final c = GuestBookingsByCourtRow.fromJson({'court_id': 'c1', 'court_name': 'Court 1', 'sport_name': 'Badminton', 'booking_count': 50, 'revenue_minor': 2000000});
    expect(c.courtName, 'Court 1');

    final h = GuestPeakHourRow.fromJson({'hour': 18, 'booking_count': 30});
    expect(h.hour, 18);
  });

  group('analytics_filter helpers', () {
    test('analyticsFilterFromQuery decodes preset + scope, falls back on garbage', () {
      final f = analyticsFilterFromQuery({'preset': 'THIS_QUARTER', 'sport': 'fs-1'});
      expect(f.preset, AnalyticsPreset.thisQuarter);
      expect(f.facilitySportId, 'fs-1');
      expect(analyticsFilterFromQuery({'preset': 'NONSENSE'}).preset, AnalyticsPreset.thisMonth);
      expect(analyticsFilterFromQuery({'preset': 'CUSTOM', 'from': '2026-09-01'}).preset, AnalyticsPreset.thisMonth);
    });

    test('pickAnalyticsGranularity by span', () {
      expect(pickAnalyticsGranularity(const AnalyticsFilter(preset: AnalyticsPreset.thisMonth)),
          RevenueTrendGranularity.daily);
      expect(pickAnalyticsGranularity(const AnalyticsFilter(preset: AnalyticsPreset.thisQuarter)),
          RevenueTrendGranularity.weekly);
      expect(pickAnalyticsGranularity(const AnalyticsFilter(preset: AnalyticsPreset.thisYear)),
          RevenueTrendGranularity.monthly);
    });

    test('previousAnalyticsPeriod maps rolling presets and shifts CUSTOM', () {
      expect(previousAnalyticsPeriod(const AnalyticsFilter(preset: AnalyticsPreset.thisMonth))?.preset,
          AnalyticsPreset.lastMonth);
      expect(previousAnalyticsPeriod(const AnalyticsFilter(preset: AnalyticsPreset.thisYear)), isNull);
      final prev = previousAnalyticsPeriod(const AnalyticsFilter(
        preset: AnalyticsPreset.custom,
        startDate: '2026-09-10',
        endDate: '2026-09-19',
      ))!;
      expect(prev.startDate, '2026-08-31');
      expect(prev.endDate, '2026-09-09');
    });
  });
}
