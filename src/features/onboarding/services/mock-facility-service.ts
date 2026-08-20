import type { Facility, FacilityInput } from "@/features/onboarding/types";

const STORAGE_KEY = "turf.facility.mock.v1";

function readAll(): Facility[] {
  if (typeof window === "undefined") return [];
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    return raw ? (JSON.parse(raw) as Facility[]) : [];
  } catch {
    return [];
  }
}

function writeAll(facilities: Facility[]): void {
  window.localStorage.setItem(STORAGE_KEY, JSON.stringify(facilities));
}

export const MockFacilityService = {
  async saveFacility(input: FacilityInput): Promise<Facility> {
    const now = new Date().toISOString();
    const facility: Facility = {
      ...input,
      id: crypto.randomUUID(),
      status: input.status ?? "ACTIVE",
      createdAt: now,
      updatedAt: now,
    };

    const facilities = readAll().filter((f) => f.ownerId !== input.ownerId);
    writeAll([...facilities, facility]);
    return facility;
  },

  async getFacility(ownerId: string): Promise<Facility | null> {
    return readAll().find((f) => f.ownerId === ownerId) ?? null;
  },

  async updateFacility(id: string, patch: Partial<FacilityInput>): Promise<Facility> {
    const facilities = readAll();
    const index = facilities.findIndex((f) => f.id === id);
    if (index === -1) throw new Error("Facility not found");

    const facility = facilities[index];
    const updated = {
      ...facility,
      ...patch,
      updatedAt: new Date().toISOString(),
    } as Facility;
    facilities[index] = updated;
    writeAll(facilities);
    return updated;
  },
};
