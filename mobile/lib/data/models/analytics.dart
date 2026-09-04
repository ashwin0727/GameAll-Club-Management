/// Reports & Analytics — Flutter port (Phase 9).
///
/// Mirrors src/features/reports/types.ts 1:1. Every figure here is
/// server-computed (migrations 0056–0063) — these classes only describe the
/// SHAPE of what the RPCs return. Nothing in this file computes, sums or
/// derives a number; there is deliberately no convenience arithmetic getter.
///
/// Date ranges are never resolved on the client: [AnalyticsFilter] carries a
/// preset name (plus explicit CUSTOM dates), and resolve_finance_date_range
/// turns it into real timestamps in the FACILITY's timezone.
library;

export 'finance.dart' show RevenueTrendPoint, RevenueTrendGranularity;

/// Every preset resolve_finance_date_range understands (0056 added the last
/// two). The client only ever picks one of these, or CUSTOM + explicit dates.
enum AnalyticsPreset {
  today,
  yesterday,
  thisWeek,
  lastWeek,
  thisMonth,
  lastMonth,
  thisQuarter,
  thisYear,
  custom;

  String toJson() {
    switch (this) {
      case AnalyticsPreset.today:
        return 'TODAY';
      case AnalyticsPreset.yesterday:
        return 'YESTERDAY';
      case AnalyticsPreset.thisWeek:
        return 'THIS_WEEK';
      case AnalyticsPreset.lastWeek:
        return 'LAST_WEEK';
      case AnalyticsPreset.thisMonth:
        return 'THIS_MONTH';
      case AnalyticsPreset.lastMonth:
        return 'LAST_MONTH';
      case AnalyticsPreset.thisQuarter:
        return 'THIS_QUARTER';
      case AnalyticsPreset.thisYear:
        return 'THIS_YEAR';
      case AnalyticsPreset.custom:
        return 'CUSTOM';
    }
  }

  static AnalyticsPreset fromJson(String value) {
    switch (value) {
      case 'TODAY':
        return AnalyticsPreset.today;
      case 'YESTERDAY':
        return AnalyticsPreset.yesterday;
      case 'THIS_WEEK':
        return AnalyticsPreset.thisWeek;
      case 'LAST_WEEK':
        return AnalyticsPreset.lastWeek;
      case 'THIS_MONTH':
        return AnalyticsPreset.thisMonth;
      case 'LAST_MONTH':
        return AnalyticsPreset.lastMonth;
      case 'THIS_QUARTER':
        return AnalyticsPreset.thisQuarter;
      case 'THIS_YEAR':
        return AnalyticsPreset.thisYear;
      case 'CUSTOM':
        return AnalyticsPreset.custom;
      default:
        throw ArgumentError('Unknown AnalyticsPreset: $value');
    }
  }

  /// Display label — mirrors PRESET_LABELS in src/features/reports/types.ts.
  String get label {
    switch (this) {
      case AnalyticsPreset.today:
        return 'Today';
      case AnalyticsPreset.yesterday:
        return 'Yesterday';
      case AnalyticsPreset.thisWeek:
        return 'This Week';
      case AnalyticsPreset.lastWeek:
        return 'Last Week';
      case AnalyticsPreset.thisMonth:
        return 'This Month';
      case AnalyticsPreset.lastMonth:
        return 'Last Month';
      case AnalyticsPreset.thisQuarter:
        return 'This Quarter';
      case AnalyticsPreset.thisYear:
        return 'This Year';
      case AnalyticsPreset.custom:
        return 'Custom Range';
    }
  }
}

/// The presets the date picker offers. LAST_WEEK is a valid value (the
/// comparison-period helper produces it) but isn't offered directly.
const List<AnalyticsPreset> kAnalyticsPresets = [
  AnalyticsPreset.today,
  AnalyticsPreset.yesterday,
  AnalyticsPreset.thisWeek,
  AnalyticsPreset.thisMonth,
  AnalyticsPreset.lastMonth,
  AnalyticsPreset.thisQuarter,
  AnalyticsPreset.thisYear,
  AnalyticsPreset.custom,
];

/// The one filter shape every report RPC call is built from
/// (mirrors AnalyticsFilter in src/features/reports/types.ts). No facility
/// selector on mobile — the session tracks one facility.
class AnalyticsFilter {
  const AnalyticsFilter({
    required this.preset,
    this.startDate,
    this.endDate,
    this.facilitySportId,
    this.courtId,
  });

  final AnalyticsPreset preset;

  /// ISO yyyy-MM-dd — required, and only used, when preset is CUSTOM.
  final String? startDate;
  final String? endDate;
  final String? facilitySportId;
  final String? courtId;

