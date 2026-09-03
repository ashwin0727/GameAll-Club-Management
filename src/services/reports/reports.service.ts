// ═══════════════════════════════════════════════════════════════════════════
// Reports & Analytics service boundary. Every figure here is server-computed
// by a Supabase RPC (0058+) — this interface only ever describes the SHAPE
// of what the backend returns. Nothing in the reports UI counts, sums, or
// averages a record itself (spec §32 "Data Architecture").
// ═══════════════════════════════════════════════════════════════════════════

import type {
  AnalyticsFilter,
  AnalyticsGranularity,
  BookingAnalytics,
  BookingTrendPoint,
  BookingsBySportRow,
  BookingSourceRow,
} from "@/features/reports/types";

export interface ReportsService {
  /** Status counts + guest/member split + avg guest booking value for the range. */
  getBookingAnalytics(filter: AnalyticsFilter): Promise<BookingAnalytics>;
  /** Booking volume over time, zero-filled, bucketed at the given granularity. */
  getBookingTrend(filter: AnalyticsFilter, granularity: AnalyticsGranularity): Promise<BookingTrendPoint[]>;
  /** One row per active facility sport (0-count sports included), busiest first. */
  getBookingsBySport(filter: AnalyticsFilter): Promise<BookingsBySportRow[]>;
  /** Exactly two rows — GUEST and MEMBER. */
  getBookingSourceSplit(filter: AnalyticsFilter): Promise<BookingSourceRow[]>;
}
