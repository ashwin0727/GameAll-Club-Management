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
  AnalyticsOverview,
  MembershipAnalytics,
  MembershipTypeRow,
  MembershipSessionAnalytics,
  GuestReleaseAnalytics,
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

  async getAnalyticsOverview(filter: AnalyticsFilter): Promise<AnalyticsOverview> {
    const { data, error } = await this.supabase.rpc("get_analytics_overview", this.baseArgs(filter));
    if (error || !data?.[0]) throw this.mapError(error);
    const r = data[0];
    return {
      grossRevenueMinor: r.gross_revenue_minor,
      bookingRevenueMinor: r.booking_revenue_minor,
      membershipRevenueMinor: r.membership_revenue_minor,
      expensesMinor: r.expenses_minor,
      netRevenueMinor: r.net_revenue_minor,
      outstandingMinor: r.outstanding_minor,
      totalBookings: r.total_bookings,
      completedBookings: r.completed_bookings,
      cancelledBookings: r.cancelled_bookings,
      overallUtilizationPct: r.overall_utilization_pct,
    };
  }

  // ─── Phase 6: Memberships ──────────────────────────────────────────────

  async getMembershipAnalytics(filter: AnalyticsFilter): Promise<MembershipAnalytics> {
    const { data, error } = await this.supabase.rpc("get_membership_analytics", {
      p_facility_id: filter.facilityId,
      ...dateRangeArgs(filter),
    });
    if (error || !data?.[0]) throw this.mapError(error);
    const r = data[0];
    return {
      activeMembers: r.active_members,
      newMemberships: r.new_memberships,
      expiringSoon: r.expiring_soon,
      membershipRevenueMinor: r.membership_revenue_minor,
      paidCount: r.paid_count,
      partiallyPaidCount: r.partially_paid_count,
      pendingCount: r.pending_count,
      outstandingMinor: r.outstanding_minor,
    };
  }

  async getMembershipsByType(filter: AnalyticsFilter): Promise<MembershipTypeRow[]> {
    const { data, error } = await this.supabase.rpc("get_memberships_by_type", {
      p_facility_id: filter.facilityId,
      ...dateRangeArgs(filter),
    });
    if (error) throw this.mapError(error);
    return (data ?? []).map((r) => ({
      membershipType: r.membership_type,
      planName: r.plan_name,
      count: r.count,
      revenueMinor: r.revenue_minor,
    }));
  }

  async getMembershipSessionAnalytics(filter: AnalyticsFilter): Promise<MembershipSessionAnalytics> {
    const { data, error } = await this.supabase.rpc(
      "get_membership_session_analytics",
      this.baseArgs(filter),
    );
    if (error || !data?.[0]) throw this.mapError(error);
    const r = data[0];
    return {
      sessionCount: r.session_count,
      totalCapacity: r.total_capacity,
      memberAllocations: r.member_allocations,
      guestReleased: r.guest_released,
      guestBooked: r.guest_booked,
      remainingReleased: r.remaining_released,
      unusedCapacity: r.unused_capacity,
    };
  }

  async getGuestReleaseAnalytics(filter: AnalyticsFilter): Promise<GuestReleaseAnalytics> {
    const { data, error } = await this.supabase.rpc("get_guest_release_analytics", this.baseArgs(filter));
    if (error || !data?.[0]) throw this.mapError(error);
    const r = data[0];
    return {
      released: r.released,
      booked: r.booked,
      remaining: r.remaining,
      revenueMinor: r.revenue_minor,
    };
  }

  private mapError(error: unknown): ServiceError {
    console.error("[reports-service] request failed", error);
    const message = (error as { message?: string } | null)?.message;
    if (message?.includes("Not authorized")) return new ServiceError("REPORTS_ACCESS_DENIED");
    if (message?.includes("valid start and end date")) return new ServiceError("INVALID_DATE_RANGE");
    return new ServiceError("REPORTS_DATA_ERROR");
  }
}
