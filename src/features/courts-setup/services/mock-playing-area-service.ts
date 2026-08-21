import type { PlayingArea, PlayingAreaInput } from "@/features/courts-setup/types";

const STORAGE_KEY = "turf.playing-areas.mock.v1";

function readAll(): PlayingArea[] {
  if (typeof window === "undefined") return [];
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    return raw ? (JSON.parse(raw) as PlayingArea[]) : [];
  } catch {
    return [];
  }
}

function writeAll(rows: PlayingArea[]): void {
  window.localStorage.setItem(STORAGE_KEY, JSON.stringify(rows));
}

export const MockPlayingAreaService = {
  async getPlayingAreas(facilityId: string): Promise<PlayingArea[]> {
    return readAll().filter((row) => row.facilityId === facilityId && !row.archived);
  },

  async getPlayingAreasByFacilitySport(facilitySportId: string): Promise<PlayingArea[]> {
    return readAll().filter((row) => row.facilitySportId === facilitySportId && !row.archived);
  },

  async createPlayingArea(input: PlayingAreaInput): Promise<PlayingArea> {
    const now = new Date().toISOString();
    const created: PlayingArea = {
      ...input,
      id: crypto.randomUUID(),
      createdAt: now,
      updatedAt: now,
    };
    writeAll([...readAll(), created]);
    return created;
  },

  async updatePlayingArea(id: string, patch: Partial<PlayingAreaInput>): Promise<PlayingArea> {
    const rows = readAll();
    const index = rows.findIndex((row) => row.id === id);
    const existing = rows[index];
    if (index === -1 || !existing) throw new Error("Playing area not found");

    const updated: PlayingArea = {
      ...existing,
      ...patch,
      updatedAt: new Date().toISOString(),
    };
    rows[index] = updated;
    writeAll(rows);
    return updated;
  },

  /** Soft delete — never removes the row, so history survives for future reporting. */
  async removePlayingArea(id: string): Promise<void> {
    const rows = readAll();
    const index = rows.findIndex((row) => row.id === id);
    const existing = rows[index];
    if (index === -1 || !existing) return;

    rows[index] = { ...existing, archived: true, updatedAt: new Date().toISOString() };
    writeAll(rows);
  },
};