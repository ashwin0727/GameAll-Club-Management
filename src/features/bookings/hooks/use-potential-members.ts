"use client";

import { useMemo } from "react";
import { useQuery } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";
import { useGuestHistory } from "@/features/bookings/hooks/use-guest-booking-stats";
import { phoneKey } from "@/features/bookings/guest-insights";
import { buildGuestProfiles, type GuestProfile } from "@/features/bookings/potential-members";

/** The phone numbers (last ten digits) of the club's current members — who a guest is checked against. */
export function useMemberPhoneKeys(facilityId: string | null) {
  return useQuery({
    queryKey: ["member-phone-keys", facilityId],
    enabled: Boolean(facilityId),
    staleTime: 60_000,
    queryFn: async (): Promise<Set<string>> => {
      const { data } = await createClient().from("members").select("phone").eq("facility_id", facilityId!).eq("status", "ACTIVE");
      return new Set((data ?? []).map((m) => phoneKey(m.phone)).filter((k): k is string => k !== null));
    },
  });
}

/**
 * Every guest of the sport, each with their booking history summed up and whether they are
 * already a member. `guests` is undefined until both the history and the member list are in.
 */
export function useGuestProfiles(facilityId: string | null, facilitySportId: string) {
  const history = useGuestHistory(facilityId, facilitySportId);
  const members = useMemberPhoneKeys(facilityId);
  const guests = useMemo<GuestProfile[] | undefined>(
    () => (history.data && members.data ? buildGuestProfiles(history.data, members.data, new Date()) : undefined),
    [history.data, members.data],
  );
  return { guests, isError: history.isError || members.isError, refetch: history.refetch };
}
