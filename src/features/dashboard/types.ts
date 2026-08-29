export type DateRangePreset = "TODAY" | "YESTERDAY" | "THIS_WEEK" | "THIS_MONTH" | "CUSTOM";

/** [from, to) — half-open ISO instant range. */
export interface DateRange {
  from: string;
  to: string;
}

export interface KpiValue {
  value: number;
  /** null when the previous period can't be meaningfully compared (e.g. a custom range). */
  previousValue: number | null;
  changePercent: number | null;
}

export interface DashboardKpis {
  /** Paid revenue in the selected period; scoped to the selected sport (booking court + member's batch sport). */
  revenueInr: KpiValue;
  /** Memberships active as of now; scoped to the selected sport via batch enrolment. Date range does not affect it. */
  activeMemberships: KpiValue;
  /** Guest bookings that are booked and paid in the selected period; scoped to the selected sport by court. */
  guestBookings: KpiValue;
  utilizationPercent: KpiValue;
}

/**
 * `payments` isn't linked to a booking/sport in the current schema (no
 * booking_id/facility_sport_id column) — a per-sport revenue split can't be
 * computed honestly yet, so this stays an explicit unavailable state rather
 * than an estimate.
 */
export interface RevenueBySportSummary {
  available: false;
}

export interface CourtUtilizationEntry {
  playingAreaId: string;
  playingAreaName: string;
  utilizationPercent: number;
}

export interface SportUtilizationEntry {
  facilitySportId: string;
  sportName: string;
  utilizationPercent: number;
  courts: CourtUtilizationEntry[];
}

export interface UtilizationSummary {
  overallPercent: number;
  bySport: SportUtilizationEntry[];
}

/**
 * The only block types with real backing data: a regular member booking, a
 * regular guest booking, or actual usage of a membership-protected session.
 * There is no "blocked"/"maintenance" table yet, so those are never fabricated.
 */
export type ScheduleBlockType = "MEMBER" | "GUEST" | "SESSION";

export interface ScheduleBlock {
  id: string;
  label: string;
  /** Minutes from midnight (local), clamped to the timeline's [startHour, endHour] window. */
  startMinute: number;
  endMinute: number;
  /** e.g. "5:00 – 6:00 PM". */
  timeLabel: string;
  type: ScheduleBlockType;
  /** Lane index for side-by-side stacking of overlapping blocks in the same court. */
  lane: number;
}

export interface ScheduleCourtRow {
  courtId: string;
  courtName: string;
  sportName: string;
  /** Number of overlap lanes this row needs (>= 1). */
  laneCount: number;
  blocks: ScheduleBlock[];
}

export interface ScheduleTimeline {
  /** Hour-of-day axis bounds derived from today's actual operating slots (e.g. 6 and 23). Both 0 when closed. */
  startHour: number;
  endHour: number;
  courts: ScheduleCourtRow[];
}

export interface MembershipSummary {
  active: number;
  expiringSoon: number;
  expired: number;
  newThisMonth: number;
}

/** Guest-player tracking has no backing table yet — always unavailable, never fabricated. */
export interface GuestSummary {
  available: false;
}

export interface PaymentSummary {
  collectedInr: number;
  pendingInr: number;
  refundsInr: number;
}

/** Finance/expense tracking has no backing table yet — always unavailable, never fabricated. */
export interface ExpenseSummary {
  available: false;
}

export interface BusinessPosition {
  revenueInr: number;
  expensesAvailable: false;
}

export interface AttentionItem {
  id: string;
  message: string;
  /** Omitted when there's no existing page this can honestly link to yet. */
  actionLabel?: string;
  actionHref?: string;
}

/** No activity/event log table exists yet — always unavailable, never fabricated. */
export interface LiveActivitySummary {
  available: false;
}

/** No tournament/coaching/maintenance-schedule tables exist yet — always unavailable, never fabricated. */
export interface UpcomingActivitiesSummary {
  available: false;
}

export interface AvailableSportOption {
  facilitySportId: string;
  sportName: string;
  sportIcon: string;
}

export interface RevenueTrendPoint {
  /** Calendar date, "YYYY-MM-DD". */
  date: string;
  /** Collected (paid) revenue for that day, in whole rupees. */
  amountInr: number;
}

export type RevenueBreakdownKey = "bookings" | "memberships" | "coaching" | "other";

export interface RevenueBreakdownSegment {
  key: RevenueBreakdownKey;
  label: string;
  /** Paid revenue for this category in the selected month, whole rupees. */
  amountInr: number;
  /** Number of paid transactions; null for categories with no backing data yet (coaching/other). */
  count: number | null;
  /** True when the category has no data source yet — shown at ₹0, not fabricated. */
  unavailable: boolean;
}

export interface RevenueOverview {
  /** Human label for the selected month, e.g. "May 2026". */
  monthLabel: string;
  /** First day of the selected month, "YYYY-MM-DD" (for the x-axis). */
  monthStart: string;
  /** Total paid revenue for the month, whole rupees. */
  totalInr: number;
  /** Percent change vs the previous month; null when the previous month had no revenue. */
  changePercent: number | null;
  /** One point per day of the month (zero-filled), always non-empty so the chart always renders. */
  points: RevenueTrendPoint[];
  /** Where the month's revenue came from — bookings / memberships / (future) coaching / other. */
  breakdown: RevenueBreakdownSegment[];
}

export interface DashboardSummary {
  facility: { id: string; name: string; city: string };
  sports: AvailableSportOption[];
  selectedFacilitySportId: string | null;
  period: DateRange;
  kpis: DashboardKpis;
  revenueBySport: RevenueBySportSummary;
  utilization: UtilizationSummary;
  scheduleTimeline: ScheduleTimeline;
  revenueOverview: RevenueOverview;
  liveActivity: LiveActivitySummary;
  memberships: MembershipSummary;
  guests: GuestSummary;
  payments: PaymentSummary;
  expenses: ExpenseSummary;
  businessPosition: BusinessPosition;
  attentionItems: AttentionItem[];
  upcomingActivities: UpcomingActivitiesSummary;
}