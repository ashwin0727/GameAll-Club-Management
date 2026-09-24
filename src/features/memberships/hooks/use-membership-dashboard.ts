import { useQuery } from "@tanstack/react-query";
import { getMembershipService } from "@/services/memberships";
import type { MembershipListRow } from "@/features/memberships/types";

const MEMBERSHIP_STALE_TIME = 15_000;

// Every membership, every status, in one page — used to compute the dashboard's derived
// figures (expiring soon, inactive, plan distribution, the 6-month trend) client-side.
// Comfortably covers any club's roster without a dedicated summary RPC.
const ALL_ROWS_PAGE_SIZE = 5000;

/** Every membership at the facility, unfiltered — the raw material for the dashboard's charts. */
export function useAllMemberships(facilityId: string | null) {
  return useQuery<MembershipListRow[]>({
    queryKey: ["membership-dashboard-rows", facilityId],
    enabled: Boolean(facilityId),
    staleTime: MEMBERSHIP_STALE_TIME,
    queryFn: async () => {
      const result = await getMembershipService().listMemberships(facilityId!, {
        sort: "oldest",
        page: 1,
        perPage: ALL_ROWS_PAGE_SIZE,
      });
      return result.rows;
    },
  });
}
