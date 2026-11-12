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
  locationUrl: "https://maps.app.goo.gl/AbCdEf123",
  contactPersonName: "Uma Shankar M",
  contactPersonRole: "Facility Owner" as const,
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

  it("requires the Google Maps location link, and only a Google Maps one", () => {
    expect(facilityDetailsSchema.safeParse({ ...VALID, locationUrl: "" }).success).toBe(false);
    expect(facilityDetailsSchema.safeParse({ ...VALID, locationUrl: "   " }).success).toBe(false);
    expect(facilityDetailsSchema.safeParse({ ...VALID, locationUrl: "https://example.com/map" }).success).toBe(false);
    expect(facilityDetailsSchema.safeParse({ ...VALID, locationUrl: "https://www.google.com/maps/place/Arena" }).success).toBe(true);
  });

  it("amenities default to none, accept only the 12 known keys, and custom ones are checked", () => {
    const parsed = facilityDetailsSchema.safeParse(VALID);
    expect(parsed.success).toBe(true);
    if (parsed.success) expect(parsed.data.amenityKeys).toEqual([]);
    expect(facilityDetailsSchema.safeParse({ ...VALID, amenityKeys: ["wifi", "shower"] }).success).toBe(true);
    expect(facilityDetailsSchema.safeParse({ ...VALID, amenityKeys: ["jacuzzi"] }).success).toBe(false);
    expect(facilityDetailsSchema.safeParse({ ...VALID, customAmenities: ["Physio room"] }).success).toBe(true);
    expect(facilityDetailsSchema.safeParse({ ...VALID, customAmenities: ["x"] }).success).toBe(false);
    expect(facilityDetailsSchema.safeParse({ ...VALID, customAmenities: ["Wi-Fi"] }).success).toBe(false);
    expect(facilityDetailsSchema.safeParse({ ...VALID, customAmenities: ["Spa", "spa"] }).success).toBe(false);
  });

  it("requires address line, area, city, and state", () => {
    for (const field of ["addressLine", "area", "city", "state"] as const) {
      const result = facilityDetailsSchema.safeParse({ ...VALID, [field]: "" });
      expect(result.success).toBe(false);
    }
  });
});

describe("businessPhone", () => {
  const base = { facilityName: "Arena", facilityType: "BADMINTON", addressLine: "1 Main St", area: "Adyar", city: "Chennai", state: "Tamil Nadu", pinCode: "600020", locationUrl: "https://maps.app.goo.gl/AbCdEf123", contactPersonName: "Uma Shankar M", contactPersonRole: "Facility Owner" };
  const msg = (phone: string) => facilityDetailsSchema.safeParse({ ...base, businessPhone: phone }).error?.issues[0]?.message;

  it("is required", () => expect(msg("")).toBe("Contact number is required"));
  it("needs exactly 10 digits", () => expect(msg("98765")).toBe("Enter a valid 10-digit mobile number"));
  it("must start with 6, 7, 8 or 9", () => expect(msg("1234567890")).toBe("Mobile number must start with 6, 7, 8 or 9"));
  it("accepts a valid mobile, with or without +91", () => {
    expect(msg("9876543210")).toBeUndefined();
    expect(msg("+919876543210")).toBeUndefined();
  });
});

describe("contact person, whatsapp, ownership and description", () => {
  const msg = (patch: Record<string, unknown>) => facilityDetailsSchema.safeParse({ ...VALID, ...patch }).error?.issues[0]?.message;

  it("defaults ownership to owned and accepts leased, but nothing else", () => {
    const parsed = facilityDetailsSchema.safeParse(VALID);
    expect(parsed.success && parsed.data.ownershipType).toBe("OWNED");
    expect(facilityDetailsSchema.safeParse({ ...VALID, ownershipType: "LEASED" }).success).toBe(true);
    expect(facilityDetailsSchema.safeParse({ ...VALID, ownershipType: "RENTED" }).success).toBe(false);
  });

  it("whatsapp is optional but, when given, must be a valid mobile number", () => {
    expect(facilityDetailsSchema.safeParse({ ...VALID, whatsappNumber: "" }).success).toBe(true);
    expect(facilityDetailsSchema.safeParse({ ...VALID, whatsappNumber: "9123456780" }).success).toBe(true);
    expect(msg({ whatsappNumber: "91234" })).toBe("Enter a valid 10-digit mobile number");
    expect(msg({ whatsappNumber: "5123456789" })).toBe("Mobile number must start with 6, 7, 8 or 9");
  });

  it("requires the contact person name (letters only) and a role from the list", () => {
    expect(msg({ contactPersonName: "" })).toBe("Enter the contact person's name");
    expect(msg({ contactPersonName: "U" })).toBe("Enter the contact person's name");
    expect(msg({ contactPersonName: "Uma123" })).toBe("Name can contain letters, spaces and . ' - only");
    expect(facilityDetailsSchema.safeParse({ ...VALID, contactPersonName: "Mary-Ann O'Neil Jr." }).success).toBe(true);
    expect(facilityDetailsSchema.safeParse({ ...VALID, contactPersonRole: "Janitor" }).success).toBe(false);
    for (const role of ["Facility Owner", "Manager", "Receptionist", "Coach", "Other"]) {
      expect(facilityDetailsSchema.safeParse({ ...VALID, contactPersonRole: role }).success).toBe(true);
    }
  });

  it("the alternate number is optional, valid when given, and different from the contact number", () => {
    expect(facilityDetailsSchema.safeParse({ ...VALID, contactAlternatePhone: "9123456780" }).success).toBe(true);
    expect(msg({ contactAlternatePhone: "123" })).toBe("Enter a valid 10-digit mobile number");
    expect(msg({ contactAlternatePhone: VALID.businessPhone })).toBe("Use a different number from the contact number");
  });

  it("limits the description to 500 characters", () => {
    expect(facilityDetailsSchema.safeParse({ ...VALID, description: "a".repeat(500) }).success).toBe(true);
    expect(msg({ description: "a".repeat(501) })).toBe("Description can be up to 500 characters");
  });

  it("limits custom amenities to 10", () => {
    const eleven = Array.from({ length: 11 }, (_, i) => `Extra ${String.fromCharCode(97 + i)}`);
    expect(facilityDetailsSchema.safeParse({ ...VALID, customAmenities: eleven.slice(0, 10) }).success).toBe(true);
    expect(msg({ customAmenities: eleven })).toBe("Add up to 10 custom amenities");
  });
});
