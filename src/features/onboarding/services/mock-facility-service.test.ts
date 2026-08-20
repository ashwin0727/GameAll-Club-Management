import { beforeEach, describe, expect, it } from "vitest";
import { MockFacilityService } from "@/features/onboarding/services/mock-facility-service";
import type { FacilityInput } from "@/features/onboarding/types";

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

describe("MockFacilityService", () => {
  beforeEach(() => {
    window.localStorage.clear();
  });

  it("saves a facility and assigns an id and timestamps", async () => {
    const facility = await MockFacilityService.saveFacility(INPUT);

    expect(facility.id).toBeTruthy();
    expect(facility.name).toBe("GameAll Sports Arena");
    expect(facility.status).toBe("ACTIVE");
    expect(facility.createdAt).toBeTruthy();
    expect(facility.updatedAt).toBe(facility.createdAt);
  });

  it("retrieves a saved facility by owner id", async () => {
    const saved = await MockFacilityService.saveFacility(INPUT);

    const found = await MockFacilityService.getFacility("owner-1");
    expect(found?.id).toBe(saved.id);
  });

  it("returns null for an owner with no facility", async () => {
    const found = await MockFacilityService.getFacility("owner-does-not-exist");
    expect(found).toBeNull();
  });

  it("updates a facility and bumps updatedAt", async () => {
    const saved = await MockFacilityService.saveFacility(INPUT);
    await new Promise((resolve) => setTimeout(resolve, 2));

    const updated = await MockFacilityService.updateFacility(saved.id, { name: "New Name" });
    expect(updated.name).toBe("New Name");
    expect(updated.updatedAt).not.toBe(saved.updatedAt);
  });
});
