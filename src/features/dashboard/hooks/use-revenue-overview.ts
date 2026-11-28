import { keepPreviousData, useQuery } from "@tanstack/react-query";
import { getDashboardService } from "@/services/dashboard";
import type { Facility } from "@/features/onboarding/types";

/**
 * The Revenue Overview for a month other than this one. It is its own query, so paging the month loads only this panel: the dashboard
 * summary (whose key does not include the month) stays as it is and is not fetched again. Month 0 (this month) is already part of the
 * summary, so nothing is requested for it.
 */
export function useRevenueOverview(facility: Facility | null, params: { facilitySportIds: string[] | null; revenueMonthOffset: number }) {
  return useQuery({
    queryKey: ["dashboard-revenue-overview", facility?.id, params.facilitySportIds, params.revenueMonthOffset],
    queryFn: () => getDashboardService().getRevenueOverview(facility!, params),
    enabled: Boolean(facility) && params.revenueMonthOffset !== 0,
    placeholderData: keepPreviousData,
    staleTime: 30_000,
  });
}
