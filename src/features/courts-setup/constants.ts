export type PlayingAreaLabel = "Court" | "Turf" | "Playing Area";

/** Keyed by Sport.code (the global sport catalog). Drives every piece of
 * dynamic terminology in this feature — never hardcode "Court" elsewhere. */
export const PLAYING_AREA_LABEL: Record<string, PlayingAreaLabel> = {
  BADMINTON: "Court",
  PICKLEBALL: "Court",
  TENNIS: "Court",
  CRICKET: "Turf",
  FOOTBALL: "Turf",
  BASKETBALL: "Court",
  OTHER: "Playing Area",
};

export function playingAreaLabelFor(sportCode: string): PlayingAreaLabel {
  return PLAYING_AREA_LABEL[sportCode] ?? "Playing Area";
}

export function pluralizeLabel(label: PlayingAreaLabel, count: number): string {
  if (count === 1) return label;
  return label === "Playing Area" ? "Playing Areas" : `${label}s`;
}

export const DEFAULT_PLAYING_AREA_TYPE = "INDOOR" as const;
export const DEFAULT_PLAYING_AREA_STATUS = "ACTIVE" as const;
export const DEFAULT_BOOKING_ENABLED = true;

// ── per-court details (Sports & Courts page) ──────────────────────────────

import type { CourtAmenity, LightingType } from "@/features/courts-setup/types";

export const COURT_TYPE_OPTIONS = [
  { value: "INDOOR", label: "Indoor" },
  { value: "OUTDOOR", label: "Outdoor" },
] as const;

export const LIGHTING_OPTIONS: { value: LightingType; label: string }[] = [
  { value: "LED", label: "LED" },
  { value: "FLOODLIGHT", label: "Floodlight" },
  { value: "NATURAL", label: "Natural Light" },
  { value: "NONE", label: "No Lighting" },
];

export const COURT_AMENITY_OPTIONS: { value: CourtAmenity; label: string }[] = [
  { value: "ac", label: "AC" },
  { value: "shower", label: "Shower" },
  { value: "locker", label: "Locker" },
];

/** The playing surfaces offered for each sport (keyed by sport code); a sport not listed gets the generic list. */
const SURFACES_BY_SPORT: Record<string, string[]> = {
  BADMINTON: ["Wooden", "Synthetic (PU)", "Vinyl Mat", "Cement"],
  PICKLEBALL: ["Acrylic", "Concrete", "Wooden", "Synthetic"],
  TENNIS: ["Hard Court", "Clay", "Grass", "Synthetic"],
  CRICKET: ["Turf", "Artificial Turf", "Matting", "Cement"],
  FOOTBALL: ["Artificial Turf", "Natural Grass", "Hybrid Turf", "Concrete"],
  BASKETBALL: ["Wooden", "Concrete", "Synthetic", "Rubber"],
};
const GENERIC_SURFACES = ["Wooden", "Synthetic", "Artificial Turf", "Natural Grass", "Concrete", "Other"];

export function surfaceOptionsFor(sportCode: string): string[] {
  return SURFACES_BY_SPORT[sportCode] ?? GENERIC_SURFACES;
}

/** What a brand-new court starts as, per sport (the owner changes whatever differs). */
const COURT_DEFAULTS: Record<string, { type: "INDOOR" | "OUTDOOR"; surface: string; lighting: LightingType }> = {
  BADMINTON: { type: "INDOOR", surface: "Wooden", lighting: "LED" },
  PICKLEBALL: { type: "OUTDOOR", surface: "Acrylic", lighting: "FLOODLIGHT" },
  TENNIS: { type: "OUTDOOR", surface: "Hard Court", lighting: "FLOODLIGHT" },
  CRICKET: { type: "OUTDOOR", surface: "Turf", lighting: "FLOODLIGHT" },
  FOOTBALL: { type: "OUTDOOR", surface: "Artificial Turf", lighting: "FLOODLIGHT" },
  BASKETBALL: { type: "INDOOR", surface: "Wooden", lighting: "LED" },
};
const GENERIC_DEFAULT = { type: "INDOOR" as const, surface: "Wooden", lighting: "LED" as LightingType };

export function courtDefaultsFor(sportCode: string) {
  return COURT_DEFAULTS[sportCode] ?? GENERIC_DEFAULT;
}

export function lightingLabel(value: LightingType | undefined): string {
  return LIGHTING_OPTIONS.find((o) => o.value === value)?.label ?? "";
}
