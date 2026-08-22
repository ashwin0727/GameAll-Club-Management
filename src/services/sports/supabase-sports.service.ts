"use client";

import type { SupabaseClient } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";
import { presentSport } from "@/features/sports-setup/constants";
import type { FacilitySport, FacilitySportInput, Sport } from "@/features/sports-setup/types";
import type { SportsService } from "@/services/sports/sports.service";
import { ServiceError, mapSupabaseError } from "@/services/shared/service-error";
import type { Database } from "@/types/database.types";

type FacilitySportRow = Database["public"]["Tables"]["facility_sports"]["Row"];

function toFacilitySport(row: FacilitySportRow): FacilitySport {
  return {
    id: row.id,
    facilityId: row.facility_id,
    sportId: row.sport_id,
    enabled: row.is_active,
    customSportName: row.custom_sport_name ?? undefined,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

export class SupabaseSportsService implements SportsService {
  private readonly supabase: SupabaseClient<Database>;

  constructor(client?: SupabaseClient<Database>) {
    this.supabase = client ?? createClient();
  }

  async getActiveSports(): Promise<Sport[]> {
    const { data, error } = await this.supabase
      .from("sports")
      .select("id, key, name, is_active, sort_order")
      .eq("is_active", true)
      .order("sort_order", { ascending: true });

    if (error) throw mapSupabaseError(error);
    return (data ?? []).map(presentSport);
  }

  async getFacilitySports(facilityId: string): Promise<FacilitySport[]> {
    const { data, error } = await this.supabase
      .from("facility_sports")
      .select("*")
      .eq("facility_id", facilityId)
      .eq("is_active", true);

    if (error) throw mapSupabaseError(error);
    return (data ?? []).map(toFacilitySport);
  }

  async saveFacilitySports(facilityId: string, sports: FacilitySportInput[]): Promise<FacilitySport[]> {
    const customSportName = sports.find((s) => s.customSportName)?.customSportName ?? null;

    const { data, error } = await this.supabase.rpc("sync_facility_sports", {
      p_facility_id: facilityId,
      p_sport_ids: sports.map((s) => s.sportId),
      p_custom_sport_name: customSportName,
    });

    if (error) throw mapSupabaseError(error, { duplicate: "DUPLICATE_FACILITY_SPORT" });
    if (!data) throw new ServiceError("DATABASE_ERROR");
    return data.map(toFacilitySport);
  }

  async updateFacilitySports(facilityId: string, sports: FacilitySportInput[]): Promise<FacilitySport[]> {
    return this.saveFacilitySports(facilityId, sports);
  }
}