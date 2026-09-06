// ═══════════════════════════════════════════════════════════════════════════
// The single place AnalyticsFilter is encoded to / decoded from the URL
// query string. Report links (drill-down, "view all", shared bookmarks) are
// therefore just hrefs — no client state to thread through. facilityId is
// always in the URL and always re-authorised server-side by RLS.
// ═══════════════════════════════════════════════════════════════════════════

import {
  ANALYTICS_PRESETS,
  DEFAULT_FILTER_PRESET,
  type AnalyticsFilter,
  type AnalyticsPreset,
} from "./types";

type ParamsLike = { get(key: string): string | null };

const PRESET_SET = new Set<string>([...ANALYTICS_PRESETS, "LAST_WEEK"]);

export function filterToSearchParams(filter: AnalyticsFilter): URLSearchParams {
  const params = new URLSearchParams();
  params.set("facility", filter.facilityId);
  params.set("preset", filter.preset);
  if (filter.preset === "CUSTOM") {
    if (filter.startDate) params.set("from", filter.startDate);
    if (filter.endDate) params.set("to", filter.endDate);
  }
  if (filter.facilitySportId) params.set("sport", filter.facilitySportId);
  if (filter.courtId) params.set("court", filter.courtId);
  return params;
}

export function filterFromSearchParams(params: ParamsLike, fallbackFacilityId: string): AnalyticsFilter {
  const rawPreset = params.get("preset");
  let preset: AnalyticsPreset =
    rawPreset && PRESET_SET.has(rawPreset) ? (rawPreset as AnalyticsPreset) : DEFAULT_FILTER_PRESET;

  const from = params.get("from");
  const to = params.get("to");
  if (preset === "CUSTOM" && !(from && to)) preset = DEFAULT_FILTER_PRESET;

  return {
    facilityId: params.get("facility") ?? fallbackFacilityId,
    preset,
    startDate: preset === "CUSTOM" ? from : null,
    endDate: preset === "CUSTOM" ? to : null,
    facilitySportId: params.get("sport"),
    courtId: params.get("court"),
  };
}