  static const AnalyticsFilter initial = AnalyticsFilter(preset: AnalyticsPreset.thisMonth);

  /// A half-picked CUSTOM range can't be sent — the server would reject it.
  bool get isComplete =>
      preset != AnalyticsPreset.custom || (startDate != null && endDate != null);

  bool get isScoped => facilitySportId != null || courtId != null;

  AnalyticsFilter copyWith({
    AnalyticsPreset? preset,
    String? startDate,
    String? endDate,
    Object? facilitySportId = _sentinel,
    Object? courtId = _sentinel,
  }) {
    return AnalyticsFilter(
      preset: preset ?? this.preset,
      startDate: preset == AnalyticsPreset.custom ? (startDate ?? this.startDate) : null,
      endDate: preset == AnalyticsPreset.custom ? (endDate ?? this.endDate) : null,
      facilitySportId: identical(facilitySportId, _sentinel)
          ? this.facilitySportId
          : facilitySportId as String?,
      courtId: identical(courtId, _sentinel) ? this.courtId : courtId as String?,
    );
  }

  static const Object _sentinel = Object();

  @override
  bool operator ==(Object other) =>
      other is AnalyticsFilter &&
      other.preset == preset &&
      other.startDate == startDate &&
      other.endDate == endDate &&
      other.facilitySportId == facilitySportId &&
      other.courtId == courtId;

  @override
  int get hashCode => Object.hash(preset, startDate, endDate, facilitySportId, courtId);
}

int _int(dynamic v) => (v as num).toInt();
double _double(dynamic v) => (v as num).toDouble();

// ─── Phase 9.2: Overview ────────────────────────────────────────────────

class AnalyticsOverview {
  const AnalyticsOverview({
    required this.grossRevenueMinor,
    required this.bookingRevenueMinor,
    required this.membershipRevenueMinor,
    required this.expensesMinor,
    required this.netRevenueMinor,
    required this.outstandingMinor,
    required this.totalBookings,
    required this.completedBookings,
    required this.cancelledBookings,
    required this.overallUtilizationPct,
  });

  final int grossRevenueMinor;
  final int bookingRevenueMinor;
  final int membershipRevenueMinor;
  final int expensesMinor;
  final int netRevenueMinor;
  final int outstandingMinor;
  final int totalBookings;
  final int completedBookings;
  final int cancelledBookings;
  final double overallUtilizationPct;

  factory AnalyticsOverview.fromJson(Map<String, dynamic> json) => AnalyticsOverview(
        grossRevenueMinor: _int(json['gross_revenue_minor']),
        bookingRevenueMinor: _int(json['booking_revenue_minor']),
        membershipRevenueMinor: _int(json['membership_revenue_minor']),
        expensesMinor: _int(json['expenses_minor']),
        netRevenueMinor: _int(json['net_revenue_minor']),
        outstandingMinor: _int(json['outstanding_minor']),
        totalBookings: _int(json['total_bookings']),
        completedBookings: _int(json['completed_bookings']),
        cancelledBookings: _int(json['cancelled_bookings']),
        overallUtilizationPct: _double(json['overall_utilization_pct']),
      );
}

// ─── Phase 9.3: Bookings ────────────────────────────────────────────────

class BookingAnalytics {
  const BookingAnalytics({
    required this.total,
    required this.completed,
    required this.confirmed,
    required this.pending,
    required this.cancelled,
    required this.guestCount,
    required this.memberCount,
    required this.avgGuestBookingValueMinor,
  });

  final int total;
  final int completed;
  final int confirmed;
  final int pending;
  final int cancelled;
  final int guestCount;
  final int memberCount;
  final int avgGuestBookingValueMinor;

  factory BookingAnalytics.fromJson(Map<String, dynamic> json) => BookingAnalytics(
        total: _int(json['total']),
        completed: _int(json['completed']),
        confirmed: _int(json['confirmed']),
        pending: _int(json['pending']),
        cancelled: _int(json['cancelled']),
        guestCount: _int(json['guest_count']),
        memberCount: _int(json['member_count']),
        avgGuestBookingValueMinor: _int(json['avg_guest_booking_value_minor']),
      );
}

class BookingTrendPoint {
  const BookingTrendPoint({
    required this.date,
    required this.total,
    required this.completed,
    required this.cancelled,
  });

  final String date;
  final int total;
  final int completed;
  final int cancelled;

  factory BookingTrendPoint.fromJson(Map<String, dynamic> json) => BookingTrendPoint(
        date: json['bucket_date'] as String,
        total: _int(json['total']),
        completed: _int(json['completed']),
        cancelled: _int(json['cancelled']),
      );
}

