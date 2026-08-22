import type { FacilityType } from "@/features/onboarding/types";
import type { Sport } from "@/features/sports-setup/types";

/**
 * Sport ids are now database-generated UUIDs (see supabase/migrations), so
 * nothing here can hard-code an id. Presentation (icon/description) has no
 * DB column — it's purely UI, keyed by the sport's stable `code` instead.
 */
export const OTHER_SPORT_CODE = "OTHER";

const SPORT_PRESENTATION: Record<string, { icon: string; description: string }> = {
  BADMINTON: { icon: "🏸", description: "Indoor racket sport" },
  PICKLEBALL: { icon: "🏓", description: "Court-based paddle sport" },
  CRICKET: { icon: "🏏", description: "Bat-and-ball team sport" },
  FOOTBALL: { icon: "⚽", description: "Outdoor team sport" },
  TENNIS: { icon: "🎾", description: "Racket sport on a court" },
  OTHER: { icon: "➕", description: "A sport not listed here" },
};

const DEFAULT_PRESENTATION = { icon: "🏅", description: "" };

/** Maps a `sports` table row (DB shape: id/key/name/is_active) to the frontend Sport type. */
export function presentSport(row: { id: string; key: string; name: string; is_active: boolean }): Sport {
  const code = row.key.toUpperCase();
  const presentation = SPORT_PRESENTATION[code] ?? DEFAULT_PRESENTATION;
  return {
    id: row.id,
    name: row.name,
    code,
    icon: presentation.icon,
    description: presentation.description,
    isActive: row.is_active,
  };
}

/**
 * Only the five single-sport facility types preselect a matching sport on
 * first visit. MULTI_SPORT and OTHER intentionally have no entry — nothing
 * is force-preselected for them. Values are sport codes, resolved to a real
 * sport id at runtime once the sport catalog has loaded.
 */
export const SINGLE_SPORT_TYPE_CODE_MAP: Partial<Record<FacilityType, string>> = {
  BADMINTON: "BADMINTON",
  PICKLEBALL: "PICKLEBALL",
  CRICKET: "CRICKET",
  FOOTBALL: "FOOTBALL",
  TENNIS: "TENNIS",
};