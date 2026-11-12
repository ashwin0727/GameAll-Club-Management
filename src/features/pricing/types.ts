export type PricingDayType = "ALL_DAYS" | "WEEKDAYS" | "WEEKENDS" | "SPECIFIC_DAYS";
/** A label on a time slot ("Peak" / "Off-Peak"); it does not change the price. */
export type RateTier = "PEAK" | "OFF_PEAK";
/** Who a rate is for: GENERAL sets the booking price; MEMBER and COACHING rates are collected and stored. */
export type PricingAudience = "GENERAL" | "MEMBER" | "COACHING";
export type PricingUnit = "PER_HOUR" | "PER_30_MINUTES" | "PER_SESSION" | "PER_MATCH";

/** A single time-bounded (or full-day) rate window. */
export interface PricingRule {
  id?: string;
  facilitySportId: string;
  /** undefined = sport-level (applies to every playing area that has no override of its own). */
  playingAreaId?: string;
  dayType: PricingDayType;
  /** The chosen days (0 = Sunday .. 6 = Saturday) when dayType is SPECIFIC_DAYS. */
  daysOfWeek?: number[];
  rateTier?: RateTier;
  /** Defaults to GENERAL. */
  audience?: PricingAudience;
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