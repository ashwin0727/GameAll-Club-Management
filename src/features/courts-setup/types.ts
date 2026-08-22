export interface PlayingArea {
  id: string;
  facilityId: string;
  facilitySportId: string;
  sportId: string;
  name: string;
  type: "INDOOR" | "OUTDOOR";
  status: "ACTIVE" | "INACTIVE";
  bookingEnabled: boolean;
  /**
   * Separate from `status`. Status is a legitimate, owner-set, always-
   * visible toggle ("this court exists but isn't bookable right now").
   * `archived` means "removed from the onboarding list" — set by Remove
   * on an already-saved playing area. Archived rows are excluded from
   * every read the UI displays but never hard-deleted, preserving
   * history for future reporting/booking modules.
   */
  archived: boolean;
  displayOrder: number;
  createdAt: string;
  updatedAt: string;
}

export type PlayingAreaInput = Omit<PlayingArea, "createdAt" | "updatedAt">;