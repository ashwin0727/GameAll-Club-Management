import { useFacilitySportOptions } from "@/features/facility/hooks/use-facility-sport-options";
import { useUiStore } from "@/stores/ui-store";

/**
 * The one sport every "current view" should be scoped to — whatever the top bar's Sport picker
 * has selected, falling back to the facility's first sport when nothing's picked yet (a fresh
 * session) or the stored id no longer matches one of this facility's sports (switched facility).
 * Same resolution rule `booking-operations-view.tsx` already uses; pulled out here so every other
 * "one sport at a time" page (Memberships) can share it instead of re-deriving it.
 *
 * Returns null only while the facility's sport list hasn't loaded yet, or it has none — callers
 * should treat null as "don't filter" rather than "no sport", so a not-yet-loaded list never
 * hides everything.
 */
export function useActiveFacilitySportId(facilityId: string | null | undefined): string | null {
  const { data: options = [] } = useFacilitySportOptions(facilityId ?? undefined);
  const stored = useUiStore((s) => s.activeFacilitySportId);
  if (options.some((o) => o.facilitySportId === stored)) return stored;
  return options[0]?.facilitySportId ?? null;
}
