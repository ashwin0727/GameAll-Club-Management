export type PricingDayType = "ALL_DAYS" | "WEEKDAYS" | "WEEKENDS";
export type PricingUnit = "PER_HOUR" | "PER_30_MINUTES" | "PER_SESSION" | "PER_MATCH";

/** A single time-bounded (or full-day) rate window. */
export interface PricingRule {
  id?: string;
  facilitySportId: string;
  /** undefined = sport-level (applies to every playing area that has no override of its own). */
  playingAreaId?: string;
  dayType: PricingDayType;
  coversFullDay: boolean;
  /** "HH:MM", present only when !coversFullDay. */
  startTime?: string;
  endTime?: string;
  amountMinor: number;
  currency: string;
  pricingUnit: PricingUnit;
  priority: number;
}

export interface PricingPlan {
  id: string;
  facilityId: string;
  name: string;
  currency: string;
  status: "ACTIVE" | "INACTIVE";
  rules: PricingRule[];
  createdAt: string;
  updatedAt: string;
}