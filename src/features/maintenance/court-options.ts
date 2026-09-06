import { getPlayingAreasService } from "@/services/playing-areas";
import { getSportsService } from "@/services/sports";

export interface CourtOption {
  id: string;
  name: string;
  facilitySportId: string;
  sportName: string;
}

/**
 * Court + sport labels for a facility, built from the existing courts-setup
 * and sports-setup services — no new "list courts" endpoint. Only ACTIVE,
 * non-archived, booking-enabled courts are offered (a ticket about a
 * disabled court is still filed by editing it directly if ever needed —
 * not the common path this picker serves).
 */
export async function getCourtOptions(facilityId: string): Promise<CourtOption[]> {
  const [areas, sports, facilitySports] = await Promise.all([
    getPlayingAreasService().getPlayingAreas(facilityId),
    getSportsService().getActiveSports(),
    getSportsService().getFacilitySports(facilityId),
  ]);

  const sportName = (facilitySportId: string): string => {
    const fs = facilitySports.find((f) => f.id === facilitySportId);
    if (!fs) return "Sport";
    return fs.customSportName ?? sports.find((s) => s.id === fs.sportId)?.name ?? "Sport";
  };

  return areas
    .filter((a) => !a.archived)
    .map((a) => ({ id: a.id, name: a.name, facilitySportId: a.facilitySportId, sportName: sportName(a.facilitySportId) }))
    .sort((a, b) => a.name.localeCompare(b.name));
}
