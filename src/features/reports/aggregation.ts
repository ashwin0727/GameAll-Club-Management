// ═══════════════════════════════════════════════════════════════════════════
// Pure client helpers for Reports. No I/O, no React, no date-boundary
// computation for the *server's* range (the backend owns that) — these only
// (a) pick a readable chart granularity from a span, (b) name the comparison
// window, and (c) serialise already-fetched aggregate rows to CSV.
// ═══════════════════════════════════════════════════════════════════════════

import type { AnalyticsFilter, AnalyticsGranularity, AnalyticsPreset } from "./types";

const MS_PER_DAY = 86_400_000;

function parseIso(iso: string): Date {
  // Midnight UTC — these are calendar dates, not instants; arithmetic below
  // only ever takes differences and adds whole days, so the zone is moot.
  const [y, m, d] = iso.split("-").map(Number);
  return new Date(Date.UTC(y!, (m ?? 1) - 1, d ?? 1));
}

function toIso(date: Date): string {
  return date.toISOString().slice(0, 10);
}

/** Inclusive day count: 2026-09-01..2026-09-01 -> 1. */
export function spanDays(startISO: string, endISO: string): number {
  return Math.round((parseIso(endISO).getTime() - parseIso(startISO).getTime()) / MS_PER_DAY) + 1;
}

/** Readable chart buckets: daily <=31d, weekly <=183d, monthly beyond (spec §31). */
export function pickGranularity(startISO: string, endISO: string): AnalyticsGranularity {
  const days = spanDays(startISO, endISO);
  if (days <= 31) return "daily";
  if (days <= 183) return "weekly";
  return "monthly";
}

const PRIOR_PRESET: Partial<Record<AnalyticsPreset, AnalyticsPreset>> = {
  TODAY: "YESTERDAY",
  THIS_WEEK: "LAST_WEEK",
  THIS_MONTH: "LAST_MONTH",
};

/**
 * The equal-length window immediately before this one, for "vs previous
 * period". Common presets map to their sibling; the rest become an explicit
 * CUSTOM range shifted back by their own length (the caller passes the
 * resolved current dates). Null when there is no sensible previous window.
 */
export function previousPeriod(
  filter: AnalyticsFilter,
  resolvedRange?: { startDate: string; endDate: string },
): AnalyticsFilter | null {
  const mapped = PRIOR_PRESET[filter.preset];
  if (mapped) return { ...filter, preset: mapped, startDate: null, endDate: null };

  const range =
    filter.preset === "CUSTOM"
      ? filter.startDate && filter.endDate
        ? { startDate: filter.startDate, endDate: filter.endDate }
        : null
      : resolvedRange ?? null;
  if (!range) return null;

  const length = spanDays(range.startDate, range.endDate);
  const prevEnd = new Date(parseIso(range.startDate).getTime() - MS_PER_DAY);
  const prevStart = new Date(prevEnd.getTime() - (length - 1) * MS_PER_DAY);
  return { ...filter, preset: "CUSTOM", startDate: toIso(prevStart), endDate: toIso(prevEnd) };
}

const NEEDS_QUOTING = /[",\n]/;

/** RFC-4180-ish CSV of already-fetched aggregate rows (tens of rows, not raw records). */
export function toCsv(rows: Array<Record<string, string | number | null>>): string {
  if (rows.length === 0) return "";
  const headers = Object.keys(rows[0]!);
  const encodeCell = (value: string | number | null): string => {
    if (value === null) return '""';
    const s = String(value);
    return NEEDS_QUOTING.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  };
  const lines = [
    headers.join(","),
    ...rows.map((row) => headers.map((h) => encodeCell(row[h] ?? null)).join(",")),
  ];
  return lines.join("\r\n");
}
