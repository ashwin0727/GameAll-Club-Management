import type { DashboardSummary, DateRangePreset } from "@/features/dashboard/types";
import type { Facility } from "@/features/onboarding/types";

export interface DashboardSummaryParams {
  /** null = All Sports (aggregate). */
  facilitySportId: string | null;
  preset: DateRangePreset;
  custom?: { from: string; to: string };
  /** Months back from the current month for the Revenue Overview panel (0 = this month). Independent of `preset`. */
  revenueMonthOffset?: number;
}

/**
 * The dashboard boundary the UI codes against. Aggregates everything the
 * Owner Dashboard needs — facility, sports, utilization, schedule,
 * memberships, payments, attention items — into one response, reusing the
 * facility/sports/playing-areas/operating-hours services already built
 * rather than the page issuing a dozen independent requests.
 *
 * Takes the already-resolved `facility` (not just its id) so the caller's
 * existing facility fetch can be reused instead of this service fetching it
 * again internally.
 */
export interface DashboardService {
  getDashboardSummary(facility: Facility, params: DashboardSummaryParams): Promise<DashboardSummary>;
}
