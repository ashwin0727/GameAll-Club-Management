import type { MembershipListRow } from "@/features/memberships/types";

const MS_PER_DAY = 24 * 60 * 60 * 1000;

/** Whole days between two ISO dates (`b` minus `a`), ignoring time of day. */
function daysBetween(a: string, b: string): number {
  return Math.round((new Date(b + "T00:00:00").getTime() - new Date(a + "T00:00:00").getTime()) / MS_PER_DAY);
}

function addDays(d: Date, n: number): Date {
  const copy = new Date(d);
  copy.setDate(copy.getDate() + n);
  return copy;
}

function iso(d: Date): string {
  return d.toISOString().slice(0, 10);
}

export type PlanBucket = "Monthly" | "3 Months" | "6 Months" | "1 Year" | "Others";

export const PLAN_BUCKET_ORDER: PlanBucket[] = ["Monthly", "3 Months", "6 Months", "1 Year", "Others"];

/** Buckets a membership by its billed period (end date minus start date), not its plan name. */
export function bucketForRow(row: Pick<MembershipListRow, "startDate" | "endDate">): PlanBucket {
  const days = daysBetween(row.startDate, row.endDate);
  if (days <= 35) return "Monthly";
  if (days <= 100) return "3 Months";
  if (days <= 200) return "6 Months";
  if (days <= 400) return "1 Year";
  return "Others";
}

export interface PlanDistributionSlice {
  bucket: PlanBucket;
  count: number;
  percent: number;
}

/** How many current memberships fall into each billing-period bucket, for the overview donut. */
export function planDistribution(rows: MembershipListRow[]): PlanDistributionSlice[] {
  const counts = new Map<PlanBucket, number>(PLAN_BUCKET_ORDER.map((b) => [b, 0]));
  for (const row of rows) counts.set(bucketForRow(row), (counts.get(bucketForRow(row)) ?? 0) + 1);
  const total = rows.length;
  return PLAN_BUCKET_ORDER.map((bucket) => {
    const count = counts.get(bucket) ?? 0;
    return { bucket, count, percent: total === 0 ? 0 : (count / total) * 100 };
  });
}

/**
 * Memberships due to lapse within the next 5 days — anything not already inactive whose paid
 * period ends between today and 5 days out.
 */
export function expiringSoon(rows: MembershipListRow[], now: Date): MembershipListRow[] {
  const today = iso(now);
  const cutoff = iso(addDays(now, 5));
  return rows.filter((r) => r.status !== "inactive" && r.endDate >= today && r.endDate <= cutoff);
}

export function inactiveMembers(rows: MembershipListRow[]): MembershipListRow[] {
  return rows.filter((r) => r.status === "inactive");
}

/**
 * Active Members' own change pill: the RPC gives an accurate current count but no history, so
 * the "30 days ago" side is approximated the same way as the other cards — by billing dates,
 * treating a membership as having been active then if today's status isn't inactive and its
 * paid period covered that day.
 */
export function activeMembersChangePct(rows: MembershipListRow[], currentActive: number, now: Date): number | null {
  const asOfIso = iso(addDays(now, -30));
  const before = rows.filter((r) => r.status !== "inactive" && r.startDate <= asOfIso && r.endDate >= asOfIso).length;
  return before === 0 ? null : ((currentActive - before) / before) * 100;
}

/**
 * The absolute change behind a percent figure, rounded to the nearest whole member — e.g. "124
 * members, +12%" reads back as "+13 from last month". Returns null when there's no prior count
 * to compare against.
 */
export function membersDeltaAbs(current: number, changePct: number | null): number | null {
  if (changePct === null) return null;
  const prev = current / (1 + changePct / 100);
  return Math.round(current - prev);
}

/**
 * Percent change of a count against the same rule applied 30 days ago, using only each
 * membership's start/end dates (status history isn't tracked, so this is an approximation:
 * "expiring soon" 30 days ago is read as `endDate` falling in that 5-day window while already
 * started, and "inactive" 30 days ago is read as already past its end date by then).
 */
export function expiringSoonChangePct(rows: MembershipListRow[], now: Date): number | null {
  const asOf = addDays(now, -30);
  const asOfIso = iso(asOf);
  const cutoffIso = iso(addDays(asOf, 5));
  const before = rows.filter((r) => r.startDate <= asOfIso && r.endDate >= asOfIso && r.endDate <= cutoffIso).length;
  const current = expiringSoon(rows, now).length;
  return before === 0 ? null : ((current - before) / before) * 100;
}

export function inactiveChangePct(rows: MembershipListRow[], now: Date): number | null {
  const asOfIso = iso(addDays(now, -30));
  const before = rows.filter((r) => r.endDate < asOfIso).length;
  const current = inactiveMembers(rows).length;
  return before === 0 ? null : ((current - before) / before) * 100;
}

