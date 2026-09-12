import { SupabaseCoachingService } from "@/services/coaching/supabase-coaching.service";

let instance: SupabaseCoachingService | null = null;

/** Single entry point for the Coaching Management implementation. */
export function getCoachingService(): SupabaseCoachingService {
  instance ??= new SupabaseCoachingService();
  return instance;
}

/** Test seam: overrides the singleton for the current module instance. */
export function setCoachingService(service: SupabaseCoachingService | null): void {
  instance = service;
}