class BookingsBySportRow {
  const BookingsBySportRow({
    required this.facilitySportId,
    required this.sportName,
    required this.bookingCount,
  });

  final String facilitySportId;
  final String sportName;
  final int bookingCount;

  factory BookingsBySportRow.fromJson(Map<String, dynamic> json) => BookingsBySportRow(
        facilitySportId: json['facility_sport_id'] as String,
        sportName: json['sport_name'] as String,
        bookingCount: _int(json['booking_count']),
      );
}

class BookingSourceRow {
  const BookingSourceRow({required this.source, required this.bookingCount});

  /// GUEST | MEMBER
  final String source;
  final int bookingCount;

  factory BookingSourceRow.fromJson(Map<String, dynamic> json) => BookingSourceRow(
        source: json['source'] as String,
        bookingCount: _int(json['booking_count']),
      );
}

// ─── Phase 9.4: Court Utilization ───────────────────────────────────────

class OverallUtilization {
  const OverallUtilization({
    required this.openMinutes,
    required this.bookedMinutes,
    required this.utilizationPct,
  });

  final int openMinutes;
  final int bookedMinutes;
  final double utilizationPct;

  factory OverallUtilization.fromJson(Map<String, dynamic> json) => OverallUtilization(
        openMinutes: _int(json['open_minutes']),
        bookedMinutes: _int(json['booked_minutes']),
        utilizationPct: _double(json['utilization_pct']),
      );
}

class CourtUtilizationRow {
  const CourtUtilizationRow({
    required this.courtId,
    required this.courtName,
    required this.facilitySportId,
    required this.sportName,
    required this.openMinutes,
    required this.bookedMinutes,
    required this.utilizationPct,
  });

  final String courtId;
  final String courtName;
  final String facilitySportId;
  final String sportName;
  final int openMinutes;
  final int bookedMinutes;
  final double utilizationPct;

  factory CourtUtilizationRow.fromJson(Map<String, dynamic> json) => CourtUtilizationRow(
        courtId: json['court_id'] as String,
        courtName: json['court_name'] as String,
        facilitySportId: json['facility_sport_id'] as String,
        sportName: json['sport_name'] as String,
        openMinutes: _int(json['open_minutes']),
        bookedMinutes: _int(json['booked_minutes']),
        utilizationPct: _double(json['utilization_pct']),
      );
}

class SportUtilizationRow {
  const SportUtilizationRow({
    required this.facilitySportId,
    required this.sportName,
    required this.openMinutes,
    required this.bookedMinutes,
    required this.utilizationPct,
  });

  final String facilitySportId;
  final String sportName;
  final int openMinutes;
  final int bookedMinutes;
  final double utilizationPct;

  factory SportUtilizationRow.fromJson(Map<String, dynamic> json) => SportUtilizationRow(
        facilitySportId: json['facility_sport_id'] as String,
        sportName: json['sport_name'] as String,
        openMinutes: _int(json['open_minutes']),
        bookedMinutes: _int(json['booked_minutes']),
        utilizationPct: _double(json['utilization_pct']),
      );
}

class PeakHourRow {
  const PeakHourRow({
    required this.hour,
    required this.openMinutes,
    required this.bookedMinutes,
    required this.demandPct,
  });

  final int hour;
  final int openMinutes;
  final int bookedMinutes;
  final double demandPct;

  factory PeakHourRow.fromJson(Map<String, dynamic> json) => PeakHourRow(
        hour: _int(json['hour']),
        openMinutes: _int(json['open_minutes']),
        bookedMinutes: _int(json['booked_minutes']),
        demandPct: _double(json['demand_pct']),
      );
}

class HeatmapCell {
  const HeatmapCell({
    required this.dow,
    required this.hour,
    required this.openMinutes,
    required this.bookedMinutes,
    required this.demandPct,
  });

  final int dow;
  final int hour;
  final int openMinutes;
  final int bookedMinutes;
  final double demandPct;

  factory HeatmapCell.fromJson(Map<String, dynamic> json) => HeatmapCell(
        dow: _int(json['dow']),
        hour: _int(json['hour']),
        openMinutes: _int(json['open_minutes']),
        bookedMinutes: _int(json['booked_minutes']),
        demandPct: _double(json['demand_pct']),
      );
}

// ─── Phase 9.5: Revenue ─────────────────────────────────────────────────

class RevenueSummary {
  const RevenueSummary({
    required this.grossMinor,
    required this.refundsMinor,
    required this.expensesMinor,
    required this.netMinor,
    required this.outstandingMinor,
  });

