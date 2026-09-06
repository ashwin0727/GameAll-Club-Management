import type { MaintenanceService } from "@/services/maintenance/maintenance.service";
import { SupabaseMaintenanceService } from "@/services/maintenance/supabase-maintenance.service";

let instance: MaintenanceService | null = null;

/** Single entry point for the Maintenance implementation. */
export function getMaintenanceService(): MaintenanceService {
  instance ??= new SupabaseMaintenanceService();
  return instance;
}

/** Test seam: overrides the singleton for the current module instance. */
export function setMaintenanceService(service: MaintenanceService | null): void {
  instance = service;
}

export type { FacilityStaffOption, MaintenanceService } from "@/services/maintenance/maintenance.service";
