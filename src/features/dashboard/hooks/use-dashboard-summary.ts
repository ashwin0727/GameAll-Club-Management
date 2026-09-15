import { useQuery } from "@tanstack/react-query";
import { getDashboardService } from "@/services/dashboard";
import type { DashboardSummaryParams } from "@/services/dashboard";
import type { Facility } from "@/features/onboarding/types";

export function useDashboardSummary(facility: Facility | null, params: DashboardSummaryParams) {
  return useQuery({
    queryKey: ["dashboard-summary", facility?.id, params],
    queryFn: () => getDashboardService().getDashboardSummary(facility!, params),
    enabled: Boolean(facility),
    // The dashboard is the most-visited page and its numbers change from
    // actions taken elsewhere (future Bookings/Payments/Members pages) — a
    // background refetch on refocus is the "clean invalidation mechanism"
    // called for without introducing Realtime infrastructure this codebase
    // doesn't use anywhere else yet. staleTime avoids re-running the whole
    // multi-query chain on every remount/refocus when nothing could have
    // changed yet.
    staleTime: 30_000,
    refetchOnWindowFocus: true,
  });
}