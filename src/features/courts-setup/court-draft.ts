import { courtDefaultsFor, playingAreaLabelFor } from "@/features/courts-setup/constants";
import type { CourtAmenity, LightingType, PlayingArea } from "@/features/courts-setup/types";

/** A court as it is edited on the Sports & Courts page, before it is saved. */
export interface CourtDraft {
  /** Stable id for the editing session (the database id once saved). */
  id: string;
  /** Set when the court already exists in the database. */
  savedId?: string;
  sportId: string;
  name: string;
  type: "INDOOR" | "OUTDOOR";
  surface: string;
  lighting: LightingType | "";
  amenities: CourtAmenity[];
}

/** The settings shared by every court of a sport in "Bulk" mode. */
export type CourtSettings = Pick<CourtDraft, "type" | "surface" | "lighting" | "amenities">;

export function draftFromPlayingArea(area: PlayingArea, sportCode: string): CourtDraft {
  const defaults = courtDefaultsFor(sportCode);
  return {
    id: area.id,
    savedId: area.id,
    sportId: area.sportId,
    name: area.name,
    type: area.type,
    // a court saved before surface / lighting were asked starts from the sport's usual values, which the owner confirms
    surface: area.surface || defaults.surface,
    lighting: area.lighting ?? defaults.lighting,
    amenities: area.amenities ?? [],
  };
}

/** "Court 3" / "Turf 2": numbered after the highest number already used for the sport (not the count, so a removal never repeats a name). */
export function nextCourtName(sportCode: string, existingNames: string[]): string {
  const label = playingAreaLabelFor(sportCode);
  const used = existingNames.map((n) => {
    const match = /(\d+)\s*$/.exec(n.trim());
    return match ? Number(match[1]) : 0;
  });
  return `${label} ${(used.length > 0 ? Math.max(...used) : 0) + 1}`;
}

/** A new court copies the sport's last court (so "add another" is one click), else the sport's usual defaults. */
export function newCourtDraft(opts: { id: string; sportId: string; sportCode: string; sportName: string; existing: CourtDraft[] }): CourtDraft {
  const forSport = opts.existing.filter((c) => c.sportId === opts.sportId);
  const last = forSport[forSport.length - 1];
  const defaults = courtDefaultsFor(opts.sportCode);
  const base = nextCourtName(opts.sportCode, forSport.map((c) => c.name));
  // e.g. "Badminton Court 1": the sport's name reads better in the table than a bare "Court 1"
  const name = opts.sportCode === "OTHER" ? base : `${opts.sportName} ${base}`;
  return {
    id: opts.id,
    sportId: opts.sportId,
    name,
    type: last?.type ?? defaults.type,
    surface: last?.surface ?? defaults.surface,
    lighting: last?.lighting ?? defaults.lighting,
    amenities: last ? [...last.amenities] : [],
  };
}

export function applyToSport(drafts: CourtDraft[], sportId: string, patch: Partial<CourtSettings>): CourtDraft[] {
  return drafts.map((c) => (c.sportId === sportId ? { ...c, ...patch } : c));
}

export interface CourtProblems {
  /** problems keyed by court id, then by field */
  byCourt: Record<string, { name?: string; surface?: string; lighting?: string }>;
  /** a sport with no court at all */
  bySport: Record<string, string>;
  ok: boolean;
}

export function validateCourtDrafts(drafts: CourtDraft[], sports: { id: string; name: string; code: string }[]): CourtProblems {
  const byCourt: CourtProblems["byCourt"] = {};
  const bySport: CourtProblems["bySport"] = {};
  const seen = new Map<string, Set<string>>();

  for (const court of drafts) {
    const problems: { name?: string; surface?: string; lighting?: string } = {};
    const name = court.name.trim();
    if (name.length < 2 || name.length > 50) {
      problems.name = "Name must be between 2 and 50 characters.";
    } else {
      const set = seen.get(court.sportId) ?? new Set<string>();
      if (set.has(name.toLowerCase())) problems.name = "This name is already used for this sport.";
      set.add(name.toLowerCase());
      seen.set(court.sportId, set);
    }
    if (!court.surface.trim()) problems.surface = "Select a surface.";
    if (!court.lighting) problems.lighting = "Select lighting.";
    if (Object.keys(problems).length > 0) byCourt[court.id] = problems;
  }

  for (const sport of sports) {
    if (!drafts.some((c) => c.sportId === sport.id)) {
      bySport[sport.id] = `Add at least one ${playingAreaLabelFor(sport.code).toLowerCase()} for ${sport.name}.`;
    }
  }
  return { byCourt, bySport, ok: Object.keys(byCourt).length === 0 && Object.keys(bySport).length === 0 };
}
