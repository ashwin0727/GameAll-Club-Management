import { useQuery } from "@tanstack/react-query";
import { getSportsService } from "@/services/sports";

export interface FacilitySportOption {
  facilitySportId: string;
  name: string;
  icon: string;
}

/**
 * The sports the owner selected while onboarding, as picker options. Names
 * follow the same rule the dashboard uses: a custom name wins over the
 * catalogue name.
 */
export function useFacilitySportOptions(facilityId: string | undefined) {
  return useQuery({
    queryKey: ["facility-sport-options", facilityId],
    enabled: Boolean(facilityId),
    staleTime: 5 * 60_000,
    queryFn: async (): Promise<FacilitySportOption[]> => {
      const service = getSportsService();
      const [facilitySports, sports] = await Promise.all([
        service.getFacilitySports(facilityId!),
        service.getActiveSports(),
      ]);
      return facilitySports.map((fs) => {
        const sport = sports.find((s) => s.id === fs.sportId);
        return {
          facilitySportId: fs.id,
          name: fs.customSportName || sport?.name || "Sport",
          icon: sport?.icon ?? "🏅",
        };
      });
    },
  });
}
