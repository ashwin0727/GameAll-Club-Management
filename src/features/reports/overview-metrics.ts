import type { DayRange } from "@/features/finance/day-range";
import type { OverviewMetricKey, OverviewTrendPoint, ReportsOverviewMetrics } from "@/features/reports/types";

export type MetricKind = "money" | "count";

export interface OverviewMetricDef {
  key: OverviewMetricKey;
  /** The card's title. */
  title: string;
  kind: MetricKind;
  /** Chart colour. */
  color: string;
  /** What the figure is, with the scope word in front: "Overall revenue" / "Selected revenue". */
  describe: (scope: string) => string;
  /** The chart heading when this card is selected. */
  heading: (scope: string) => string;
  /** Read the figure off the server's metrics. */
  read: (m: ReportsOverviewMetrics) => number;
  /** Not split by sport: shows the whole facility even when sports are selected. */
  facilityWide?: boolean;
  /** A headcount over the dates (members, programs, coaches, students): the chart shows how many were added in each bucket instead. */
  snapshot?: boolean;
}

/** "Overall" under All Sports, "Selected" when particular sports are chosen. */
export function scopeWord(sportsSelected: boolean): "Overall" | "Selected" {
  return sportsSelected ? "Selected" : "Overall";
}

/** In the order the cards are shown: three rows of four. */
export const OVERVIEW_METRICS: OverviewMetricDef[] = [
  { key: "REVENUE", title: "Total Revenue", kind: "money", color: "#00D084", describe: (s) => `${s} revenue`, heading: (s) => `${s} Revenue Trend`, read: (m) => m.totalRevenueMinor },
  { key: "EXPENSES", title: "Total Expenses", kind: "money", color: "#FF4D67", facilityWide: true, describe: (s) => `${s} expenses`, heading: (s) => `${s} Expenses Trend`, read: (m) => m.totalExpensesMinor },
  { key: "NET", title: "Net Revenue", kind: "money", color: "#6366F1", describe: (s) => `${s} revenue less expenses`, heading: (s) => `${s} Net Revenue Trend`, read: (m) => m.netRevenueMinor },
  { key: "GUEST_BOOKINGS", title: "Total Guest Booking", kind: "count", color: "#0EA5E9", describe: (s) => `${s} guest bookings`, heading: (s) => `${s} Guest Bookings`, read: (m) => m.guestBookings },
  { key: "MEMBERS", title: "Total Members", kind: "count", color: "#8B5CF6", snapshot: true, describe: (s) => `${s} active memberships`, heading: () => "New Memberships Started", read: (m) => m.members },
  { key: "PROGRAMS", title: "Total Program", kind: "count", color: "#F59E0B", snapshot: true, describe: (s) => `${s} active programs`, heading: () => "Programs Started", read: (m) => m.programs },
  { key: "COACHES", title: "Total Coach", kind: "count", color: "#14B8A6", snapshot: true, describe: (s) => `${s} active coaches`, heading: () => "Coaches Joined", read: (m) => m.coaches },
  { key: "STUDENTS", title: "Total Students", kind: "count", color: "#EC4899", snapshot: true, describe: (s) => `${s} enrolled students`, heading: () => "Students Enrolled", read: (m) => m.students },
  { key: "GUEST_BOOKING_REVENUE", title: "Guest Booking Revenue", kind: "money", color: "#00D084", describe: (s) => `${s} guest booking revenue`, heading: (s) => `${s} Guest Booking Revenue Trend`, read: (m) => m.guestBookingRevenueMinor },
  { key: "MEMBERSHIP_REVENUE", title: "Membership Revenue", kind: "money", color: "#8B5CF6", describe: (s) => `${s} members revenue`, heading: (s) => `${s} Membership Revenue Trend`, read: (m) => m.membershipRevenueMinor },
  { key: "COACHING_REVENUE", title: "Coaching Revenue", kind: "money", color: "#F59E0B", describe: (s) => `${s} students revenue`, heading: (s) => `${s} Coaching Revenue Trend`, read: (m) => m.coachingRevenueMinor },
  { key: "COACHING_EXPENSES", title: "Coaching Expenses", kind: "money", color: "#FF4D67", facilityWide: true, describe: (s) => `${s} coaching expenses`, heading: (s) => `${s} Coaching Expenses Trend`, read: (m) => m.coachingExpensesMinor },
];

export function metricDef(key: OverviewMetricKey): OverviewMetricDef {
  return OVERVIEW_METRICS.find((m) => m.key === key)!;
}

/** A day-by-day chart for a short span, weekly for a few months, monthly beyond that. */
export function trendGranularity(range: DayRange): "daily" | "weekly" | "monthly" {
  const days = Math.round((new Date(range.to).getTime() - new Date(range.from).getTime()) / 86_400_000) + 1;
  if (days > 120) return "monthly";
  if (days > 45) return "weekly";
  return "daily";
}

const rupees = (minor: number) => (minor / 100).toFixed(2);

const csvCell = (value: string | number): string => {
  const s = String(value);
  return /[",\r\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
};

/**
 * The Overview export: the period and scope, then the twelve figures split into the same three groups as the cards, then
 * the chart that was on screen (one row per day / week / month). Amounts are in rupees, counts are plain numbers.
 */
export function buildOverviewCsv(input: {
  range: DayRange;
  sportsLabel: string | null;
  metrics: ReportsOverviewMetrics;
  chart: { title: string; kind: MetricKind; points: OverviewTrendPoint[] };
}): string {
  const scope = scopeWord(input.sportsLabel !== null);
  const value = (key: OverviewMetricKey) => {
    const def = metricDef(key);
    const v = def.read(input.metrics);
    return def.kind === "money" ? rupees(v) : String(v);
  };
  const line = (key: OverviewMetricKey) => {
    const def = metricDef(key);
    const note = def.facilityWide && input.sportsLabel !== null ? " (not split by sport)" : "";
    return [def.title, def.describe(scope) + note, def.kind === "money" ? "INR" : "count", value(key)].map(csvCell).join(",");
  };

  const lines = [
    "GameAll Reports & Analytics — Overview",
    `Period,${input.range.from} to ${input.range.to}`,
    `Sports,${csvCell(input.sportsLabel ?? "All sports")}`,
    "",
    "Section,Metric,Unit,Value".replace("Section,", ""),
    "Finance",
    line("REVENUE"),
    line("EXPENSES"),
    line("NET"),
    "Activity",
    line("GUEST_BOOKINGS"),
    line("MEMBERS"),
    line("PROGRAMS"),
    line("COACHES"),
    line("STUDENTS"),
    "Revenue and coaching cost",
    line("GUEST_BOOKING_REVENUE"),
    line("MEMBERSHIP_REVENUE"),
    line("COACHING_REVENUE"),
    line("COACHING_EXPENSES"),
    "",
    csvCell(input.chart.title),
    `Date,${input.chart.kind === "money" ? "Amount (INR)" : "Count"}`,
    ...input.chart.points.map((p) => `${p.date},${input.chart.kind === "money" ? rupees(p.value) : p.value}`),
  ];
  // The BOM makes Excel read the file as UTF-8.
  return "﻿" + lines.join("\r\n");
}
