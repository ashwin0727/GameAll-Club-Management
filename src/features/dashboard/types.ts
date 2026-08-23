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
  revenueInr: KpiValue;
  bookings: KpiValue;
  utilizationPercent: KpiValue;
  activeMembers: KpiValue;
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

export type ScheduleSlotStatus = "AVAILABLE" | "BOOKED";

export interface ScheduleEntry {
  time: string;
  sportName: string;
  playingAreaName: string;
  status: ScheduleSlotStatus;
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

export interface DashboardSummary {
  facility: { id: string; name: string; city: string };
  sports: AvailableSportOption[];
  selectedFacilitySportId: string | null;
  period: DateRange;
  kpis: DashboardKpis;
  revenueBySport: RevenueBySportSummary;
  utilization: UtilizationSummary;
  schedule: ScheduleEntry[];
  liveActivity: LiveActivitySummary;
  memberships: MembershipSummary;
  guests: GuestSummary;
  payments: PaymentSummary;
  expenses: ExpenseSummary;
  businessPosition: BusinessPosition;
  attentionItems: AttentionItem[];
  upcomingActivities: UpcomingActivitiesSummary;
}