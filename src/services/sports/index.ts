import type { SportsService } from "@/services/sports/sports.service";
import { SupabaseSportsService } from "@/services/sports/supabase-sports.service";

let instance: SportsService | null = null;

/** Single entry point for the sports implementation. */
export function getSportsService(): SportsService {
  instance ??= new SupabaseSportsService();
  return instance;
}

/** Test seam: overrides the singleton for the current module instance. */
export function setSportsService(service: SportsService | null): void {
  instance = service;
}

export type { SportsService } from "@/services/sports/sports.service";