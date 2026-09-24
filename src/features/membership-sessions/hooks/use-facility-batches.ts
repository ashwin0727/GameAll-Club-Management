import { useQuery } from "@tanstack/react-query";
import { getMembershipSessionService } from "@/services/membership-sessions";
import type { MembershipBatch } from "@/features/membership-sessions/types";

const STALE_TIME = 30_000;

/**
 * Every Court Access time window (batch) at the facility — each one's own `facilitySportId` is
 * how a membership plan's sport gets worked out (`sport-scope.ts`'s `plansForSport`), since plans
 * themselves don't carry a sport column. Reused across every Membership v1 page that needs to
 * scope its plans/members to the top bar's active sport, instead of each page fetching batches
 * itself via a raw `getFacilityBatches` call.
 */
export function useFacilityBatches(facilityId: string | null) {
  return useQuery<MembershipBatch[]>({
    queryKey: ["membership-batches", facilityId],
    enabled: Boolean(facilityId),
    staleTime: STALE_TIME,
    queryFn: () => getMembershipSessionService().getFacilityBatches(facilityId!),
  });
}
