import { describe, expect, it, vi } from "vitest";
import { SupabaseFacilityService } from "@/services/facility/supabase-facility.service";
import { ServiceError } from "@/services/shared/service-error";
import { fakeQueryBuilder } from "@/test/fakes/fake-supabase-query";
import type { FacilityInput } from "@/features/onboarding/types";

const FACILITY_ROW = {
  id: "facility-1",
  name: "GameAll Sports Arena",
  slug: "gameall-sports-arena-abc123",
  owner_id: "owner-1",
  city: "Chennai",
  address: null,
  timezone: "Asia/Kolkata",
  currency: "INR",
  created_at: "2026-01-01T00:00:00.000Z",
  facility_type: "MULTI_SPORT",
  custom_facility_type: null,
  business_email: "owner@yourturf.com",
  business_phone: "9876543210",
  address_line_1: "123 Anna Salai",
  address_line_2: null,
  area: "Ambattur",
  state: "Tamil Nadu",
  country: "India",
  postal_code: "600053",
  latitude: null,
  longitude: null,
  logo_url: null,
  description: null,
  status: "ACTIVE",
  onboarding_step: "FACILITY_DETAILS",
  updated_at: "2026-01-01T00:00:00.000Z",
  membership_access_days: [1, 2, 3, 4, 5],
};

const INPUT: FacilityInput = {
  ownerId: "owner-1",
  name: "GameAll Sports Arena",
  type: "MULTI_SPORT",
  businessEmail: "owner@yourturf.com",
  businessPhone: "9876543210",
  address: {
    line1: "123 Anna Salai",
    area: "Ambattur",
    city: "Chennai",
    state: "Tamil Nadu",
    country: "India",
    pinCode: "600053",
  },
};

describe("SupabaseFacilityService", () => {
  it("creates a facility via the create_facility_with_owner RPC and maps the row back", async () => {
    const rpc = vi.fn(async () => ({ data: FACILITY_ROW, error: null }));
    const service = new SupabaseFacilityService({ rpc } as never);

    const facility = await service.createFacility(INPUT);

    expect(rpc).toHaveBeenCalledWith(
      "create_facility_with_owner",
      expect.objectContaining({ p_name: "GameAll Sports Arena", p_facility_type: "MULTI_SPORT" }),
    );
    expect(facility.id).toBe("facility-1");
    expect(facility.address.pinCode).toBe("600053");
  });

  it("getFacility throws UNAUTHENTICATED when there is no signed-in user", async () => {
    const auth = { getUser: vi.fn(async () => ({ data: { user: null } })) };
    const service = new SupabaseFacilityService({ auth } as never);

    await expect(service.getFacility()).rejects.toThrow(ServiceError);
  });

  it("getFacility returns null when the current user has no facility yet", async () => {
    const auth = { getUser: vi.fn(async () => ({ data: { user: { id: "owner-1" } } })) };
    const from = vi.fn(() => fakeQueryBuilder({ data: null, error: null }));
    const service = new SupabaseFacilityService({ auth, from } as never);

    expect(await service.getFacility()).toBeNull();
  });

  it("maps membership_access_days onto the Facility", async () => {
    const auth = { getUser: vi.fn(async () => ({ data: { user: { id: "owner-1" } } })) };
    const from = vi.fn(() => fakeQueryBuilder({ data: FACILITY_ROW, error: null }));
    const service = new SupabaseFacilityService({ auth, from } as never);

    const facility = await service.getFacility();

    expect(facility?.membershipAccessDays).toEqual([1, 2, 3, 4, 5]);
  });

  it("updateFacility never lets id or owner_id be part of the write payload", async () => {
    const builder = fakeQueryBuilder({ data: FACILITY_ROW, error: null });
    const from = vi.fn(() => builder);
    const service = new SupabaseFacilityService({ from } as never);

    await service.updateFacility("facility-1", { name: "New Name", ownerId: "someone-else" } as never);

    const updateCall = (builder.update as ReturnType<typeof vi.fn>).mock.calls[0]?.[0];
    expect(updateCall).not.toHaveProperty("id");
    expect(updateCall).not.toHaveProperty("owner_id");
    expect(updateCall.name).toBe("New Name");
  });

  it("updateFacility throws FACILITY_NOT_FOUND when no row matches", async () => {
    const from = vi.fn(() => fakeQueryBuilder({ data: null, error: null }));
    const service = new SupabaseFacilityService({ from } as never);

    await expect(service.updateFacility("missing", { name: "X" })).rejects.toMatchObject({
      code: "FACILITY_NOT_FOUND",
    });
  });
});