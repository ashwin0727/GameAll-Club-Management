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

  private mapError(error: unknown): ServiceError {
    console.error("[reports-service] request failed", error);
    const message = (error as { message?: string } | null)?.message;
    if (message?.includes("Not authorized")) return new ServiceError("REPORTS_ACCESS_DENIED");
    if (message?.includes("valid start and end date")) return new ServiceError("INVALID_DATE_RANGE");
    return new ServiceError("REPORTS_DATA_ERROR");
  }
}
