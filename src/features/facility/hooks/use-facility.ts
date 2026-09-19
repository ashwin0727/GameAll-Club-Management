import { useQuery } from "@tanstack/react-query";
import { getFacilityService } from "@/services/facility";

export const FACILITY_QUERY_KEY = ["facility", "current"] as const;

/**
 * The signed-in user's active facility. Rarely changes within a session, so a
 * long staleTime means navigating between pages reuses the cached value
 * instead of re-fetching it (auth.getUser() + a facilities select) on every
 * mount.
 */
export function useFacility() {
  return useQuery({
    queryKey: FACILITY_QUERY_KEY,
    queryFn: () => getFacilityService().getFacility(),
    staleTime: 5 * 60_000,
  });
}
