"use client";

import type { SupabaseClient } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";
import { sortTimeSlots, validateSchedule } from "@/features/operating-hours/validation";
import type { OperatingDay, OperatingSchedule } from "@/features/operating-hours/types";
import type { OperatingHoursService } from "@/services/operating-hours/operating-hours.service";
import { ServiceError, mapSupabaseError } from "@/services/shared/service-error";
import type { Database } from "@/types/database.types";

type ScheduleRow = Database["public"]["Tables"]["operating_schedules"]["Row"];
type DayRow = Database["public"]["Tables"]["operating_days"]["Row"];
type SlotRow = Database["public"]["Tables"]["operating_time_slots"]["Row"];
type ScheduleWithDays = ScheduleRow & { operating_days: (DayRow & { operating_time_slots: SlotRow[] })[] };

const SCHEDULE_SELECT = "*, operating_days(*, operating_time_slots(*))";

function toSchedule(row: ScheduleWithDays): OperatingSchedule {
  const days: OperatingDay[] = row.operating_days.map((day) => ({
    dayOfWeek: day.day_of_week as OperatingDay["dayOfWeek"],
    isClosed: day.is_closed,
    is24Hours: day.is_24_hours,
    slots: sortTimeSlots(
      day.operating_time_slots.map((slot) => ({
        startTime: slot.start_time.slice(0, 5),
        endTime: slot.end_time.slice(0, 5),
        crossesMidnight: slot.crosses_midnight,
        displayOrder: slot.display_order,
      })),
    ),
  }));

  return {
    id: row.id,
    facilityId: row.facility_id,
    scopeType: row.scope_type,
    playingAreaId: row.playing_area_id ?? undefined,
    timezone: row.timezone,
    days,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function toDaysPayload(days: OperatingDay[]) {
  return days.map((day) => ({
    dayOfWeek: day.dayOfWeek,
    isClosed: day.isClosed,
    is24Hours: day.is24Hours,
    slots: day.isClosed || day.is24Hours
      ? []
      : day.slots.map((slot, index) => ({
          startTime: slot.startTime,
          endTime: slot.endTime,
          crossesMidnight: slot.crossesMidnight,
          displayOrder: index,
        })),
  }));
}

export class SupabaseOperatingHoursService implements OperatingHoursService {
  private readonly supabase: SupabaseClient<Database>;

  constructor(client?: SupabaseClient<Database>) {
    this.supabase = client ?? createClient();
  }

  async getFacilitySchedule(facilityId: string): Promise<OperatingSchedule | null> {
    const { data, error } = await this.supabase
      .from("operating_schedules")
      .select(SCHEDULE_SELECT)
      .eq("facility_id", facilityId)
      .eq("scope_type", "FACILITY")
      .maybeSingle();

    if (error) throw mapSupabaseError(error);
    return data ? toSchedule(data as unknown as ScheduleWithDays) : null;
  }

  async saveFacilitySchedule(facilityId: string, days: OperatingDay[]): Promise<OperatingSchedule> {
    const result = validateSchedule(days);
    if (!result.isValid) throw new ServiceError("INVALID_PLAYING_AREA", "Operating hours cannot overlap.");

    const { data, error } = await this.supabase.rpc("save_operating_schedule", {
      p_facility_id: facilityId,
      p_scope_type: "FACILITY",
      p_playing_area_id: null,
      p_days: toDaysPayload(days),
    });

    if (error) throw mapSupabaseError(error);
    if (!data) throw new ServiceError("DATABASE_ERROR");

    const schedule = await this.getFacilitySchedule(facilityId);
    if (!schedule) throw new ServiceError("DATABASE_ERROR");
    return schedule;
  }

  async getPlayingAreaSchedule(playingAreaId: string): Promise<OperatingSchedule | null> {
    const { data, error } = await this.supabase
      .from("operating_schedules")
      .select(SCHEDULE_SELECT)
      .eq("playing_area_id", playingAreaId)
      .eq("scope_type", "PLAYING_AREA")
      .maybeSingle();

    if (error) throw mapSupabaseError(error);
    return data ? toSchedule(data as unknown as ScheduleWithDays) : null;
  }

  async savePlayingAreaSchedule(
    playingAreaId: string,
    facilityId: string,
    days: OperatingDay[],
  ): Promise<OperatingSchedule> {
    const result = validateSchedule(days);
    if (!result.isValid) throw new ServiceError("INVALID_PLAYING_AREA", "Operating hours cannot overlap.");

    const { data, error } = await this.supabase.rpc("save_operating_schedule", {
      p_facility_id: facilityId,
      p_scope_type: "PLAYING_AREA",
      p_playing_area_id: playingAreaId,
      p_days: toDaysPayload(days),
    });

    if (error) throw mapSupabaseError(error, { notFound: "PLAYING_AREA_NOT_FOUND" });
    if (!data) throw new ServiceError("DATABASE_ERROR");

    const schedule = await this.getPlayingAreaSchedule(playingAreaId);
    if (!schedule) throw new ServiceError("DATABASE_ERROR");
    return schedule;
  }

  async deletePlayingAreaOverride(playingAreaId: string): Promise<void> {
    const { error } = await this.supabase.rpc("delete_playing_area_override", {
      p_playing_area_id: playingAreaId,
    });
    if (error) throw mapSupabaseError(error);
  }

  validateSchedule(days: OperatingDay[]) {
    return validateSchedule(days);
  }
}