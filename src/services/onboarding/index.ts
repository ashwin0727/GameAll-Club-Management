import type { OnboardingService } from "@/services/onboarding/onboarding.service";
import { SupabaseOnboardingService } from "@/services/onboarding/supabase-onboarding.service";

let instance: OnboardingService | null = null;

/** Single entry point for the setup-summary implementation. */
export function getOnboardingService(): OnboardingService {
  instance ??= new SupabaseOnboardingService();
  return instance;
}

/** Test seam: overrides the singleton for the current module instance. */
export function setOnboardingService(service: OnboardingService | null): void {
  instance = service;
}

export type { OnboardingService } from "@/services/onboarding/onboarding.service";