import type { Facility } from "@/features/onboarding/types";
import type { Sport, FacilitySport } from "@/features/sports-setup/types";
import type { PlayingArea } from "@/features/courts-setup/types";
import type { FacilityService } from "@/services/facility/facility.service";
import type { SportsService } from "@/services/sports/sports.service";
import type { PlayingAreasService } from "@/services/playing-areas/playing-areas.service";
import { setFacilityService } from "@/services/facility";
import { setSportsService } from "@/services/sports";
import { setPlayingAreasService } from "@/services/playing-areas";

/**
 * Deterministic filter-bar fixture: N facilities, three sports (fs-1..fs-3),
 * four courts (two under fs-1). Every id is stable so tests can assert on it.
 */
export function installFakeReportsFilterDeps(opts: { facilities?: number } = {}) {
  const count = opts.facilities ?? 1;
  const facilities = Array.from(
    { length: count },
    (_, i) => ({ id: `fac-${i + 1}`, name: `Facility ${i + 1}` }) as Facility,
  );

  setFacilityService({
    getFacility: async () => facilities[0] ?? null,
    getFacilities: async () => facilities,
    createFacility: async () => facilities[0]!,
    updateFacility: async () => facilities[0]!,
    updateOnboardingStep: async () => {},
  } as FacilityService);

  const activeSports: Sport[] = [
    { id: "sport-badminton", name: "Badminton", code: "badminton", icon: "B", description: "", isActive: true },
    { id: "sport-football", name: "Football", code: "football", icon: "F", description: "", isActive: true },
    { id: "sport-tennis", name: "Tennis", code: "tennis", icon: "T", description: "", isActive: true },
  ];
  const facilitySports: FacilitySport[] = [
    { id: "fs-1", facilityId: "fac-1", sportId: "sport-badminton", enabled: true, createdAt: "", updatedAt: "" },
    { id: "fs-2", facilityId: "fac-1", sportId: "sport-football", enabled: true, createdAt: "", updatedAt: "" },
    { id: "fs-3", facilityId: "fac-1", sportId: "sport-tennis", enabled: true, createdAt: "", updatedAt: "" },
  ];
  setSportsService({
    getActiveSports: async () => activeSports,
    getFacilitySports: async () => facilitySports,
    saveFacilitySports: async () => facilitySports,
    updateFacilitySports: async () => facilitySports,
  } as SportsService);

  const court = (
    id: string,
    name: string,
    facilitySportId: string,
    sportId: string,
  ): PlayingArea => ({
    id,
    facilityId: "fac-1",
    facilitySportId,
    sportId,
    name,
    type: "INDOOR",
    status: "ACTIVE",
    bookingEnabled: true,
    archived: false,
    displayOrder: 0,
    createdAt: "",
    updatedAt: "",
  });
  const courts: PlayingArea[] = [
    court("court-1", "Court 1", "fs-1", "sport-badminton"),
    court("court-2", "Court 2", "fs-1", "sport-badminton"),
    court("court-3", "Turf A", "fs-2", "sport-football"),
    court("court-4", "Tennis 1", "fs-3", "sport-tennis"),
  ];
  setPlayingAreasService({
    getPlayingAreas: async () => courts,
    getPlayingAreasByFacilitySport: async (fsId: string) =>
      courts.filter((c) => c.facilitySportId === fsId),
    createPlayingArea: async () => courts[0]!,
    updatePlayingArea: async () => courts[0]!,
    removePlayingArea: async () => {},
    restorePlayingArea: async () => courts[0]!,
    reorderPlayingAreas: async () => {},
  } as PlayingAreasService);

  return { facilities, activeSports, facilitySports, courts };
}
