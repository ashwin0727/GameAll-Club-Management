/** The global sport catalog — never facility-specific. */
export interface Sport {
  id: string;
  name: string;
  code: string;
  /** A single emoji character, rendered directly by SportCard. */
  icon: string;
  description: string;
  isActive: boolean;
}

/**
 * "This facility operates this sport." The only place facilityId and
 * sportId meet — kept deliberately separate from Sport (which stays
 * global). customSportName is the one facility-specific attribute this
 * relationship needs (only set when sportId is the Other sport), not a
 * merge of the two models.
 */
export interface FacilitySport {
  id: string;
  facilityId: string;
  sportId: string;
  enabled: boolean;
  customSportName?: string;
  createdAt: string;
  updatedAt: string;
}

export type FacilitySportInput = Omit<FacilitySport, "id" | "createdAt" | "updatedAt">;