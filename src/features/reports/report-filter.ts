// ═══════════════════════════════════════════════════════════════════════════
// AnalyticsFilter -> RPC argument mapping. Every reports service method builds
// its args from these two helpers so the date-range and sport/court contract
// is defined in exactly one place (mirrors SupabaseFinanceService's inline
// dateRangeArgs).
// ═══════════════════════════════════════════════════════════════════════════

import type { AnalyticsFilter } from "./types";

export function dateRangeArgs(f: AnalyticsFilter): {
  p_preset: string;
  p_start_date: string | null;
  p_end_date: string | null;
} {
  const custom = f.preset === "CUSTOM";
  return {
    p_preset: f.preset,
    p_start_date: custom ? (f.startDate ?? null) : null,
    p_end_date: custom ? (f.endDate ?? null) : null,
  };
}

export function scopeArgs(f: AnalyticsFilter): {
  p_facility_sport_id: string | null;
  p_court_id: string | null;
} {
  return {
    p_facility_sport_id: f.facilitySportId ?? null,
    p_court_id: f.courtId ?? null,
  };
}
