import type { ProfileService } from "@/services/profile/profile.service";
import { SupabaseProfileService } from "@/services/profile/supabase-profile.service";

let instance: ProfileService | null = null;

/** Single entry point for the profile implementation. */
export function getProfileService(): ProfileService {
  instance ??= new SupabaseProfileService();
  return instance;
}

/** Test seam: overrides the singleton for the current module instance. */
export function setProfileService(service: ProfileService | null): void {
  instance = service;
}

export type { ProfileService } from "@/services/profile/profile.service";
