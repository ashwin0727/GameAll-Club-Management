import type { ReportsService } from "@/services/reports/reports.service";
import { setReportsService } from "@/services/reports";
import type { RevenueTrendPoint } from "@/features/finance/types";
import type {
  BookingAnalytics,
  BookingTrendPoint,
  BookingsBySportRow,
  BookingSourceRow,
  OverallUtilization,
  CourtUtilizationRow,
  SportUtilizationRow,
  PeakHourRow,
  HeatmapCell,
  RevenueSummary,
  RevenueBreakdown,
  PaymentMethodSlice,
  RevenueBySportRow,
  RevenueByCourtRow,
  AnalyticsOverview,
  MembershipAnalytics,
  MembershipTypeRow,
  MembershipSessionAnalytics,
  GuestReleaseAnalytics,
  GuestBookingAnalytics,
  GuestBookingsBySportRow,
  GuestBookingsByCourtRow,
  GuestPeakHourRow,
} from "@/features/reports/types";

const EMPTY_ANALYTICS: BookingAnalytics = {
  total: 0,
  completed: 0,
  confirmed: 0,
  pending: 0,
  cancelled: 0,
  guestCount: 0,
  memberCount: 0,
  avgGuestBookingValueMinor: 0,
};

/** In-memory ReportsService. Set the public fields to the fixture a test needs. */
export class FakeReportsService implements ReportsService {
  bookingAnalytics: BookingAnalytics = { ...EMPTY_ANALYTICS };
  bookingTrend: BookingTrendPoint[] = [];
  bookingsBySport: BookingsBySportRow[] = [];
  bookingSourceSplit: BookingSourceRow[] = [];
  overallUtilization: OverallUtilization = { openMinutes: 0, bookedMinutes: 0, utilizationPct: 0 };
  courtUtilization: CourtUtilizationRow[] = [];
  sportUtilization: SportUtilizationRow[] = [];
  peakHours: PeakHourRow[] = [];
  demandHeatmap: HeatmapCell[] = [];
  revenueSummary: RevenueSummary = {
    grossMinor: 0,
    refundsMinor: 0,
    expensesMinor: 0,
    netMinor: 0,
    outstandingMinor: 0,
  };
  revenueTrend: RevenueTrendPoint[] = [];
  revenueBreakdown: RevenueBreakdown = {
    membershipMinor: 0,
    memberBookingMinor: 0,
    guestBookingMinor: 0,
    refundsMinor: 0,
    netMinor: 0,
  };
  paymentMethods: PaymentMethodSlice[] = [];
  revenueBySport: RevenueBySportRow[] = [];
  revenueByCourt: RevenueByCourtRow[] = [];
  analyticsOverview: AnalyticsOverview = {
    grossRevenueMinor: 0,
    bookingRevenueMinor: 0,
    membershipRevenueMinor: 0,
    expensesMinor: 0,
    netRevenueMinor: 0,
    outstandingMinor: 0,
    totalBookings: 0,
    completedBookings: 0,
    cancelledBookings: 0,
    overallUtilizationPct: 0,
  };
  membershipAnalytics: MembershipAnalytics = {
    activeMembers: 0,
    newMemberships: 0,
    expiringSoon: 0,
    membershipRevenueMinor: 0,
    paidCount: 0,
    partiallyPaidCount: 0,
    pendingCount: 0,
    outstandingMinor: 0,
  };
  membershipsByType: MembershipTypeRow[] = [];
  membershipSessionAnalytics: MembershipSessionAnalytics = {
    sessionCount: 0,
    totalCapacity: 0,
    memberAllocations: 0,
    guestReleased: 0,
    guestBooked: 0,
    remainingReleased: 0,
    unusedCapacity: 0,
  };
  guestReleaseAnalytics: GuestReleaseAnalytics = { released: 0, booked: 0, remaining: 0, revenueMinor: 0 };
  guestBookingAnalytics: GuestBookingAnalytics = {
    total: 0,
    completed: 0,
    confirmed: 0,
    pending: 0,
    cancelled: 0,
    revenueMinor: 0,
    avgBookingValueMinor: 0,
    collectedMinor: 0,
    outstandingMinor: 0,
    collectionRatePct: 0,
  };
  guestBookingsBySport: GuestBookingsBySportRow[] = [];
  guestBookingsByCourt: GuestBookingsByCourtRow[] = [];
  guestPeakHours: GuestPeakHourRow[] = [];
  error: Error | null = null;

