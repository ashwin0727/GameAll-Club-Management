import { z } from "zod";
import { isGoogleMapsLink } from "@/features/facility-profile/maps-link";
import { AMENITY_KEYS, CONTACT_ROLE_OPTIONS, DEFAULT_POLICIES, MAX_CUSTOM_AMENITIES, FACILITY_AMENITIES } from "@/features/facility-profile/types";
import { FACILITY_TYPE_OPTIONS } from "@/features/onboarding/constants";

const facilityTypeValues = FACILITY_TYPE_OPTIONS.map((option) => option.value) as [
  string,
  ...string[],
];

/** Mobile rules used everywhere in the app: exactly 10 digits, starting 6–9 (a stored "+91…" is still accepted). */
function mobileProblem(value: string, label: string): string | null {
  const digits = value.trim().replace(/^\+91/, "");
  if (!digits) return `${label} is required`;
  if (!/^\d{10}$/.test(digits)) return "Enter a valid 10-digit mobile number";
  if (!/^[6-9]/.test(digits)) return "Mobile number must start with 6, 7, 8 or 9";
  return null;
}

const requiredMobile = (label: string) =>
  z
    .string()
    .trim()
    .superRefine((value, ctx) => {
      const problem = mobileProblem(value, label);
      if (problem) ctx.addIssue({ code: "custom", message: problem });
    });

const optionalMobile = z
  .string()
  .trim()
  .optional()
  .default("")
  .superRefine((value, ctx) => {
    if (!value) return;
    const problem = mobileProblem(value, "Number");
    if (problem) ctx.addIssue({ code: "custom", message: problem });
  });

const customAmenity = z
  .string()
  .trim()
  .min(2, "Amenity name must be at least 2 characters")
  .max(30, "Keep the amenity name under 30 characters")
  .regex(/^[\p{L}\p{N}][\p{L}\p{N} &/'().,+-]*$/u, "Use letters, numbers and common punctuation only");

/** The raw field rules; facilityDetailsSchema adds the cross-field checks on top. */
export const facilityDetailsObject = z.object({
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
    ownershipType: z.enum(["OWNED", "LEASED"], { message: "Choose owned or leased" }).default("OWNED"),
    businessPhone: requiredMobile("Contact number"),
    whatsappNumber: optionalMobile,
    description: z.string().trim().max(500, "Description can be up to 500 characters").optional().default(""),
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
    contactPersonName: z
      .string()
      .trim()
      .min(2, "Enter the contact person's name")
      .max(80, "Name is too long")
      .regex(/^[\p{L}][\p{L} .'-]*$/u, "Name can contain letters, spaces and . ' - only"),
    contactPersonRole: z.enum(CONTACT_ROLE_OPTIONS, { message: "Choose a role" }),
    contactAlternatePhone: optionalMobile,
    policies: z
      .object({
        allowOnlineBooking: z.boolean(),
        allowWalkIn: z.boolean(),
        advancePaymentRequired: z.boolean(),
        allowCancellations: z.boolean(),
        requirePlayerDetails: z.boolean(),
      })
      .default(DEFAULT_POLICIES),
    amenityKeys: z.array(z.enum(AMENITY_KEYS)).default([]),
    customAmenities: z.array(customAmenity).max(MAX_CUSTOM_AMENITIES, `Add up to ${MAX_CUSTOM_AMENITIES} custom amenities`).default([]),
});

export const facilityDetailsSchema = facilityDetailsObject
  .superRefine((values, ctx) => {
    if (values.facilityType === "OTHER" && values.customFacilityType.trim().length === 0) {
      ctx.addIssue({ code: "custom", path: ["customFacilityType"], message: "Specify your facility type" });
    }
    const normalise = (v: string) => v.trim().toLowerCase();
    const seen = new Set<string>();
    const standard = new Set(FACILITY_AMENITIES.map((a) => normalise(a.label)));
    values.customAmenities.forEach((name, i) => {
      const key = normalise(name);
      if (seen.has(key) || standard.has(key)) {
        ctx.addIssue({ code: "custom", path: ["customAmenities", i], message: `"${name}" is already in the list` });
      }
      seen.add(key);
    });
    const alt = values.contactAlternatePhone.replace(/^\+91/, "");
    if (alt && alt === values.businessPhone.replace(/^\+91/, "")) {
      ctx.addIssue({ code: "custom", path: ["contactAlternatePhone"], message: "Use a different number from the contact number" });
    }
  });

export type FacilityDetailsInput = z.infer<typeof facilityDetailsSchema>;

/** The message to show when a typed custom amenity can't be added (null when it is fine). Shares the schema's rules. */
export function customAmenityProblem(name: string, existing: string[]): string | null {
  const parsed = customAmenity.safeParse(name);
  if (!parsed.success) return parsed.error.issues[0]?.message ?? "Enter a valid amenity name";
  if (existing.length >= MAX_CUSTOM_AMENITIES) return `Add up to ${MAX_CUSTOM_AMENITIES} custom amenities`;
  const key = parsed.data.toLowerCase();
  const taken = [...existing, ...FACILITY_AMENITIES.map((a) => a.label)].some((n) => n.trim().toLowerCase() === key);
  return taken ? `"${parsed.data}" is already in the list` : null;
}
