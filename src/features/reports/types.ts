// ═══════════════════════════════════════════════════════════════════════════
// Reports & Analytics — the one filter shape every report RPC call is built
// from (spec §"Shared filter model"). Like Finance, the frontend only ever
// picks a preset string; the backend's resolve_finance_date_range turns it
// into real dates in the facility's timezone.
// ═══════════════════════════════════════════════════════════════════════════

export type AnalyticsPreset =
  | "TODAY"
  | "YESTERDAY"
  | "THIS_WEEK"
  | "LAST_WEEK"
  | "THIS_MONTH"
  | "LAST_MONTH"
  | "THIS_QUARTER"
  | "THIS_YEAR"
  | "CUSTOM";

export type AnalyticsGranularity = "daily" | "weekly" | "monthly";

export interface AnalyticsFilter {
  /** Never trusted from the URL alone — every RPC re-authorises via RLS. */
  facilityId: string;
  preset: AnalyticsPreset;
  /** Required, and only used, when preset is CUSTOM. ISO yyyy-mm-dd. */
  startDate?: string | null;
  endDate?: string | null;
  /** facility_sports.id — null means "all sports". */
  facilitySportId?: string | null;
  /** courts.id — null means "all courts". */
  courtId?: string | null;
}

export const DEFAULT_FILTER_PRESET: AnalyticsPreset = "THIS_MONTH";

export const PRESET_LABELS: Record<AnalyticsPreset, string> = {
  TODAY: "Today",
  YESTERDAY: "Yesterday",
  THIS_WEEK: "This Week",
  LAST_WEEK: "Last Week",
  THIS_MONTH: "This Month",
  LAST_MONTH: "Last Month",
  THIS_QUARTER: "This Quarter",
  THIS_YEAR: "This Year",
  CUSTOM: "Custom Range",
};

/** The presets the date dropdown offers. LAST_WEEK is a valid value (the
 *  comparison-period helper produces it) but isn't offered directly. */
export const ANALYTICS_PRESETS: AnalyticsPreset[] = [
  "TODAY",
  "YESTERDAY",
  "THIS_WEEK",
  "THIS_MONTH",
  "LAST_MONTH",
  "THIS_QUARTER",
  "THIS_YEAR",
  "CUSTOM",
];

// ─── Phase 2: Bookings ────────────────────────────────────────────────────

export interface BookingAnalytics {
  total: number;
  completed: number;
  confirmed: number;
  pending: number;
  cancelled: number;
  guestCount: number;
  memberCount: number;
  /** Captured value of paid, non-cancelled guest bookings ÷ their count. */
  avgGuestBookingValueMinor: number;
}

export interface BookingTrendPoint {
  date: string;
  total: number;
  completed: number;
  cancelled: number;
}

export interface BookingsBySportRow {
  facilitySportId: string;
  sportName: string;
  bookingCount: number;
}

export interface BookingSourceRow {
  source: "GUEST" | "MEMBER";
  bookingCount: number;
}

// ─── Phase 3: Court Utilization ──────────────────────────────────────────

export interface OverallUtilization {
  openMinutes: number;
  bookedMinutes: number;
  utilizationPct: number;
}

export interface CourtUtilizationRow {
  courtId: string;
  courtName: string;
  facilitySportId: string;
  sportName: string;
  openMinutes: number;
  bookedMinutes: number;
  utilizationPct: number;
}

export interface SportUtilizationRow {
  facilitySportId: string;
  sportName: string;
  openMinutes: number;
  bookedMinutes: number;
  utilizationPct: number;
}

export interface PeakHourRow {
  hour: number;
  openMinutes: number;
  bookedMinutes: number;
  demandPct: number;
}

export interface HeatmapCell {
  dow: number;
  hour: number;
  openMinutes: number;
  bookedMinutes: number;
  demandPct: number;
}

// ─── Phase 4: Revenue ────────────────────────────────────────────────────

export interface RevenueSummary {
  grossMinor: number;
  refundsMinor: number;
  expensesMinor: number;
  netMinor: number;
  outstandingMinor: number;
}

export interface RevenueBreakdown {
  membershipMinor: number;
  memberBookingMinor: number;
  guestBookingMinor: number;
  refundsMinor: number;
  netMinor: number;
}

export interface PaymentMethodSlice {
  method: string;
  amountMinor: number;
  count: number;
}

export interface RevenueBySportRow {
  facilitySportId: string;
  sportName: string;
  revenueMinor: number;
}

export interface RevenueByCourtRow {
  courtId: string;
  courtName: string;
  facilitySportId: string;
  sportName: string;
  revenueMinor: number;
}

// ─── Phase 5: Overview ───────────────────────────────────────────────────

export interface AnalyticsOverview {
  grossRevenueMinor: number;
  bookingRevenueMinor: number;
  membershipRevenueMinor: number;
  expensesMinor: number;
  netRevenueMinor: number;
  outstandingMinor: number;
  totalBookings: number;
  completedBookings: number;
  cancelledBookings: number;
  overallUtilizationPct: number;
}
