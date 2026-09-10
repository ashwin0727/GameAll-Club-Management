import { SupabaseInventoryService } from "@/services/inventory/supabase-inventory.service";

let instance: SupabaseInventoryService | null = null;

/** Single entry point for the Inventory & Vendors implementation. */
export function getInventoryService(): SupabaseInventoryService {
  instance ??= new SupabaseInventoryService();
  return instance;
}

/** Test seam: overrides the singleton for the current module instance. */
export function setInventoryService(service: SupabaseInventoryService | null): void {
  instance = service;
}
