import { z } from "zod";
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
    businessPhone: z
      .string()
      .trim()
      .regex(/^(\+91)?[6-9]\d{9}$/, "Enter a valid 10-digit mobile number"),
    addressLine: z
      .string()
      .trim()
      .min(1, "Address is required")
      .max(250, "Address is too long"),
    area: z.string().trim().min(1, "Area / locality is required").max(100, "Area is too long"),
    city: z.string().trim().min(1, "City is required"),
    state: z.string().trim().min(1, "State is required"),
    pinCode: z.string().trim().regex(/^\d{6}$/, "PIN code must be exactly 6 digits"),
    description: z.string().max(500, "Keep this under 500 characters").optional().default(""),
  })
  .refine(
    (values) => values.facilityType !== "OTHER" || values.customFacilityType.trim().length > 0,
    { path: ["customFacilityType"], message: "Specify your facility type" },
  );

export type FacilityDetailsInput = z.infer<typeof facilityDetailsSchema>;