  async getBookingAnalytics(): Promise<BookingAnalytics> {
    if (this.error) throw this.error;
    return this.bookingAnalytics;
  }
  async getBookingTrend(): Promise<BookingTrendPoint[]> {
    if (this.error) throw this.error;
    return this.bookingTrend;
  }
  async getBookingsBySport(): Promise<BookingsBySportRow[]> {
    if (this.error) throw this.error;
    return this.bookingsBySport;
  }
  async getBookingSourceSplit(): Promise<BookingSourceRow[]> {
    if (this.error) throw this.error;
    return this.bookingSourceSplit;
  }
  async getOverallUtilization(): Promise<OverallUtilization> {
    if (this.error) throw this.error;
    return this.overallUtilization;
  }
  async getCourtUtilization(): Promise<CourtUtilizationRow[]> {
    if (this.error) throw this.error;
    return this.courtUtilization;
  }
  async getSportUtilization(): Promise<SportUtilizationRow[]> {
    if (this.error) throw this.error;
    return this.sportUtilization;
  }
  async getPeakHours(): Promise<PeakHourRow[]> {
    if (this.error) throw this.error;
    return this.peakHours;
  }
  async getDemandHeatmap(): Promise<HeatmapCell[]> {
    if (this.error) throw this.error;
    return this.demandHeatmap;
  }
  async getRevenueSummary(): Promise<RevenueSummary> {
    if (this.error) throw this.error;
    return this.revenueSummary;
  }
  async getRevenueTrend(): Promise<RevenueTrendPoint[]> {
    if (this.error) throw this.error;
    return this.revenueTrend;
  }
  async getRevenueBreakdown(): Promise<RevenueBreakdown> {
    if (this.error) throw this.error;
    return this.revenueBreakdown;
  }
  async getPaymentMethodBreakdown(): Promise<PaymentMethodSlice[]> {
    if (this.error) throw this.error;
    return this.paymentMethods;
  }
  async getRevenueBySport(): Promise<RevenueBySportRow[]> {
    if (this.error) throw this.error;
    return this.revenueBySport;
  }
  async getRevenueByCourt(): Promise<RevenueByCourtRow[]> {
    if (this.error) throw this.error;
    return this.revenueByCourt;
  }
  async getAnalyticsOverview(): Promise<AnalyticsOverview> {
    if (this.error) throw this.error;
    return this.analyticsOverview;
  }
  async getMembershipAnalytics(): Promise<MembershipAnalytics> {
    if (this.error) throw this.error;
    return this.membershipAnalytics;
  }
  async getMembershipsByType(): Promise<MembershipTypeRow[]> {
    if (this.error) throw this.error;
    return this.membershipsByType;
  }
  async getMembershipSessionAnalytics(): Promise<MembershipSessionAnalytics> {
    if (this.error) throw this.error;
    return this.membershipSessionAnalytics;
  }
  async getGuestReleaseAnalytics(): Promise<GuestReleaseAnalytics> {
    if (this.error) throw this.error;
    return this.guestReleaseAnalytics;
  }
  async getGuestBookingAnalytics(): Promise<GuestBookingAnalytics> {
    if (this.error) throw this.error;
    return this.guestBookingAnalytics;
  }
  async getGuestBookingsBySport(): Promise<GuestBookingsBySportRow[]> {
    if (this.error) throw this.error;
    return this.guestBookingsBySport;
  }
  async getGuestBookingsByCourt(): Promise<GuestBookingsByCourtRow[]> {
    if (this.error) throw this.error;
    return this.guestBookingsByCourt;
  }
  async getGuestPeakHours(): Promise<GuestPeakHourRow[]> {
    if (this.error) throw this.error;
    return this.guestPeakHours;
  }
}

export function installFakeReportsService(): FakeReportsService {
  const service = new FakeReportsService();
  setReportsService(service);
  return service;
}
