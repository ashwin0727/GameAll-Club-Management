import { useQuery } from "@tanstack/react-query";
import { getDashboardService } from "@/services/dashboard";
import type { DashboardSummaryParams } from "@/services/dashboard";

export function useDashboardSummary(facilityId: string | null, params: DashboardSummaryParams) {
  return useQuery({
    queryKey: ["dashboard-summary", facilityId, params],
    queryFn: () => getDashboardService().getDashboardSummary(facilityId!, params),
    enabled: Boolean(facilityId),
    // The dashboard is the most-visited page and its numbers change from
    // actions taken elsewhere (future Bookings/Payments/Members pages) — a
    // background refetch on refocus is the "clean invalidation mechanism"
    // called for without introducing Realtime infrastructure this codebase
    // doesn't use anywhere else yet.
    refetchOnWindowFocus: true,
  });
}