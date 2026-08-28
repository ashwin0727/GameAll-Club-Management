import type { FinanceService } from "@/services/finance/finance.service";
import { SupabaseFinanceService } from "@/services/finance/supabase-finance.service";

let instance: FinanceService | null = null;

/** Single entry point for the Finance implementation. */
export function getFinanceService(): FinanceService {
  instance ??= new SupabaseFinanceService();
  return instance;
}

/** Test seam: overrides the singleton for the current module instance. */
export function setFinanceService(service: FinanceService | null): void {
  instance = service;
}

export type { FinanceService } from "@/services/finance/finance.service";