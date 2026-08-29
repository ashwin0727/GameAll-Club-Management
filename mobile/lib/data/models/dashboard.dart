/// Mirrors src/features/dashboard/types.ts + summary.ts — same shape, same
/// "unavailable, not fabricated" states for modules with no backing table.
enum DateRangePreset { today, yesterday, thisWeek, thisMonth }

class DateRange {
  const DateRange({required this.from, required this.to});
  final DateTime from;
  final DateTime to;
}

class ResolvedPeriod {
  const ResolvedPeriod({required this.current, this.previous});
  final DateRange current;
  final DateRange? previous;
}

class KpiValue {
  const KpiValue({required this.value, this.previousValue, this.changePercent});
  final num value;
  final num? previousValue;
  final double? changePercent;
}

class CourtUtilization {
  const CourtUtilization({
    required this.playingAreaId,
    required this.playingAreaName,
    required this.utilizationPercent,
  });
  final String playingAreaId;
  final String playingAreaName;
  final int utilizationPercent;
}

class SportUtilization {
  const SportUtilization({
    required this.facilitySportId,
    required this.sportName,
    required this.utilizationPercent,
    required this.courts,
  });
  final String facilitySportId;
  final String sportName;
  final int utilizationPercent;
  final List<CourtUtilization> courts;
}

class UtilizationSummary {
  const UtilizationSummary({required this.overallPercent, required this.bySport});
  final int overallPercent;
  final List<SportUtilization> bySport;
}

/// The only block types with real backing data: a regular member booking, a
/// regular guest booking, or actual usage of a membership-protected session.
/// There is no "blocked"/"maintenance" table yet, so those are never fabricated.
enum ScheduleBlockType { member, guest, session }

class ScheduleBlock {
  const ScheduleBlock({
    required this.id,
    required this.label,
    required this.startMinute,
    required this.endMinute,
    required this.timeLabel,
    required this.type,
    required this.lane,
  });

  final String id;
  final String label;

  /// Minutes from midnight (local), clamped to the timeline's window.
  final int startMinute;
  final int endMinute;

  /// e.g. "5:00 – 6:00 PM".
  final String timeLabel;
  final ScheduleBlockType type;

  /// Lane index for side-by-side stacking of overlapping blocks in one court.
  final int lane;
}

class ScheduleCourtRow {
  const ScheduleCourtRow({
    required this.courtId,
    required this.courtName,
    required this.sportName,
    required this.laneCount,
    required this.blocks,
  });

  final String courtId;
  final String courtName;
  final String sportName;
  final int laneCount;
  final List<ScheduleBlock> blocks;
}

class ScheduleTimeline {
  const ScheduleTimeline({
    required this.startHour,
    required this.endHour,
    required this.courts,
  });

  /// Hour-of-day axis bounds from today's real operating slots. Both 0 when closed.
  final int startHour;
  final int endHour;
  final List<ScheduleCourtRow> courts;
}

class MembershipSummary {
  const MembershipSummary({
    required this.active,
    required this.expiringSoon,
    required this.expired,
    required this.newThisMonth,
  });
  final int active;
  final int expiringSoon;
  final int expired;
  final int newThisMonth;
}

class PaymentSummary {
  const PaymentSummary({
    required this.collectedInr,
    required this.pendingInr,
    required this.refundsInr,
  });
  final int collectedInr;
  final int pendingInr;
  final int refundsInr;
}

class AttentionItem {
  const AttentionItem({required this.id, required this.message});
  final String id;
  final String message;
}

class AvailableSportOption {
  const AvailableSportOption({
    required this.facilitySportId,
    required this.sportName,
    required this.sportIcon,
  });
  final String facilitySportId;
  final String sportName;
  final String sportIcon;
}

class RevenueTrendPoint {
  const RevenueTrendPoint({required this.date, required this.amountInr});

  /// Calendar date, "YYYY-MM-DD".
  final String date;

  /// Collected (paid) revenue for that day, in whole rupees.
  final int amountInr;
}

enum RevenueBreakdownKey { bookings, memberships, coaching, other }

class RevenueBreakdownSegment {
  const RevenueBreakdownSegment({
    required this.key,
    required this.label,
    required this.amountInr,
    required this.count,
    required this.unavailable,
  });

  final RevenueBreakdownKey key;
  final String label;

  /// Paid revenue for this category in the selected month, whole rupees.
  final int amountInr;

  /// Number of paid transactions; null for categories with no backing data yet.
  final int? count;

  /// True when the category has no data source yet — shown at ₹0, not fabricated.
  final bool unavailable;
}

class RevenueOverview {
  const RevenueOverview({
    required this.monthLabel,
    required this.totalInr,
    required this.changePercent,
    required this.points,
    required this.breakdown,
  });

  /// Human label for the selected month, e.g. "May 2026".
  final String monthLabel;

  /// Total paid revenue for the month, whole rupees.
  final int totalInr;

  /// Percent change vs the previous month; null when the previous month had no revenue.
  final double? changePercent;

  /// One point per day of the month (zero-filled), always non-empty so the chart always renders.
  final List<RevenueTrendPoint> points;

  /// Where the month's revenue came from — bookings / memberships / (future) coaching / other.
  final List<RevenueBreakdownSegment> breakdown;
}

class DashboardSummary {
  const DashboardSummary({
    required this.facilityName,
    required this.facilityCity,
    required this.sports,
    required this.selectedFacilitySportId,
    required this.kpis,
    required this.utilization,
    required this.scheduleTimeline,
    required this.revenueOverview,
    required this.memberships,
    required this.payments,
    required this.attentionItems,
  });

  final String facilityName;
  final String facilityCity;
  final List<AvailableSportOption> sports;
  final String? selectedFacilitySportId;
  final DashboardKpis kpis;
  final UtilizationSummary utilization;
  final ScheduleTimeline scheduleTimeline;
  final RevenueOverview revenueOverview;
  final MembershipSummary memberships;
  final PaymentSummary payments;
  final List<AttentionItem> attentionItems;
}

class DashboardKpis {
  const DashboardKpis({
    required this.revenueInr,
    required this.activeMemberships,
    required this.guestBookings,
    required this.utilizationPercent,
  });

  /// Paid revenue in the selected period; scoped to the selected sport.
  final KpiValue revenueInr;

  /// Memberships active as of now; scoped to the selected sport via batch enrolment.
  final KpiValue activeMemberships;

  /// Guest bookings booked and paid in the selected period; scoped to the sport by court.
  final KpiValue guestBookings;

  final KpiValue utilizationPercent;
}