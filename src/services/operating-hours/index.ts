import type { OperatingHoursService } from "@/services/operating-hours/operating-hours.service";
import { SupabaseOperatingHoursService } from "@/services/operating-hours/supabase-operating-hours.service";

let instance: OperatingHoursService | null = null;

/** Single entry point for the operating-hours implementation. */
export function getOperatingHoursService(): OperatingHoursService {
  instance ??= new SupabaseOperatingHoursService();
  return instance;
}

/** Test seam: overrides the singleton for the current module instance. */
export function setOperatingHoursService(service: OperatingHoursService | null): void {
  instance = service;
}

export type { OperatingHoursService } from "@/services/operating-hours/operating-hours.service";