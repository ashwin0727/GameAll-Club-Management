import { useQuery } from "@tanstack/react-query";
import { getMembershipService } from "@/services/memberships";
import type { MembershipListParams, RevenueGranularity } from "@/features/memberships/types";

export function useMembershipRevenue(facilityId: string | null, granularity: RevenueGranularity) {
  return useQuery({
    queryKey: ["membership-revenue", facilityId, granularity],
    queryFn: () => getMembershipService().getMembershipRevenueTimeseries(facilityId!, granularity),
    enabled: Boolean(facilityId),
  });
}

export function useMembershipList(facilityId: string | null, params: MembershipListParams) {
  return useQuery({
    queryKey: ["membership-list", facilityId, params],
    queryFn: () => getMembershipService().listMemberships(facilityId!, params),
    enabled: Boolean(facilityId),
    placeholderData: (prev) => prev,
  });
}

export function useMembershipSummary(facilityId: string | null) {
  return useQuery({
    queryKey: ["membership-summary", facilityId],
    queryFn: () => getMembershipService().getMembershipPageSummary(facilityId!),
    enabled: Boolean(facilityId),
  });
}