  final int grossMinor;
  final int refundsMinor;
  final int expensesMinor;
  final int netMinor;
  final int outstandingMinor;

  factory RevenueSummary.fromJson(Map<String, dynamic> json) => RevenueSummary(
        grossMinor: _int(json['gross_revenue_minor']),
        refundsMinor: _int(json['refunds_minor']),
        expensesMinor: _int(json['expenses_minor'] ?? 0),
        netMinor: _int(json['net_revenue_minor']),
        outstandingMinor: _int(json['outstanding_minor'] ?? 0),
      );
}

class ReportRevenueBreakdown {
  const ReportRevenueBreakdown({
    required this.membershipMinor,
    required this.memberBookingMinor,
    required this.guestBookingMinor,
    required this.refundsMinor,
    required this.netMinor,
  });

  final int membershipMinor;
  final int memberBookingMinor;
  final int guestBookingMinor;
  final int refundsMinor;
  final int netMinor;

  factory ReportRevenueBreakdown.fromJson(Map<String, dynamic> json) => ReportRevenueBreakdown(
        membershipMinor: _int(json['membership_revenue_minor']),
        memberBookingMinor: _int(json['member_booking_revenue_minor']),
        guestBookingMinor: _int(json['guest_booking_revenue_minor']),
        refundsMinor: _int(json['refunds_minor']),
        netMinor: _int(json['net_revenue_minor']),
      );
}

class PaymentMethodSlice {
  const PaymentMethodSlice({required this.method, required this.amountMinor, required this.count});

  final String method;
  final int amountMinor;
  final int count;

  factory PaymentMethodSlice.fromJson(Map<String, dynamic> json) => PaymentMethodSlice(
        method: json['payment_method'] as String,
        amountMinor: _int(json['amount_minor']),
        count: _int(json['payment_count']),
      );
}

class RevenueBySportRow {
  const RevenueBySportRow({
    required this.facilitySportId,
    required this.sportName,
    required this.revenueMinor,
  });

  final String facilitySportId;
  final String sportName;
  final int revenueMinor;

  factory RevenueBySportRow.fromJson(Map<String, dynamic> json) => RevenueBySportRow(
        facilitySportId: json['facility_sport_id'] as String,
        sportName: json['sport_name'] as String,
        revenueMinor: _int(json['revenue_minor']),
      );
}

class RevenueByCourtRow {
  const RevenueByCourtRow({
    required this.courtId,
    required this.courtName,
    required this.facilitySportId,
    required this.sportName,
    required this.revenueMinor,
  });

  final String courtId;
  final String courtName;
  final String facilitySportId;
  final String sportName;
  final int revenueMinor;

  factory RevenueByCourtRow.fromJson(Map<String, dynamic> json) => RevenueByCourtRow(
        courtId: json['court_id'] as String,
        courtName: json['court_name'] as String,
        facilitySportId: json['facility_sport_id'] as String,
        sportName: json['sport_name'] as String,
        revenueMinor: _int(json['revenue_minor']),
      );
}

// ─── Phase 9.6: Memberships ─────────────────────────────────────────────

class MembershipAnalytics {
  const MembershipAnalytics({
    required this.activeMembers,
    required this.newMemberships,
    required this.expiringSoon,
    required this.membershipRevenueMinor,
    required this.paidCount,
    required this.partiallyPaidCount,
    required this.pendingCount,
    required this.outstandingMinor,
  });

  final int activeMembers;
  final int newMemberships;
  final int expiringSoon;
  final int membershipRevenueMinor;
  final int paidCount;
  final int partiallyPaidCount;
  final int pendingCount;
  final int outstandingMinor;

  factory MembershipAnalytics.fromJson(Map<String, dynamic> json) => MembershipAnalytics(
        activeMembers: _int(json['active_members']),
        newMemberships: _int(json['new_memberships']),
        expiringSoon: _int(json['expiring_soon']),
        membershipRevenueMinor: _int(json['membership_revenue_minor']),
        paidCount: _int(json['paid_count']),
        partiallyPaidCount: _int(json['partially_paid_count']),
        pendingCount: _int(json['pending_count']),
        outstandingMinor: _int(json['outstanding_minor']),
      );
}

class MembershipTypeRow {
  const MembershipTypeRow({
    required this.membershipType,
    required this.planName,
    required this.count,
    required this.revenueMinor,
  });

  final String membershipType;
  final String planName;
  final int count;
  final int revenueMinor;

  factory MembershipTypeRow.fromJson(Map<String, dynamic> json) => MembershipTypeRow(
        membershipType: json['membership_type'] as String,
        planName: json['plan_name'] as String,
        count: _int(json['count']),
        revenueMinor: _int(json['revenue_minor']),
      );
}

