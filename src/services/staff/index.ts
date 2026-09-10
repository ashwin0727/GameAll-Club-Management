import { SupabaseStaffService } from "@/services/staff/supabase-staff.service";

let instance: SupabaseStaffService | null = null;

/** Single entry point for the Staff / Roles / Permissions implementation. */
export function getStaffService(): SupabaseStaffService {
  instance ??= new SupabaseStaffService();
  return instance;
}

/** Test seam: overrides the singleton for the current module instance. */
export function setStaffService(service: SupabaseStaffService | null): void {
  instance = service;
}
