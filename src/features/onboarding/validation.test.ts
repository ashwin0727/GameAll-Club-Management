import { describe, expect, it } from "vitest";
import { facilityDetailsSchema } from "@/features/onboarding/validation";

const VALID = {
  facilityName: "GameAll Sports Arena",
  facilityType: "MULTI_SPORT" as const,
  customFacilityType: "",
  businessPhone: "9876543210",
  addressLine: "123 Anna Salai",
  area: "Ambattur",
  city: "Chennai",
  state: "Tamil Nadu",
  pinCode: "600053",
  description: "",
};

describe("facilityDetailsSchema", () => {
  it("accepts a fully valid facility", () => {
    expect(facilityDetailsSchema.safeParse(VALID).success).toBe(true);
  });

  it("rejects an empty facility name", () => {
    const result = facilityDetailsSchema.safeParse({ ...VALID, facilityName: "" });
    expect(result.success).toBe(false);
  });

  it("rejects a facility name under 2 characters", () => {
    const result = facilityDetailsSchema.safeParse({ ...VALID, facilityName: "G" });
    expect(result.success).toBe(false);
  });

  it("rejects a whitespace-only facility name", () => {
    const result = facilityDetailsSchema.safeParse({ ...VALID, facilityName: "   " });
    expect(result.success).toBe(false);
  });

  it("requires customFacilityType when facilityType is OTHER", () => {
    const result = facilityDetailsSchema.safeParse({
      ...VALID,
      facilityType: "OTHER",
      customFacilityType: "",
    });
    expect(result.success).toBe(false);
  });

  it("accepts OTHER with a custom type under 50 characters", () => {
    const result = facilityDetailsSchema.safeParse({
      ...VALID,
      facilityType: "OTHER",
      customFacilityType: "Basketball Court",
    });
    expect(result.success).toBe(true);
  });

  it("accepts a phone with a +91 prefix", () => {
    expect(
      facilityDetailsSchema.safeParse({ ...VALID, businessPhone: "+919876543210" }).success,
    ).toBe(true);
  });

  it("rejects a phone that isn't 10 digits", () => {
    expect(facilityDetailsSchema.safeParse({ ...VALID, businessPhone: "98765" }).success).toBe(
      false,
    );
  });

  it("rejects a PIN code with letters", () => {
    expect(facilityDetailsSchema.safeParse({ ...VALID, pinCode: "6000AB" }).success).toBe(false);
  });

  it("rejects a PIN code that isn't exactly 6 digits", () => {
    expect(facilityDetailsSchema.safeParse({ ...VALID, pinCode: "60005" }).success).toBe(false);
  });

  it("rejects a description over 500 characters", () => {
    const result = facilityDetailsSchema.safeParse({
      ...VALID,
      description: "a".repeat(501),
    });
    expect(result.success).toBe(false);
  });

  it("requires address line, area, city, and state", () => {
    for (const field of ["addressLine", "area", "city", "state"] as const) {
      const result = facilityDetailsSchema.safeParse({ ...VALID, [field]: "" });
      expect(result.success).toBe(false);
    }
  });
});
