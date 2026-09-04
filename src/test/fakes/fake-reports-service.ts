import type { ReportsService } from "@/services/reports/reports.service";
import { setReportsService } from "@/services/reports";
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
}

export function installFakeReportsService(): FakeReportsService {
  const service = new FakeReportsService();
  setReportsService(service);
  return service;
}
