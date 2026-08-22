import type { PlayingArea, PlayingAreaInput } from "@/features/courts-setup/types";
import type { PlayingAreasService } from "@/services/playing-areas/playing-areas.service";
import { setPlayingAreasService } from "@/services/playing-areas";

/** In-memory stand-in for SupabasePlayingAreasService. */
export class FakePlayingAreasService implements PlayingAreasService {
  rows: PlayingArea[] = [];

  async getPlayingAreas(facilityId: string): Promise<PlayingArea[]> {
    return this.rows.filter((row) => row.facilityId === facilityId && !row.archived);
  }

  async getPlayingAreasByFacilitySport(facilitySportId: string): Promise<PlayingArea[]> {
    return this.rows.filter((row) => row.facilitySportId === facilitySportId && !row.archived);
  }

  async createPlayingArea(input: PlayingAreaInput): Promise<PlayingArea> {
    const now = new Date().toISOString();
    const created: PlayingArea = { ...input, createdAt: now, updatedAt: now };
    this.rows.push(created);
    return created;
  }

  async updatePlayingArea(id: string, patch: Partial<Omit<PlayingAreaInput, "id">>): Promise<PlayingArea> {
    const index = this.rows.findIndex((row) => row.id === id);
    const existing = this.rows[index];
    if (index === -1 || !existing) throw new Error("Playing area not found");
    const updated: PlayingArea = { ...existing, ...patch, updatedAt: new Date().toISOString() };
    this.rows[index] = updated;
    return updated;
  }

  async removePlayingArea(id: string): Promise<void> {
    const index = this.rows.findIndex((row) => row.id === id);
    const existing = this.rows[index];
    if (index === -1 || !existing) return;
    this.rows[index] = { ...existing, archived: true, updatedAt: new Date().toISOString() };
  }

  async restorePlayingArea(id: string): Promise<PlayingArea> {
    const index = this.rows.findIndex((row) => row.id === id);
    const existing = this.rows[index];
    if (index === -1 || !existing) throw new Error("Playing area not found");
    const updated: PlayingArea = { ...existing, archived: false, updatedAt: new Date().toISOString() };
    this.rows[index] = updated;
    return updated;
  }

  async reorderPlayingAreas(facilitySportId: string, orderedIds: string[]): Promise<void> {
    orderedIds.forEach((id, index) => {
      const row = this.rows.find((r) => r.id === id && r.facilitySportId === facilitySportId);
      if (row) row.displayOrder = index;
    });
  }
}

/** Test seam: builds a fake, injects it via setPlayingAreasService, returns it for assertions/overrides. */
export function installFakePlayingAreasService(): FakePlayingAreasService {
  const service = new FakePlayingAreasService();
  setPlayingAreasService(service);
  return service;
}