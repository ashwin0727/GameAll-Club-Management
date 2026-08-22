import type { PlayingAreasService } from "@/services/playing-areas/playing-areas.service";
import { SupabasePlayingAreasService } from "@/services/playing-areas/supabase-playing-areas.service";

let instance: PlayingAreasService | null = null;

/** Single entry point for the playing-areas implementation. */
export function getPlayingAreasService(): PlayingAreasService {
  instance ??= new SupabasePlayingAreasService();
  return instance;
}

/** Test seam: overrides the singleton for the current module instance. */
export function setPlayingAreasService(service: PlayingAreasService | null): void {
  instance = service;
}

export type { PlayingAreasService } from "@/services/playing-areas/playing-areas.service";