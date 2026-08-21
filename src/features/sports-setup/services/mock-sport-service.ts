import { AVAILABLE_SPORTS } from "@/features/sports-setup/constants";
import type { FacilitySport, FacilitySportInput, Sport } from "@/features/sports-setup/types";

const STORAGE_KEY = "turf.facility-sports.mock.v1";

function readAll(): FacilitySport[] {
  if (typeof window === "undefined") return [];
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    return raw ? (JSON.parse(raw) as FacilitySport[]) : [];
  } catch {
    return [];
  }
}

function writeAll(rows: FacilitySport[]): void {
  window.localStorage.setItem(STORAGE_KEY, JSON.stringify(rows));
}

function replaceForFacility(facilityId: string, inputs: FacilitySportInput[]): FacilitySport[] {
  const now = new Date().toISOString();
  const newRows: FacilitySport[] = inputs.map((input) => ({
    ...input,
    id: crypto.randomUUID(),
    createdAt: now,
    updatedAt: now,
  }));

  const others = readAll().filter((row) => row.facilityId !== facilityId);
  writeAll([...others, ...newRows]);
  return newRows;
}

export const MockSportService = {
  async getAvailableSports(): Promise<Sport[]> {
    return AVAILABLE_SPORTS.filter((sport) => sport.isActive);
  },

  async getFacilitySports(facilityId: string): Promise<FacilitySport[]> {
    return readAll().filter((row) => row.facilityId === facilityId);
  },

  async saveFacilitySports(facilityId: string, sports: FacilitySportInput[]): Promise<FacilitySport[]> {
    return replaceForFacility(facilityId, sports);
  },

  async updateFacilitySports(facilityId: string, sports: FacilitySportInput[]): Promise<FacilitySport[]> {
    return replaceForFacility(facilityId, sports);
  },
};