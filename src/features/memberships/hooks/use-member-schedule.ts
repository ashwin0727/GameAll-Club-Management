import { useQuery } from "@tanstack/react-query";
import { getMembershipService } from "@/services/memberships";
import { getPlayingAreasService } from "@/services/playing-areas";
import { getSportsService } from "@/services/sports";
import type { PlayingArea } from "@/features/courts-setup/types";
import type { MembershipDetail, MemberScheduleRow } from "@/features/memberships/types";

const STALE_TIME = 15_000;

/** Every (member, batch) row at the facility — the Manage Member Schedule page's source data
 *  for both the Member List tab and the Select Member picker. */
export function useMemberSchedules(facilityId: string | null) {
  return useQuery<MemberScheduleRow[]>({
    queryKey: ["member-schedules", facilityId],
    enabled: Boolean(facilityId),
    staleTime: STALE_TIME,
    queryFn: () => getMembershipService().listMemberSchedules(facilityId!),
  });
}

/** The plan name / valid-till date / email for the Member Details card — `list_member_schedules`
 *  only carries schedule data, so this fills in the rest from the member's actual membership. */
export function useMembershipDetailFor(membershipId: string | null) {
  return useQuery<MembershipDetail>({
    queryKey: ["membership-detail", membershipId],
    enabled: Boolean(membershipId),
    staleTime: STALE_TIME,
    queryFn: () => getMembershipService().getMembershipDetail(membershipId!),
  });
}

/** facilitySportId → display name ("Badminton", or a facility's own custom name) — the same
 *  `customSportName ?? sport.name` resolution the Membership Sessions page already does. */
export function useFacilitySportNames(facilityId: string | null) {
  return useQuery<Map<string, string>>({
    queryKey: ["facility-sport-names", facilityId],
    enabled: Boolean(facilityId),
    staleTime: 5 * 60_000,
    queryFn: async () => {
      const [facilitySports, sports] = await Promise.all([
        getSportsService().getFacilitySports(facilityId!),
        getSportsService().getActiveSports(),
      ]);
      const sportById = new Map(sports.map((s) => [s.id, s.name]));
      return new Map(facilitySports.map((fs) => [fs.id, fs.customSportName ?? sportById.get(fs.sportId) ?? "Sport"]));
    },
  });
}

/** Every active court at the facility, for the Court filter. */
export function usePlayingAreasList(facilityId: string | null) {
  return useQuery<PlayingArea[]>({
    queryKey: ["playing-areas", facilityId],
    enabled: Boolean(facilityId),
    staleTime: 5 * 60_000,
    queryFn: async () => {
      const areas = await getPlayingAreasService().getPlayingAreas(facilityId!);
      return areas.filter((a) => !a.archived);
    },
  });
}
