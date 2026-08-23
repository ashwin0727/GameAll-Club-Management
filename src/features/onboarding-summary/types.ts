import type { Facility } from "@/features/onboarding/types";
import type { OperatingHoursSummaryGroup } from "@/features/operating-hours/summary";
import type { PlayingAreaLabel } from "@/features/courts-setup/constants";

export type SetupStatus = "READY" | "ACTION_REQUIRED";

export type MissingRequirementCode = "SPORTS" | "PLAYING_AREAS" | "OPERATING_HOURS" | "PRICING";

export interface MissingRequirement {
  code: MissingRequirementCode;
  message: string;
  actionLabel: string;
  actionHref: string;
}

export interface SportSummaryEntry {
  facilitySportId: string;
  sportName: string;
  sportIcon: string;
  areaLabel: PlayingAreaLabel;
  playingAreas: { id: string; name: string }[];
}

export interface PricingOverrideEntry {
  playingAreaId: string;
  playingAreaName: string;
  amountMinor: number;
}

export interface PricingSummaryEntry {
  facilitySportId: string;
  sportName: string;
  defaultAmountMinor: number | null;
  currency: string;
  overrides: PricingOverrideEntry[];
}

export interface SetupSummary {
  facility: Facility;
  sports: SportSummaryEntry[];
  totalSports: number;
  totalPlayingAreas: number;
  operatingHoursGroups: OperatingHoursSummaryGroup[] | null;
  pricing: PricingSummaryEntry[];
  setupStatus: SetupStatus;
  missingRequirements: MissingRequirement[];
}