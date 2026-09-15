import { useQuery } from "@tanstack/react-query";
import { getMembershipService } from "@/services/memberships";
import type { MembershipListParams, RevenueGranularity } from "@/features/memberships/types";

// Membership data changes from actions taken on this same page (payments,
// new signups), so a short staleTime is enough to skip a redundant refetch on
// a quick remount/filter-toggle without risking stale numbers.
const MEMBERSHIP_STALE_TIME = 15_000;

export function useMembershipRevenue(facilityId: string | null, granularity: RevenueGranularity) {
  return useQuery({
    queryKey: ["membership-revenue", facilityId, granularity],
    queryFn: () => getMembershipService().getMembershipRevenueTimeseries(facilityId!, granularity),
    enabled: Boolean(facilityId),
    staleTime: MEMBERSHIP_STALE_TIME,
  });
}

export function useMembershipList(facilityId: string | null, params: MembershipListParams) {
  return useQuery({
    queryKey: ["membership-list", facilityId, params],
    queryFn: () => getMembershipService().listMemberships(facilityId!, params),
    enabled: Boolean(facilityId),
    placeholderData: (prev) => prev,
    staleTime: MEMBERSHIP_STALE_TIME,
  });
}

export function useMembershipSummary(facilityId: string | null) {
  return useQuery({
    queryKey: ["membership-summary", facilityId],
    queryFn: () => getMembershipService().getMembershipPageSummary(facilityId!),
    enabled: Boolean(facilityId),
    staleTime: MEMBERSHIP_STALE_TIME,
  });
}