"use client";

import type { SupabaseClient } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";
import type { Facility, FacilityInput } from "@/features/onboarding/types";
import type { FacilityService, OnboardingStep } from "@/services/facility/facility.service";
import { ServiceError, mapSupabaseError } from "@/services/shared/service-error";
import type { Database } from "@/types/database.types";

type FacilityRow = Database["public"]["Tables"]["facilities"]["Row"];

function toFacility(row: FacilityRow): Facility {
  return {
    id: row.id,
    ownerId: row.owner_id,
    name: row.name,
    type: row.facility_type,
    customType: row.custom_facility_type ?? undefined,
    businessEmail: row.business_email,
    businessPhone: row.business_phone,
    address: {
      line1: row.address_line_1,
      area: row.area,
      city: row.city ?? "",
      state: row.state,
      country: "India",
      pinCode: row.postal_code,
    },
    logoUrl: row.logo_url ?? undefined,
    description: row.description ?? undefined,
    status: row.status,
    onboardingStep: row.onboarding_step,
    onboardingCompletedAt: row.onboarding_completed_at ?? undefined,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    membershipAccessDays: row.membership_access_days ?? [0, 1, 2, 3, 4, 5, 6],
  };
}

export class SupabaseFacilityService implements FacilityService {
  private readonly supabase: SupabaseClient<Database>;

  constructor(client?: SupabaseClient<Database>) {
    this.supabase = client ?? createClient();
  }

  async createFacility(input: FacilityInput): Promise<Facility> {
    const { data, error } = await this.supabase.rpc("create_facility_with_owner", {
      p_name: input.name,
      p_facility_type: input.type,
      p_custom_facility_type: input.type === "OTHER" ? (input.customType ?? null) : null,
      p_business_email: input.businessEmail,
      p_business_phone: input.businessPhone,
      p_address_line_1: input.address.line1,
      p_address_line_2: null,
      p_area: input.address.area,
      p_city: input.address.city,
      p_state: input.address.state,
      p_country: input.address.country,
      p_postal_code: input.address.pinCode,
      p_latitude: null,
      p_longitude: null,
      p_timezone: "Asia/Kolkata",
      p_logo_url: input.logoUrl ?? null,
      p_description: input.description ?? null,
    });

    if (error) throw mapSupabaseError(error);
    if (!data) throw new ServiceError("DATABASE_ERROR");
    return toFacility(data);
  }

  async getFacility(): Promise<Facility | null> {
    const {
      data: { user },
    } = await this.supabase.auth.getUser();
    if (!user) throw new ServiceError("UNAUTHENTICATED");

    const { data, error } = await this.supabase
      .from("facilities")
      .select("*")
      .eq("owner_id", user.id)
      .order("created_at", { ascending: true })
      .limit(1)
      .maybeSingle();

    if (error) throw mapSupabaseError(error);
    return data ? toFacility(data) : null;
  }

  async getFacilities(): Promise<Facility[]> {
    const {
      data: { user },
    } = await this.supabase.auth.getUser();
    if (!user) throw new ServiceError("UNAUTHENTICATED");

    const { data, error } = await this.supabase
      .from("facilities")
      .select("*")
      .order("created_at", { ascending: true });

    if (error) throw mapSupabaseError(error);
    return (data ?? []).map(toFacility);
  }

  async updateFacility(id: string, patch: Partial<FacilityInput>): Promise<Facility> {
    const update: Database["public"]["Tables"]["facilities"]["Update"] = {};
    if (patch.name !== undefined) update.name = patch.name;
    if (patch.type !== undefined) update.facility_type = patch.type;
    if (patch.customType !== undefined) update.custom_facility_type = patch.customType ?? null;
    if (patch.businessEmail !== undefined) update.business_email = patch.businessEmail;
    if (patch.businessPhone !== undefined) update.business_phone = patch.businessPhone;
    if (patch.address) {
      update.address_line_1 = patch.address.line1;
      update.area = patch.address.area;
      update.city = patch.address.city;
      update.state = patch.address.state;
      update.postal_code = patch.address.pinCode;
    }
    if (patch.logoUrl !== undefined) update.logo_url = patch.logoUrl ?? null;
    if (patch.description !== undefined) update.description = patch.description ?? null;
    if (patch.status !== undefined) update.status = patch.status;

    const { data, error } = await this.supabase
      .from("facilities")
      // id/owner_id are never part of `update` above — the frontend cannot
      // change either regardless of what patch it supplies.
      .update(update)
      .eq("id", id)
      .select("*")
      .maybeSingle();

    if (error) throw mapSupabaseError(error);
    if (!data) throw new ServiceError("FACILITY_NOT_FOUND");
    return toFacility(data);
  }

  async updateOnboardingStep(facilityId: string, step: OnboardingStep): Promise<void> {
    const { error } = await this.supabase
      .from("facilities")
      .update({ onboarding_step: step })
      .eq("id", facilityId);

    if (error) throw mapSupabaseError(error);
  }
}