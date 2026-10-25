"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { getMyPlan, listPlans, startPlan } from "@/features/plans/service";
import type { BillingInterval } from "@/features/plans/types";

export const planKeys = {
  all: ["plans"] as const,
  options: () => [...planKeys.all, "options"] as const,
  mine: (facilityId: string) => [...planKeys.all, "mine", facilityId] as const,
};

export function usePlanOptions() {
  return useQuery({ queryKey: planKeys.options(), queryFn: listPlans, staleTime: 5 * 60_000 });
}

export function useMyPlan(facilityId: string | undefined) {
  return useQuery({
    queryKey: planKeys.mine(facilityId ?? ""),
    queryFn: () => getMyPlan(facilityId!),
    enabled: !!facilityId,
  });
}

export function useSelectPlan(facilityId: string | undefined) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (v: { planCode: string; interval: BillingInterval }) => startPlan(facilityId!, v.planCode, v.interval),
    onSuccess: () => qc.invalidateQueries({ queryKey: planKeys.all }),
  });
}
