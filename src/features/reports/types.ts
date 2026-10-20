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
  /**
   * The sports ticked in the top bar (facility_sports.id), or null for All Sports. Filled in by useAnalyticsFilter from
   * the top bar — never read from or written to the URL — and combined with `facilitySportId`.
   */
  facilitySportIds?: string[] | null;
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
  coachingMinor: number;
  refundsMinor: number;
  netMinor: number;
}

export interface PaymentMethodSlice {
  method: string;
  amountMinor: number;
  count: number;
}

export interface RevenueBySportRow {
  /** null on the last row, "Not linked to a sport": revenue that belongs to no sport (e.g. a member never put in a batch). */
  facilitySportId: string | null;
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

// ─── Overview cards (migration 0140) ──────────────────────────────────────

/** Which card's figure a chart plots. */
export type OverviewMetricKey =
  | "REVENUE"
  | "EXPENSES"
  | "NET"
  | "GUEST_BOOKINGS"
  | "MEMBERS"
  | "PROGRAMS"
  | "COACHES"
  | "STUDENTS"
  | "GUEST_BOOKING_REVENUE"
  | "MEMBERSHIP_REVENUE"
  | "COACHING_REVENUE"
  | "COACHING_EXPENSES";

/** The twelve overview figures. Money is in minor units; the four "now" counts ignore the date range. */
export interface ReportsOverviewMetrics {
  totalRevenueMinor: number;
  totalExpensesMinor: number;
  netRevenueMinor: number;
  guestBookings: number;
  members: number;
  programs: number;
  coaches: number;
  students: number;
  guestBookingRevenueMinor: number;
  membershipRevenueMinor: number;
  coachingRevenueMinor: number;
  coachingExpensesMinor: number;
}

export interface OverviewTrendPoint {
  /** yyyy-mm-dd: the day, the Monday of the week, or the 1st of the month. */
  date: string;
  /** Minor units for money figures, a plain count otherwise. */
  value: number;
}

// ─── Phase 6: Memberships ────────────────────────────────────────────────

export interface MembershipAnalytics {
  activeMembers: number;
  newMemberships: number;
  expiringSoon: number;
  membershipRevenueMinor: number;
  paidCount: number;
  partiallyPaidCount: number;
  pendingCount: number;
  outstandingMinor: number;
}

/**
 * Members for the chosen dates: `total` registered or had a membership running in them, `active` of those have one that has not ended
 * or been cancelled by `asOf` (the last day, or today if that day is still to come), `inactive` is the rest.
 */
export interface MembershipMemberCounts {
  /** yyyy-mm-dd */
  asOf: string;
  total: number;
  active: number;
  inactive: number;
}

/**
 * One timing of a membership session batch (a court held at a time of day on some weekdays) with the members in it. The
 * last row under All Sports has `batchId` null: members counted for the dates who are in no batch.
 */
export interface MembershipBatchRow {
  facilitySportId: string | null;
  sportName: string;
  courtId: string | null;
  courtName: string | null;
  batchId: string | null;
  batchName: string | null;
  /** 0 = Sunday … 6 = Saturday */
  daysOfWeek: number[];
  /** hh:mm:ss */
  startTime: string | null;
  endTime: string | null;
  capacity: number | null;
  members: number;
  activeMembers: number;
  /** Distinct people across every timing on this court / in this sport (a person in two timings counts once). */
  courtMembers: number;
  sportMembers: number;
}

export interface MembershipTypeRow {
  membershipType: string;
  planName: string;
  count: number;
  revenueMinor: number;
}

export interface MembershipSessionAnalytics {
  sessionCount: number;
  totalCapacity: number;
  memberAllocations: number;
  guestReleased: number;
  guestBooked: number;
  remainingReleased: number;
  unusedCapacity: number;
}

export interface GuestReleaseAnalytics {
  released: number;
  booked: number;
  remaining: number;
  revenueMinor: number;
}

// ─── Phase 7: Guest Bookings ─────────────────────────────────────────────

export interface GuestBookingAnalytics {
  total: number;
  completed: number;
  confirmed: number;
  pending: number;
  cancelled: number;
  revenueMinor: number;
  avgBookingValueMinor: number;
  collectedMinor: number;
  outstandingMinor: number;
  collectionRatePct: number;
}

export interface GuestBookingsBySportRow {
  facilitySportId: string;
  sportName: string;
  bookingCount: number;
  revenueMinor: number;
}

export interface GuestBookingsByCourtRow {
  courtId: string;
  courtName: string;
  sportName: string;
  bookingCount: number;
  revenueMinor: number;
}

export interface GuestPeakHourRow {
  hour: number;
  bookingCount: number;
}
