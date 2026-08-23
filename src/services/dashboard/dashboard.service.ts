import type { DashboardSummary, DateRangePreset } from "@/features/dashboard/types";

export interface DashboardSummaryParams {
  /** null = All Sports (aggregate). */
  facilitySportId: string | null;
  preset: DateRangePreset;
  custom?: { from: string; to: string };
}

/**
 * The dashboard boundary the UI codes against. Aggregates everything the
 * Owner Dashboard needs — facility, sports, utilization, schedule,
 * memberships, payments, attention items — into one response, reusing the
 * facility/sports/playing-areas/operating-hours services already built
 * rather than the page issuing a dozen independent requests.
 */
export interface DashboardService {
  getDashboardSummary(facilityId: string, params: DashboardSummaryParams): Promise<DashboardSummary>;
}
