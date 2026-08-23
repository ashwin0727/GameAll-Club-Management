import type { DashboardService } from "@/services/dashboard/dashboard.service";
import { SupabaseDashboardService } from "@/services/dashboard/supabase-dashboard.service";

let instance: DashboardService | null = null;

/** Single entry point for the dashboard implementation. */
export function getDashboardService(): DashboardService {
  instance ??= new SupabaseDashboardService();
  return instance;
}

/** Test seam: overrides the singleton for the current module instance. */
export function setDashboardService(service: DashboardService | null): void {
  instance = service;
}

export type { DashboardService, DashboardSummaryParams } from "@/services/dashboard/dashboard.service";