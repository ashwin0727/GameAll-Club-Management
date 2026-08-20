import type { FacilityType } from "@/features/onboarding/types";

export const FACILITY_TYPE_OPTIONS: { value: FacilityType; label: string }[] = [
  { value: "BADMINTON", label: "Badminton Court" },
  { value: "PICKLEBALL", label: "Pickleball Court" },
  { value: "CRICKET", label: "Cricket Turf" },
  { value: "FOOTBALL", label: "Football Turf" },
  { value: "TENNIS", label: "Tennis Court" },
  { value: "MULTI_SPORT", label: "Multi-Sport Facility" },
  { value: "OTHER", label: "Other" },
];

export const DEFAULT_FACILITY_TYPE: FacilityType = "MULTI_SPORT";

export const INDIAN_STATES = [
  "Andhra Pradesh",
  "Arunachal Pradesh",
  "Assam",
  "Bihar",
  "Chhattisgarh",
  "Goa",
  "Gujarat",
  "Haryana",
  "Himachal Pradesh",
  "Jharkhand",
  "Karnataka",
  "Kerala",
  "Madhya Pradesh",
  "Maharashtra",
  "Manipur",
  "Meghalaya",
  "Mizoram",
  "Nagaland",
  "Odisha",
  "Punjab",
  "Rajasthan",
  "Sikkim",
  "Tamil Nadu",
  "Telangana",
  "Tripura",
  "Uttar Pradesh",
  "Uttarakhand",
  "West Bengal",
  "Andaman and Nicobar Islands",
  "Chandigarh",
  "Dadra and Nagar Haveli and Daman and Diu",
  "Delhi",
  "Jammu and Kashmir",
  "Ladakh",
  "Lakshadweep",
  "Puducherry",
];

export const MAX_LOGO_SIZE_BYTES = 5 * 1024 * 1024;
export const ACCEPTED_LOGO_TYPES = ["image/png", "image/jpeg", "image/webp"];
