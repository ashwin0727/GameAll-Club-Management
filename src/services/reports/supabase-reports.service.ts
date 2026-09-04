"use client";

import type { SupabaseClient } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";
import type { Database } from "@/types/database.types";
import type { ReportsService } from "@/services/reports/reports.service";
import { ServiceError } from "@/services/shared/service-error";
import { dateRangeArgs, scopeArgs } from "@/features/reports/report-filter";
import type { RevenueTrendPoint } from "@/features/finance/types";
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
  RevenueSummary,
  RevenueBreakdown,
  PaymentMethodSlice,
  RevenueBySportRow,
  RevenueByCourtRow,
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

  // ─── Phase 4: Revenue — trend / breakdown / method / totals are the
  //     existing Finance RPCs, called with AnalyticsFilter-derived args so
  //     the numbers match Finance exactly (spec §34). Facility + date only.

  async getRevenueSummary(filter: AnalyticsFilter): Promise<RevenueSummary> {
    const { data, error } = await this.supabase.rpc("get_finance_summary", {
      p_facility_id: filter.facilityId,
      ...dateRangeArgs(filter),
    });
    if (error || !data?.[0]) throw this.mapError(error);
    const r = data[0];
    return {
      grossMinor: r.gross_revenue_minor,
      refundsMinor: r.refunds_minor,
      expensesMinor: r.expenses_minor ?? 0,
      netMinor: r.net_revenue_minor,
      outstandingMinor: r.outstanding_minor ?? 0,
    };
  }

  async getRevenueTrend(
    filter: AnalyticsFilter,
    granularity: AnalyticsGranularity,
  ): Promise<RevenueTrendPoint[]> {
    const { data, error } = await this.supabase.rpc("get_revenue_trend", {
      p_facility_id: filter.facilityId,
      ...dateRangeArgs(filter),
      p_granularity: granularity,
    });
    if (error) throw this.mapError(error);
    return (data ?? []).map((r) => ({
      date: r.bucket_date,
      grossMinor: r.gross_minor,
      refundMinor: r.refund_minor,
      netMinor: r.net_minor,
    }));
  }

  async getRevenueBreakdown(filter: AnalyticsFilter): Promise<RevenueBreakdown> {
    const { data, error } = await this.supabase.rpc("get_revenue_breakdown", {
      p_facility_id: filter.facilityId,
      ...dateRangeArgs(filter),
    });
    if (error || !data?.[0]) throw this.mapError(error);
    const r = data[0];
    return {
      membershipMinor: r.membership_revenue_minor,
      memberBookingMinor: r.member_booking_revenue_minor,
      guestBookingMinor: r.guest_booking_revenue_minor,
      refundsMinor: r.refunds_minor,
      netMinor: r.net_revenue_minor,
    };
  }

  async getPaymentMethodBreakdown(filter: AnalyticsFilter): Promise<PaymentMethodSlice[]> {
    const { data, error } = await this.supabase.rpc("get_payment_method_breakdown", {
      p_facility_id: filter.facilityId,
      ...dateRangeArgs(filter),
    });
    if (error) throw this.mapError(error);
    return (data ?? []).map((r) => ({
      method: r.payment_method,
      amountMinor: r.amount_minor,
      count: r.payment_count,
    }));
  }

  async getRevenueBySport(filter: AnalyticsFilter): Promise<RevenueBySportRow[]> {
    const { data, error } = await this.supabase.rpc("get_revenue_by_sport", this.baseArgs(filter));
    if (error) throw this.mapError(error);
    return (data ?? []).map((r) => ({
      facilitySportId: r.facility_sport_id,
      sportName: r.sport_name,
      revenueMinor: r.revenue_minor,
    }));
  }

  async getRevenueByCourt(filter: AnalyticsFilter): Promise<RevenueByCourtRow[]> {
    const { data, error } = await this.supabase.rpc("get_revenue_by_court", this.baseArgs(filter));
    if (error) throw this.mapError(error);
    return (data ?? []).map((r) => ({
      courtId: r.court_id,
      courtName: r.court_name,
      facilitySportId: r.facility_sport_id,
      sportName: r.sport_name,
      revenueMinor: r.revenue_minor,
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
