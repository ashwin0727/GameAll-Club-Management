import { z } from "zod";
import { isGoogleMapsLink } from "@/features/facility-profile/maps-link";
import { NO_AMENITIES } from "@/features/facility-profile/types";
import { FACILITY_TYPE_OPTIONS } from "@/features/onboarding/constants";

const facilityTypeValues = FACILITY_TYPE_OPTIONS.map((option) => option.value) as [
  string,
  ...string[],
];

export const facilityDetailsSchema = z
  .object({
    facilityName: z
      .string()
      .trim()
      .min(2, "Facility name must be at least 2 characters")
      .max(100, "Facility name is too long"),
    facilityType: z.enum(facilityTypeValues as [string, ...string[]]),
    customFacilityType: z
      .string()
      .trim()
      .max(50, "Keep this under 50 characters")
      .optional()
      .default(""),
    // Same rules as the phone fields elsewhere in the app: required, exactly 10 digits, starting 6–9
    // (a stored "+91…" is still accepted).
    businessPhone: z
      .string()
      .trim()
      .superRefine((value, ctx) => {
        const digits = value.replace(/^\+91/, "");
        if (!digits) ctx.addIssue({ code: "custom", message: "Phone number is required" });
        else if (!/^\d{10}$/.test(digits)) ctx.addIssue({ code: "custom", message: "Enter a valid 10-digit mobile number" });
        else if (!/^[6-9]/.test(digits)) ctx.addIssue({ code: "custom", message: "Mobile number must start with 6, 7, 8 or 9" });
      }),
    addressLine: z
      .string()
      .trim()
      .min(1, "Address is required")
      .max(250, "Address is too long"),
    area: z.string().trim().min(1, "Area / locality is required").max(100, "Area is too long"),
    city: z.string().trim().min(1, "City is required"),
    state: z.string().trim().min(1, "State is required"),
    pinCode: z.string().trim().regex(/^\d{6}$/, "PIN code must be exactly 6 digits"),
    // The Google Maps link of the facility (required; GameAll's admin opens it to confirm the place is right).
    locationUrl: z
      .string()
      .trim()
      .min(1, "Google Maps location link is required")
      .refine(isGoogleMapsLink, "Paste a Google Maps link, e.g. https://maps.app.goo.gl/..."),
    venueType: z.enum(["INDOOR", "OUTDOOR"], { message: "Choose indoor or outdoor" }),
    amenities: z
      .object({ parking: z.boolean(), changingRooms: z.boolean(), toilets: z.boolean(), cafeteria: z.boolean(), equipmentRental: z.boolean() })
      .default(NO_AMENITIES),
  })
  .refine(
    (values) => values.facilityType !== "OTHER" || values.customFacilityType.trim().length > 0,
    { path: ["customFacilityType"], message: "Specify your facility type" },
  );

export type FacilityDetailsInput = z.infer<typeof facilityDetailsSchema>;
