/** 0=Sunday .. 6=Saturday, matching JS Date#getDay(). */
export type DayOfWeek = 0 | 1 | 2 | 3 | 4 | 5 | 6;

export const DAYS_OF_WEEK: DayOfWeek[] = [0, 1, 2, 3, 4, 5, 6];

export const DAY_LABELS: Record<DayOfWeek, string> = {
  0: "Sunday",
  1: "Monday",
  2: "Tuesday",
  3: "Wednesday",
  4: "Thursday",
  5: "Friday",
  6: "Saturday",
};

/** Persisted as "HH:MM" (24-hour, zero-padded) — never a display string. */
export interface OperatingTimeSlot {
  startTime: string;
  endTime: string;
  crossesMidnight: boolean;
  displayOrder: number;
}

export interface OperatingDay {
  dayOfWeek: DayOfWeek;
  isClosed: boolean;
  is24Hours: boolean;
  slots: OperatingTimeSlot[];
}

export type ScopeType = "FACILITY" | "PLAYING_AREA";

export interface OperatingSchedule {
  id: string;
  facilityId: string;
  scopeType: ScopeType;
  playingAreaId?: string;
  timezone: string;
  days: OperatingDay[];
  createdAt: string;
  updatedAt: string;
}

/** What saveFacilitySchedule/savePlayingAreaSchedule take — no id/timestamps, those are server-assigned. */
export type OperatingScheduleInput = Pick<OperatingSchedule, "days">;