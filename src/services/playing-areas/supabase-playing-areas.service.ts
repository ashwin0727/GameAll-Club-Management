"use client";

import type { SupabaseClient } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";
import type { PlayingArea, PlayingAreaInput } from "@/features/courts-setup/types";
import type { PlayingAreasService } from "@/services/playing-areas/playing-areas.service";
import { ServiceError, mapSupabaseError } from "@/services/shared/service-error";
import type { Database } from "@/types/database.types";

type CourtRow = Database["public"]["Tables"]["courts"]["Row"];

function toPlayingArea(row: CourtRow): PlayingArea {
  return {
    id: row.id,
    facilityId: row.facility_id,
    facilitySportId: row.facility_sport_id,
    sportId: row.sport_id,
    name: row.name,
    type: row.area_type,
    status: row.status,
    bookingEnabled: row.booking_enabled,
    archived: row.archived,
    displayOrder: row.display_order,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

export class SupabasePlayingAreasService implements PlayingAreasService {
  private readonly supabase: SupabaseClient<Database>;

  constructor(client?: SupabaseClient<Database>) {
    this.supabase = client ?? createClient();
  }

  async getPlayingAreas(facilityId: string): Promise<PlayingArea[]> {
    const { data, error } = await this.supabase
      .from("courts")
      .select("*")
      .eq("facility_id", facilityId)
      .eq("archived", false)
      .order("display_order", { ascending: true });

    if (error) throw mapSupabaseError(error);
    return (data ?? []).map(toPlayingArea);
  }

  async getPlayingAreasByFacilitySport(facilitySportId: string): Promise<PlayingArea[]> {
    const { data, error } = await this.supabase
      .from("courts")
      .select("*")
      .eq("facility_sport_id", facilitySportId)
      .eq("archived", false)
      .order("display_order", { ascending: true });

    if (error) throw mapSupabaseError(error);
    return (data ?? []).map(toPlayingArea);
  }

  async createPlayingArea(input: PlayingAreaInput): Promise<PlayingArea> {
    const { data, error } = await this.supabase
      .from("courts")
      .insert({
        id: input.id,
        facility_id: input.facilityId,
        facility_sport_id: input.facilitySportId,
        sport_id: input.sportId,
        name: input.name,
        area_type: input.type,
        status: input.status,
        booking_enabled: input.bookingEnabled,
        archived: input.archived,
        display_order: input.displayOrder,
      })
      .select("*")
      .single();

    if (error) {
      throw mapSupabaseError(error, {
        duplicate: "DUPLICATE_PLAYING_AREA",
        notFound: "FACILITY_SPORT_NOT_FOUND",
        invalid: "INVALID_PLAYING_AREA",
      });
    }
    return toPlayingArea(data);
  }

  async updatePlayingArea(id: string, patch: Partial<Omit<PlayingAreaInput, "id">>): Promise<PlayingArea> {
    const update: Database["public"]["Tables"]["courts"]["Update"] = {};
    if (patch.name !== undefined) update.name = patch.name;
    if (patch.type !== undefined) update.area_type = patch.type;
    if (patch.status !== undefined) update.status = patch.status;
    if (patch.bookingEnabled !== undefined) update.booking_enabled = patch.bookingEnabled;
    if (patch.displayOrder !== undefined) update.display_order = patch.displayOrder;
    if (patch.archived !== undefined) update.archived = patch.archived;

    const { data, error } = await this.supabase
      .from("courts")
      .update(update)
      .eq("id", id)
      .select("*")
      .maybeSingle();

    if (error) {
      throw mapSupabaseError(error, { duplicate: "DUPLICATE_PLAYING_AREA", invalid: "INVALID_PLAYING_AREA" });
    }
    if (!data) throw new ServiceError("PLAYING_AREA_NOT_FOUND");
    return toPlayingArea(data);
  }

  async removePlayingArea(id: string): Promise<void> {
    const { error } = await this.supabase.from("courts").update({ archived: true }).eq("id", id);
    if (error) throw mapSupabaseError(error);
  }

  async restorePlayingArea(id: string): Promise<PlayingArea> {
    const { data, error } = await this.supabase
      .from("courts")
      .update({ archived: false })
      .eq("id", id)
      .select("*")
      .maybeSingle();

    if (error) throw mapSupabaseError(error, { duplicate: "DUPLICATE_PLAYING_AREA" });
    if (!data) throw new ServiceError("PLAYING_AREA_NOT_FOUND");
    return toPlayingArea(data);
  }

  async reorderPlayingAreas(facilitySportId: string, orderedIds: string[]): Promise<void> {
    await Promise.all(
      orderedIds.map((id, index) =>
        this.supabase.from("courts").update({ display_order: index }).eq("id", id).eq("facility_sport_id", facilitySportId),
      ),
    );
  }
}