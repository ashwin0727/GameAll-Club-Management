import type { PricingService } from "@/services/pricing/pricing.service";
import { SupabasePricingService } from "@/services/pricing/supabase-pricing.service";

let instance: PricingService | null = null;

/** Single entry point for the pricing implementation. */
export function getPricingService(): PricingService {
  instance ??= new SupabasePricingService();
  return instance;
}

/** Test seam: overrides the singleton for the current module instance. */
export function setPricingService(service: PricingService | null): void {
  instance = service;
}

export type { PricingService } from "@/services/pricing/pricing.service";