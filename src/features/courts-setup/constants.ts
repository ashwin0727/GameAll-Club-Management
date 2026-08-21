export type PlayingAreaLabel = "Court" | "Turf" | "Playing Area";

/** Keyed by Sport.code (the global sport catalog). Drives every piece of
 * dynamic terminology in this feature — never hardcode "Court" elsewhere. */
export const PLAYING_AREA_LABEL: Record<string, PlayingAreaLabel> = {
  BADMINTON: "Court",
  PICKLEBALL: "Court",
  TENNIS: "Court",
  CRICKET: "Turf",
  FOOTBALL: "Turf",
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