import type { FacilityService } from "@/services/facility/facility.service";
import { SupabaseFacilityService } from "@/services/facility/supabase-facility.service";

let instance: FacilityService | null = null;

/** Single entry point for the facility implementation. */
export function getFacilityService(): FacilityService {
  instance ??= new SupabaseFacilityService();
  return instance;
}

/** Test seam: overrides the singleton for the current module instance. */
export function setFacilityService(service: FacilityService | null): void {
  instance = service;
}

export type { FacilityService, OnboardingStep } from "@/services/facility/facility.service";