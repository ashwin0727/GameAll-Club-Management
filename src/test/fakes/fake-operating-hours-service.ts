import type { FacilityClosure, OperatingDay, OperatingSchedule } from "@/features/operating-hours/types";
import { validateSchedule } from "@/features/operating-hours/validation";
import type { OperatingHoursService } from "@/services/operating-hours/operating-hours.service";
import { setOperatingHoursService } from "@/services/operating-hours";

/** In-memory stand-in for SupabaseOperatingHoursService. */
export class FakeOperatingHoursService implements OperatingHoursService {
  facilitySchedules = new Map<string, OperatingSchedule>();
  areaSchedules = new Map<string, OperatingSchedule>();
  closures = new Map<string, FacilityClosure[]>();
  deletedOverrides: string[] = [];

  private build(facilityId: string, days: OperatingDay[], scope: "FACILITY" | "PLAYING_AREA", areaId?: string): OperatingSchedule {
    const now = new Date().toISOString();
    return { id: crypto.randomUUID(), facilityId, scopeType: scope, playingAreaId: areaId, timezone: "Asia/Kolkata", days, createdAt: now, updatedAt: now };
  }

  async getFacilitySchedule(facilityId: string) {
    return this.facilitySchedules.get(facilityId) ?? null;
  }

  async saveFacilitySchedule(facilityId: string, days: OperatingDay[]) {
    const schedule = this.build(facilityId, days, "FACILITY");
    this.facilitySchedules.set(facilityId, schedule);
    return schedule;
  }

  async getPlayingAreaSchedule(playingAreaId: string) {
    return this.areaSchedules.get(playingAreaId) ?? null;
  }

  async savePlayingAreaSchedule(playingAreaId: string, facilityId: string, days: OperatingDay[]) {
    const schedule = this.build(facilityId, days, "PLAYING_AREA", playingAreaId);
    this.areaSchedules.set(playingAreaId, schedule);
    return schedule;
  }

  async deletePlayingAreaOverride(playingAreaId: string) {
    this.areaSchedules.delete(playingAreaId);
    this.deletedOverrides.push(playingAreaId);
  }

  validateSchedule(days: OperatingDay[]) {
    return validateSchedule(days);
  }

  async getClosures(facilityId: string) {
    return [...(this.closures.get(facilityId) ?? [])].sort((a, b) => a.date.localeCompare(b.date));
  }

  async replaceClosures(facilityId: string, closures: FacilityClosure[]) {
    this.closures.set(
      facilityId,
      closures.map((c) => ({ id: c.id ?? crypto.randomUUID(), date: c.date, name: c.name.trim() })),
    );
    return this.getClosures(facilityId);
  }
}

/** Test seam: builds a fake, injects it via setOperatingHoursService, returns it for assertions. */
export function installFakeOperatingHoursService(): FakeOperatingHoursService {
  const service = new FakeOperatingHoursService();
  setOperatingHoursService(service);
  return service;
}
