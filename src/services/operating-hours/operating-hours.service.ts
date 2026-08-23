import type { OperatingDay, OperatingSchedule } from "@/features/operating-hours/types";
import type { ScheduleValidationResult } from "@/features/operating-hours/validation";

/**
 * The operating-hours boundary the UI codes against. A facility schedule
 * always exists once saved; a playing-area schedule only exists when the
 * owner has customized that area (absence means "inherits facility hours").
 */
export interface OperatingHoursService {
  getFacilitySchedule(facilityId: string): Promise<OperatingSchedule | null>;
  saveFacilitySchedule(facilityId: string, days: OperatingDay[]): Promise<OperatingSchedule>;
  getPlayingAreaSchedule(playingAreaId: string): Promise<OperatingSchedule | null>;
  savePlayingAreaSchedule(
    playingAreaId: string,
    facilityId: string,
    days: OperatingDay[],
  ): Promise<OperatingSchedule>;
  deletePlayingAreaOverride(playingAreaId: string): Promise<void>;
  validateSchedule(days: OperatingDay[]): ScheduleValidationResult;
}