export interface RowsSummary {
  totalMembers: number;
  totalMembersChangePct: number | null;
  activeMembers: number;
  activePctOfTotal: number;
  revenueInr: number;
  revenueChangePct: number | null;
}

/**
 * A `MembershipPageSummary`-equivalent computed entirely from membership rows, for whenever the
 * dashboard is scoped to one sport — the summary RPC has no sport parameter, so its numbers can't
 * be trusted once a facility has more than one sport and a filter is actually narrowing things.
 * Same 30-days-ago approximation (by billing dates) the rest of this file's change-pct helpers
 * already use, so a sport-filtered dashboard reads consistently with its own Expiring/Inactive
 * cards rather than mixing two different measurement techniques. Counts rows (memberships), not
 * deduplicated members, matching every other function here (expiringSoon, inactiveMembers, ...).
 */
export function summaryFromRows(rows: MembershipListRow[], now: Date): RowsSummary {
  const totalMembers = rows.length;
  const activeRows = rows.filter((r) => r.status !== "inactive");
  const activeMembers = activeRows.length;
  const revenueInr = activeRows.reduce((sum, r) => sum + r.monthlyPriceInr, 0);

  const asOfIso = iso(addDays(now, -30));
  const totalMembersBefore = rows.filter((r) => r.startDate <= asOfIso).length;
  const totalMembersChangePct = totalMembersBefore === 0 ? null : ((totalMembers - totalMembersBefore) / totalMembersBefore) * 100;

  const revenueBefore = rows
    .filter((r) => r.status !== "inactive" && r.startDate <= asOfIso && r.endDate >= asOfIso)
    .reduce((sum, r) => sum + r.monthlyPriceInr, 0);
  const revenueChangePct = revenueBefore === 0 ? null : ((revenueInr - revenueBefore) / revenueBefore) * 100;

  return {
    totalMembers,
    totalMembersChangePct,
    activeMembers,
    activePctOfTotal: totalMembers === 0 ? 0 : (activeMembers / totalMembers) * 100,
    revenueInr,
    revenueChangePct,
  };
}

const MONTH_LABELS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

const NICE_STEPS = [
  1, 2, 5, 10, 20, 25, 50, 100, 200, 250, 500, 1_000, 2_000, 2_500, 5_000, 10_000, 20_000, 25_000, 50_000, 100_000,
  200_000, 250_000, 500_000, 1_000_000, 2_000_000, 2_500_000, 5_000_000, 10_000_000,
];

/**
 * Round-number gridlines for a chart's y-axis: zero plus `divisions` steps, the topmost at or
 * above the largest value — 0 / 50 / 100 / 150 for the bar chart, 0 / 100K / 200K / 300K / 400K
 * for the revenue chart.
 */
export function axisTicks(maxValue: number, divisions = 3): number[] {
  const raw = Math.max(maxValue, 1) / divisions;
  const step = NICE_STEPS.find((s) => s >= raw) ?? Math.ceil(raw / 10_000_000) * 10_000_000;
  return Array.from({ length: divisions + 1 }, (_, i) => i * step);
}

export type RowStatus = "active" | "expiring" | "payment_incomplete" | "inactive";

/**
 * The status shown in the members list. On top of the membership's own status, anything still
 * running but due to lapse within 5 days is called out as "expiring", as in the design.
 */
export function rowStatus(row: MembershipListRow, now: Date): RowStatus {
  if (row.status === "inactive") return "inactive";
  if (row.status === "payment_incomplete") return "payment_incomplete";
  const today = iso(now);
  const cutoff = iso(addDays(now, 5));
  return row.endDate >= today && row.endDate <= cutoff ? "expiring" : "active";
}

export interface MonthTrendPoint {
  /** e.g. "Apr" */
  label: string;
  active: number;
  inactive: number;
}

/**
 * The last `months` calendar months (oldest first), each with how many memberships covered
 * that month's last day (active) versus had already ended by then (inactive). Approximated
 * from start/end dates only, since per-month status snapshots aren't stored.
 */
export function activeInactiveTrend(rows: MembershipListRow[], now: Date, months = 6): MonthTrendPoint[] {
  const points: MonthTrendPoint[] = [];
  for (let i = months - 1; i >= 0; i--) {
    const monthEnd = new Date(now.getFullYear(), now.getMonth() - i + 1, 0);
    const monthEndIso = iso(monthEnd);
    const active = rows.filter((r) => r.startDate <= monthEndIso && r.endDate >= monthEndIso).length;
    const inactive = rows.filter((r) => r.endDate < monthEndIso).length;
    points.push({ label: MONTH_LABELS[monthEnd.getMonth()]!, active, inactive });
  }
  return points;
}
