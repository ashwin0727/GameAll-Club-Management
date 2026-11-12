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
    locationUrl: row.location_url ?? undefined,
    locationVerification: { status: row.location_verification_status ?? "PENDING", note: row.location_verification_note ?? undefined },
    venueType: row.venue_type ?? undefined,
    amenities: {
      parking: row.has_parking ?? false,
      changingRooms: row.has_changing_rooms ?? false,
      toilets: row.has_toilets ?? false,
      cafeteria: row.has_cafeteria ?? false,
      equipmentRental: row.has_equipment_rental ?? false,
    },
    ownershipType: row.ownership_type ?? "OWNED",
    whatsappNumber: row.whatsapp_number ?? undefined,
    contactPerson: row.contact_person_name
      ? { name: row.contact_person_name, role: row.contact_person_role ?? "", alternatePhone: row.contact_person_alt_phone ?? undefined }
      : undefined,
    policies: {
      allowOnlineBooking: row.allow_online_booking ?? true,
      allowWalkIn: row.allow_walk_in_booking ?? true,
      advancePaymentRequired: row.advance_payment_required ?? false,
      allowCancellations: row.allow_cancellations ?? true,
      requirePlayerDetails: row.require_player_details ?? true,
    },
    amenityKeys: row.amenity_keys ?? [],
    customAmenities: row.custom_amenities ?? [],
    hoursSettings: {
      allowBookingsOutsideHours: row.allow_bookings_outside_hours ?? false,
      breakStart: row.operating_break_start?.slice(0, 5) ?? undefined,
      breakEnd: row.operating_break_end?.slice(0, 5) ?? undefined,
      sportWiseHours: row.sport_wise_hours ?? false,
    },
    pricingSettings: {
      mode: row.pricing_mode ?? "BY_SPORT",
      differentWeekendPricing: row.different_weekend_pricing ?? true,
      memberPricingEnabled: row.member_pricing_enabled ?? false,
      coachingPricingEnabled: row.coaching_pricing_enabled ?? false,
    },
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

    // Resolve via facility access, not ownership: a manager or staff member
    // has an ACTIVE facility_users row but owns nothing. RLS on `facilities`
    // (is_facility_member, which now also requires status = 'ACTIVE') already
    // scopes this select to the facilities the signed-in user may see — an
    // owned facility is preferred, otherwise the first (primary) assignment.
    const { data, error } = await this.supabase
      .from("facilities")
      .select("*")
      .order("created_at", { ascending: true });

    if (error) throw mapSupabaseError(error);
    const facility = (data ?? []).find((f) => f.owner_id === user.id) ?? data?.[0] ?? null;
    return facility ? toFacility(facility) : null;
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
    if (patch.locationUrl !== undefined) update.location_url = patch.locationUrl.trim() || null;
    if (patch.venueType !== undefined) update.venue_type = patch.venueType;
    if (patch.ownershipType !== undefined) update.ownership_type = patch.ownershipType;
    if (patch.whatsappNumber !== undefined) update.whatsapp_number = patch.whatsappNumber.trim() || null;
    if (patch.contactPerson !== undefined) {
      update.contact_person_name = patch.contactPerson.name.trim() || null;
      update.contact_person_role = patch.contactPerson.role.trim() || null;
      update.contact_person_alt_phone = patch.contactPerson.alternatePhone?.trim() || null;
    }
    if (patch.policies !== undefined) {
      update.allow_online_booking = patch.policies.allowOnlineBooking;
      update.allow_walk_in_booking = patch.policies.allowWalkIn;
      update.advance_payment_required = patch.policies.advancePaymentRequired;
      update.allow_cancellations = patch.policies.allowCancellations;
      update.require_player_details = patch.policies.requirePlayerDetails;
    }
    // The database derives the five legacy amenity flags from the list (trigger sync_facility_amenity_flags).
    if (patch.amenityKeys !== undefined) update.amenity_keys = patch.amenityKeys;
    if (patch.customAmenities !== undefined) update.custom_amenities = patch.customAmenities;
    if (patch.pricingSettings !== undefined) {
      update.pricing_mode = patch.pricingSettings.mode;
      update.different_weekend_pricing = patch.pricingSettings.differentWeekendPricing;
      update.member_pricing_enabled = patch.pricingSettings.memberPricingEnabled;
      update.coaching_pricing_enabled = patch.pricingSettings.coachingPricingEnabled;
    }
    if (patch.hoursSettings !== undefined) {
      update.allow_bookings_outside_hours = patch.hoursSettings.allowBookingsOutsideHours;
      update.operating_break_start = patch.hoursSettings.breakStart ?? null;
      update.operating_break_end = patch.hoursSettings.breakEnd ?? null;
      update.sport_wise_hours = patch.hoursSettings.sportWiseHours;
    }
    if (patch.amenities !== undefined) {
      update.has_parking = patch.amenities.parking;
      update.has_changing_rooms = patch.amenities.changingRooms;
      update.has_toilets = patch.amenities.toilets;
      update.has_cafeteria = patch.amenities.cafeteria;
      update.has_equipment_rental = patch.amenities.equipmentRental;
    }
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