class MembershipSessionAnalytics {
  const MembershipSessionAnalytics({
    required this.sessionCount,
    required this.totalCapacity,
    required this.memberAllocations,
    required this.guestReleased,
    required this.guestBooked,
    required this.remainingReleased,
    required this.unusedCapacity,
  });

  final int sessionCount;
  final int totalCapacity;
  final int memberAllocations;
  final int guestReleased;
  final int guestBooked;
  final int remainingReleased;
  final int unusedCapacity;

  factory MembershipSessionAnalytics.fromJson(Map<String, dynamic> json) => MembershipSessionAnalytics(
        sessionCount: _int(json['session_count']),
        totalCapacity: _int(json['total_capacity']),
        memberAllocations: _int(json['member_allocations']),
        guestReleased: _int(json['guest_released']),
        guestBooked: _int(json['guest_booked']),
        remainingReleased: _int(json['remaining_released']),
        unusedCapacity: _int(json['unused_capacity']),
      );
}

class GuestReleaseAnalytics {
  const GuestReleaseAnalytics({
    required this.released,
    required this.booked,
    required this.remaining,
    required this.revenueMinor,
  });

  final int released;
  final int booked;
  final int remaining;
  final int revenueMinor;

  factory GuestReleaseAnalytics.fromJson(Map<String, dynamic> json) => GuestReleaseAnalytics(
        released: _int(json['released']),
        booked: _int(json['booked']),
        remaining: _int(json['remaining']),
        revenueMinor: _int(json['revenue_minor']),
      );
}

// ─── Phase 9.7: Guest Bookings ──────────────────────────────────────────

class GuestBookingAnalytics {
  const GuestBookingAnalytics({
    required this.total,
    required this.completed,
    required this.confirmed,
    required this.pending,
    required this.cancelled,
    required this.revenueMinor,
    required this.avgBookingValueMinor,
    required this.collectedMinor,
    required this.outstandingMinor,
    required this.collectionRatePct,
  });

  final int total;
  final int completed;
  final int confirmed;
  final int pending;
  final int cancelled;
  final int revenueMinor;
  final int avgBookingValueMinor;
  final int collectedMinor;
  final int outstandingMinor;
  final double collectionRatePct;

  factory GuestBookingAnalytics.fromJson(Map<String, dynamic> json) => GuestBookingAnalytics(
        total: _int(json['total']),
        completed: _int(json['completed']),
        confirmed: _int(json['confirmed']),
        pending: _int(json['pending']),
        cancelled: _int(json['cancelled']),
        revenueMinor: _int(json['revenue_minor']),
        avgBookingValueMinor: _int(json['avg_booking_value_minor']),
        collectedMinor: _int(json['collected_minor']),
        outstandingMinor: _int(json['outstanding_minor']),
        collectionRatePct: _double(json['collection_rate_pct']),
      );
}

class GuestBookingsBySportRow {
  const GuestBookingsBySportRow({
    required this.facilitySportId,
    required this.sportName,
    required this.bookingCount,
    required this.revenueMinor,
  });

  final String facilitySportId;
  final String sportName;
  final int bookingCount;
  final int revenueMinor;

  factory GuestBookingsBySportRow.fromJson(Map<String, dynamic> json) => GuestBookingsBySportRow(
        facilitySportId: json['facility_sport_id'] as String,
        sportName: json['sport_name'] as String,
        bookingCount: _int(json['booking_count']),
        revenueMinor: _int(json['revenue_minor']),
      );
}

class GuestBookingsByCourtRow {
  const GuestBookingsByCourtRow({
    required this.courtId,
    required this.courtName,
    required this.sportName,
    required this.bookingCount,
    required this.revenueMinor,
  });

  final String courtId;
  final String courtName;
  final String sportName;
  final int bookingCount;
  final int revenueMinor;

  factory GuestBookingsByCourtRow.fromJson(Map<String, dynamic> json) => GuestBookingsByCourtRow(
        courtId: json['court_id'] as String,
        courtName: json['court_name'] as String,
        sportName: json['sport_name'] as String,
        bookingCount: _int(json['booking_count']),
        revenueMinor: _int(json['revenue_minor']),
      );
}

class GuestPeakHourRow {
  const GuestPeakHourRow({required this.hour, required this.bookingCount});

  final int hour;
  final int bookingCount;

  factory GuestPeakHourRow.fromJson(Map<String, dynamic> json) => GuestPeakHourRow(
        hour: _int(json['hour']),
        bookingCount: _int(json['booking_count']),
      );
}
