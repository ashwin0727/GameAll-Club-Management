import type { PlayingArea, PlayingAreaInput } from "@/features/courts-setup/types";

/**
 * The playing-areas boundary the UI codes against ("courts" in the DB —
 * see supabase/migrations/0002_onboarding_backend.sql for why the table
 * wasn't renamed). Ownership and facility_sport/sport consistency are
 * enforced at the database layer (RLS + a trigger), not duplicated here.
 */
export interface PlayingAreasService {
  getPlayingAreas(facilityId: string): Promise<PlayingArea[]>;
  getPlayingAreasByFacilitySport(facilitySportId: string): Promise<PlayingArea[]>;
  createPlayingArea(input: PlayingAreaInput): Promise<PlayingArea>;
  updatePlayingArea(id: string, patch: Partial<Omit<PlayingAreaInput, "id">>): Promise<PlayingArea>;
  /** Soft delete — never removes the row, so history survives for future reporting. */
  removePlayingArea(id: string): Promise<void>;
  restorePlayingArea(id: string): Promise<PlayingArea>;
  reorderPlayingAreas(facilitySportId: string, orderedIds: string[]): Promise<void>;
}