import type { GuestService } from "@/services/guests/guest.service";
import { SupabaseGuestService } from "@/services/guests/supabase-guest.service";

let instance: GuestService | null = null;

/** Single entry point for the guest-players implementation. */
export function getGuestService(): GuestService {
  instance ??= new SupabaseGuestService();
  return instance;
}

/** Test seam: overrides the singleton for the current module instance. */
export function setGuestService(service: GuestService | null): void {
  instance = service;
}

export type { GuestService } from "@/services/guests/guest.service";