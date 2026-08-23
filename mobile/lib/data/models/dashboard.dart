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

enum ScheduleSlotStatus { available, booked }

class ScheduleEntry {
  const ScheduleEntry({
    required this.time,
    required this.sportName,
    required this.playingAreaName,
    required this.status,
  });
  final String time;
  final String sportName;
  final String playingAreaName;
  final ScheduleSlotStatus status;
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

class DashboardSummary {
  const DashboardSummary({
    required this.facilityName,
    required this.facilityCity,
    required this.sports,
    required this.selectedFacilitySportId,
    required this.kpis,
    required this.utilization,
    required this.schedule,
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
  final List<ScheduleEntry> schedule;
  final MembershipSummary memberships;
  final PaymentSummary payments;
  final List<AttentionItem> attentionItems;
}

class DashboardKpis {
  const DashboardKpis({
    required this.revenueInr,
    required this.bookings,
    required this.utilizationPercent,
    required this.activeMembers,
  });
  final KpiValue revenueInr;
  final KpiValue bookings;
  final KpiValue utilizationPercent;
  final KpiValue activeMembers;
}