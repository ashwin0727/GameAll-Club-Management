import type { ReportsService } from "@/services/reports/reports.service";
import { SupabaseReportsService } from "@/services/reports/supabase-reports.service";

let instance: ReportsService | null = null;

/** Single entry point for the Reports implementation. */
export function getReportsService(): ReportsService {
  instance ??= new SupabaseReportsService();
  return instance;
}

/** Test seam: overrides the singleton for the current module instance. */
export function setReportsService(service: ReportsService | null): void {
  instance = service;
}

export type { ReportsService } from "@/services/reports/reports.service";
