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
