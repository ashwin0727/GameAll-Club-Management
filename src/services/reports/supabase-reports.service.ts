"use client";

import type { SupabaseClient } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";
import type { Database } from "@/types/database.types";
import type { ReportsService } from "@/services/reports/reports.service";
import { ServiceError } from "@/services/shared/service-error";
import { dateRangeArgs, scopeArgs } from "@/features/reports/report-filter";
import type {
  AnalyticsFilter,
  AnalyticsGranularity,
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

export class SupabaseReportsService implements ReportsService {
  private readonly supabase: SupabaseClient<Database>;

  constructor(client?: SupabaseClient<Database>) {
    this.supabase = client ?? createClient();
  }

  private baseArgs(f: AnalyticsFilter) {
    return { p_facility_id: f.facilityId, ...dateRangeArgs(f), ...scopeArgs(f) };
  }

  async getBookingAnalytics(filter: AnalyticsFilter): Promise<BookingAnalytics> {
    const { data, error } = await this.supabase.rpc("get_booking_analytics", this.baseArgs(filter));
    if (error || !data?.[0]) throw this.mapError(error);
    const r = data[0];
    return {
      total: r.total,
      completed: r.completed,
      confirmed: r.confirmed,
      pending: r.pending,
      cancelled: r.cancelled,
      guestCount: r.guest_count,
      memberCount: r.member_count,
      avgGuestBookingValueMinor: r.avg_guest_booking_value_minor,
    };
  }

  async getBookingTrend(
    filter: AnalyticsFilter,
    granularity: AnalyticsGranularity,
  ): Promise<BookingTrendPoint[]> {
    const { data, error } = await this.supabase.rpc("get_booking_trend", {
      ...this.baseArgs(filter),
      p_granularity: granularity,
    });
    if (error) throw this.mapError(error);
    return (data ?? []).map((r) => ({
      date: r.bucket_date,
      total: r.total,
      completed: r.completed,
      cancelled: r.cancelled,
    }));
  }

  async getBookingsBySport(filter: AnalyticsFilter): Promise<BookingsBySportRow[]> {
    const { data, error } = await this.supabase.rpc("get_bookings_by_sport", this.baseArgs(filter));
    if (error) throw this.mapError(error);
    return (data ?? []).map((r) => ({
      facilitySportId: r.facility_sport_id,
      sportName: r.sport_name,
      bookingCount: r.booking_count,
    }));
  }

  async getBookingSourceSplit(filter: AnalyticsFilter): Promise<BookingSourceRow[]> {
    const { data, error } = await this.supabase.rpc("get_booking_source_split", this.baseArgs(filter));
    if (error) throw this.mapError(error);
    return (data ?? []).map((r) => ({
      source: r.source as "GUEST" | "MEMBER",
      bookingCount: r.booking_count,
    }));
  }

  async getOverallUtilization(filter: AnalyticsFilter): Promise<OverallUtilization> {
    const { data, error } = await this.supabase.rpc("get_overall_utilization", this.baseArgs(filter));
    if (error || !data?.[0]) throw this.mapError(error);
    const r = data[0];
    return {
      openMinutes: r.open_minutes,
      bookedMinutes: r.booked_minutes,
      utilizationPct: r.utilization_pct,
    };
  }

  async getCourtUtilization(filter: AnalyticsFilter): Promise<CourtUtilizationRow[]> {
    const { data, error } = await this.supabase.rpc("get_court_utilization", this.baseArgs(filter));
    if (error) throw this.mapError(error);
    return (data ?? []).map((r) => ({
      courtId: r.court_id,
      courtName: r.court_name,
      facilitySportId: r.facility_sport_id,
      sportName: r.sport_name,
      openMinutes: r.open_minutes,
      bookedMinutes: r.booked_minutes,
      utilizationPct: r.utilization_pct,
    }));
  }

  async getSportUtilization(filter: AnalyticsFilter): Promise<SportUtilizationRow[]> {
    const { data, error } = await this.supabase.rpc("get_sport_utilization", this.baseArgs(filter));
    if (error) throw this.mapError(error);
    return (data ?? []).map((r) => ({
      facilitySportId: r.facility_sport_id,
      sportName: r.sport_name,
      openMinutes: r.open_minutes,
      bookedMinutes: r.booked_minutes,
      utilizationPct: r.utilization_pct,
    }));
  }

  async getPeakHours(filter: AnalyticsFilter): Promise<PeakHourRow[]> {
    const { data, error } = await this.supabase.rpc("get_peak_hours", this.baseArgs(filter));
    if (error) throw this.mapError(error);
    return (data ?? []).map((r) => ({
      hour: r.hour,
      openMinutes: r.open_minutes,
      bookedMinutes: r.booked_minutes,
      demandPct: r.demand_pct,
    }));
  }

  async getDemandHeatmap(filter: AnalyticsFilter): Promise<HeatmapCell[]> {
    const { data, error } = await this.supabase.rpc("get_demand_heatmap", this.baseArgs(filter));
    if (error) throw this.mapError(error);
    return (data ?? []).map((r) => ({
      dow: r.dow,
      hour: r.hour,
      openMinutes: r.open_minutes,
      bookedMinutes: r.booked_minutes,
      demandPct: r.demand_pct,
    }));
  }

  private mapError(error: unknown): ServiceError {
    console.error("[reports-service] request failed", error);
    const message = (error as { message?: string } | null)?.message;
    if (message?.includes("Not authorized")) return new ServiceError("REPORTS_ACCESS_DENIED");
    if (message?.includes("valid start and end date")) return new ServiceError("INVALID_DATE_RANGE");
    return new ServiceError("REPORTS_DATA_ERROR");
  }
}
