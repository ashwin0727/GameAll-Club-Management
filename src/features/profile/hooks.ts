"use client";

import { useQuery } from "@tanstack/react-query";
import { samplePlan } from "@/features/profile/plan";
import { getProfileService } from "@/services/profile";

const STALE = 60_000;

export const profileKeys = {
  plan: (facilityId: string) => ["profile", "plan", facilityId] as const,
  stats: (facilityId: string) => ["profile", "stats", facilityId] as const,
  payouts: (facilityId: string) => ["profile", "payouts", facilityId] as const,
  tickets: (facilityId: string) => ["profile", "tickets", facilityId] as const,
  prefs: ["profile", "notification-prefs"] as const,
};

export function useFacilityPlan(facilityId: string | undefined) {
  return useQuery({
    queryKey: profileKeys.plan(facilityId ?? ""),
    // Until a real plan is synced in, show the sample one.
    queryFn: async () => (await getProfileService().getPlan(facilityId!)) ?? samplePlan(),
    enabled: !!facilityId,
    staleTime: STALE,
  });
}

export function useProfileStats(facilityId: string | undefined) {
  return useQuery({
    queryKey: profileKeys.stats(facilityId ?? ""),
    queryFn: () => getProfileService().getStats(facilityId!),
    enabled: !!facilityId,
    staleTime: STALE,
  });
}

export function usePayoutMethods(facilityId: string | undefined, enabled = true) {
  return useQuery({
    queryKey: profileKeys.payouts(facilityId ?? ""),
    queryFn: () => getProfileService().listPayoutMethods(facilityId!),
    enabled: !!facilityId && enabled,
  });
}

export function useSupportTickets(facilityId: string | undefined) {
  return useQuery({
    queryKey: profileKeys.tickets(facilityId ?? ""),
    queryFn: () => getProfileService().listSupportTickets(facilityId!),
    enabled: !!facilityId,
  });
}

export function useNotificationPrefs() {
  return useQuery({
    queryKey: profileKeys.prefs,
    queryFn: () => getProfileService().getNotificationPrefs(),
    staleTime: STALE,
  });
}
