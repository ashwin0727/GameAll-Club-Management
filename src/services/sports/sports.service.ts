import type { FacilitySport, FacilitySportInput, Sport } from "@/features/sports-setup/types";

/**
 * The sports boundary the UI codes against. Sports are global reference
 * data (read-only from the client); facility_sports is the per-facility
 * selection, owned and validated against facility membership.
 */
export interface SportsService {
  getActiveSports(): Promise<Sport[]>;
  getFacilitySports(facilityId: string): Promise<FacilitySport[]>;
  /** Replaces the facility's full sport selection — deselected sports are deactivated, not deleted. */
  saveFacilitySports(facilityId: string, sports: FacilitySportInput[]): Promise<FacilitySport[]>;
  updateFacilitySports(facilityId: string, sports: FacilitySportInput[]): Promise<FacilitySport[]>;
}