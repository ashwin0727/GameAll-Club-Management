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

describe("businessPhone", () => {
  const base = { facilityName: "Arena", facilityType: "BADMINTON", addressLine: "1 Main St", area: "Adyar", city: "Chennai", state: "Tamil Nadu", pinCode: "600020" };
  const msg = (phone: string) => facilityDetailsSchema.safeParse({ ...base, businessPhone: phone }).error?.issues[0]?.message;

  it("is required", () => expect(msg("")).toBe("Phone number is required"));
  it("needs exactly 10 digits", () => expect(msg("98765")).toBe("Enter a valid 10-digit mobile number"));
  it("must start with 6, 7, 8 or 9", () => expect(msg("1234567890")).toBe("Mobile number must start with 6, 7, 8 or 9"));
  it("accepts a valid mobile, with or without +91", () => {
    expect(msg("9876543210")).toBeUndefined();
    expect(msg("+919876543210")).toBeUndefined();
  });
});
