import { presentSport } from "@/features/sports-setup/constants";
import type { FacilitySport, FacilitySportInput, Sport } from "@/features/sports-setup/types";
import type { SportsService } from "@/services/sports/sports.service";
import { setSportsService } from "@/services/sports";

const CATALOG = [
  { id: "sport-badminton", key: "badminton", name: "Badminton", is_active: true },
  { id: "sport-pickleball", key: "pickleball", name: "Pickleball", is_active: true },
  { id: "sport-cricket", key: "cricket", name: "Cricket", is_active: true },
  { id: "sport-football", key: "football", name: "Football", is_active: true },
  { id: "sport-tennis", key: "tennis", name: "Tennis", is_active: true },
  { id: "sport-other", key: "other", name: "Other", is_active: true },
];

/** In-memory stand-in for SupabaseSportsService — the sport catalog is fixed, matching what the real seed produces. */
export class FakeSportsService implements SportsService {
  private rows: FacilitySport[] = [];

  async getActiveSports(): Promise<Sport[]> {
    return CATALOG.map(presentSport);
  }

  async getFacilitySports(facilityId: string): Promise<FacilitySport[]> {
    return this.rows.filter((row) => row.facilityId === facilityId && row.enabled);
  }

  async saveFacilitySports(facilityId: string, inputs: FacilitySportInput[]): Promise<FacilitySport[]> {
    const now = new Date().toISOString();
    // Preserve id/createdAt for a sport that was already selected, exactly
    // like the real sync_facility_sports RPC — otherwise a redundant re-save
    // would orphan any playing area that already references the old id.
    const existingForFacility = this.rows.filter((row) => row.facilityId === facilityId);

    const nextRows: FacilitySport[] = inputs.map((input) => {
      const existing = existingForFacility.find((row) => row.sportId === input.sportId);
      if (existing) {
        return { ...existing, ...input, id: existing.id, createdAt: existing.createdAt, updatedAt: now, enabled: true };
      }
      return { ...input, id: crypto.randomUUID(), createdAt: now, updatedAt: now, enabled: true };
    });

    const selectedSportIds = new Set(inputs.map((i) => i.sportId));
    const deactivated = existingForFacility
      .filter((row) => !selectedSportIds.has(row.sportId))
      .map((row) => ({ ...row, enabled: false, updatedAt: now }));

    const others = this.rows.filter((row) => row.facilityId !== facilityId);
    this.rows = [...others, ...nextRows, ...deactivated];
    return nextRows;
  }

  async updateFacilitySports(facilityId: string, inputs: FacilitySportInput[]): Promise<FacilitySport[]> {
    return this.saveFacilitySports(facilityId, inputs);
  }
}

/** Test seam: builds a fake, injects it via setSportsService, returns it for assertions/overrides. */
export function installFakeSportsService(): FakeSportsService {
  const service = new FakeSportsService();
  setSportsService(service);
  return service;
}