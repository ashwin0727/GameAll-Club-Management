import { playingAreaLabelFor } from "@/features/courts-setup/constants";
import type { PlayingArea } from "@/features/courts-setup/types";
import type { OperatingSchedule } from "@/features/operating-hours/types";
import type { PricingRule } from "@/features/pricing/types";
import type { FacilitySport, Sport } from "@/features/sports-setup/types";
import type {
  MissingRequirement,
  PricingSummaryEntry,
  SetupStatus,
  SportSummaryEntry,
} from "@/features/onboarding-summary/types";

export function detectMissingSports(facilitySports: FacilitySport[]): boolean {
  return facilitySports.length === 0;
}

export function detectMissingPlayingAreas(playingAreas: PlayingArea[]): boolean {
  return playingAreas.length === 0;
}

export function detectMissingOperatingHours(schedule: OperatingSchedule | null): boolean {
  if (!schedule) return true;
  return !schedule.days.some((day) => !day.isClosed);
}

/** Sport names that have no sport-level default rate configured. */
export function detectMissingPricing(
  facilitySports: FacilitySport[],
  sports: Sport[],
  pricingRules: PricingRule[],
): string[] {
  const missing: string[] = [];
  for (const fs of facilitySports) {
    const hasSportLevelRule = pricingRules.some((r) => r.facilitySportId === fs.id && !r.playingAreaId);
    if (!hasSportLevelRule) {
      const sport = sports.find((s) => s.id === fs.sportId);
      missing.push(fs.customSportName || sport?.name || "this sport");
    }
  }
  return missing;
}

export function computeSetupStatus(missingRequirements: MissingRequirement[]): SetupStatus {
  return missingRequirements.length === 0 ? "READY" : "ACTION_REQUIRED";
}

export function buildMissingRequirements(input: {
  missingSports: boolean;
  missingPlayingAreas: boolean;
  missingOperatingHours: boolean;
  sportsMissingPricing: string[];
}): MissingRequirement[] {
  const requirements: MissingRequirement[] = [];

  if (input.missingSports) {
    requirements.push({
      code: "SPORTS",
      message: "No sports have been added to this facility.",
      actionLabel: "Fix Sports",
      actionHref: "/onboarding/sports",
    });
  }
  if (input.missingPlayingAreas) {
    requirements.push({
      code: "PLAYING_AREAS",
      message: "No courts or turfs have been added.",
      actionLabel: "Fix Courts & Turfs",
      actionHref: "/onboarding/courts",
    });
  }
  if (input.missingOperatingHours) {
    requirements.push({
      code: "OPERATING_HOURS",
      message: "Operating hours have not been configured.",
      actionLabel: "Fix Operating Hours",
      actionHref: "/onboarding/operating-hours",
    });
  }
  for (const sportName of input.sportsMissingPricing) {
    requirements.push({
      code: "PRICING",
      message: `Pricing has not been configured for ${sportName}.`,
      actionLabel: "Fix Pricing",
      actionHref: "/onboarding/pricing",
    });
  }

  return requirements;
}

export function transformSportsSummary(
  facilitySports: FacilitySport[],
  sports: Sport[],
  playingAreas: PlayingArea[],
): SportSummaryEntry[] {
  return facilitySports.map((fs) => {
    const sport = sports.find((s) => s.id === fs.sportId);
    const areasForSport = playingAreas.filter((a) => a.facilitySportId === fs.id);
    return {
      facilitySportId: fs.id,
      sportName: fs.customSportName || sport?.name || "Sport",
      sportIcon: sport?.icon ?? "🏅",
      areaLabel: playingAreaLabelFor(sport?.code ?? "OTHER"),
      playingAreas: areasForSport.map((a) => ({ id: a.id, name: a.name })),
    };
  });
}

/**
 * The "default" shown per sport is its sport-level, always-applicable rate
 * (ALL_DAYS + full day) if one exists, otherwise the first sport-level rule
 * found — matching the priority resolvePrice() itself uses elsewhere.
 */
export function transformPricingSummary(
  facilitySports: FacilitySport[],
  sports: Sport[],
  playingAreas: PlayingArea[],
  pricingRules: PricingRule[],
): PricingSummaryEntry[] {
  return facilitySports.map((fs) => {
    const sport = sports.find((s) => s.id === fs.sportId);
    const sportRules = pricingRules.filter((r) => r.facilitySportId === fs.id && !r.playingAreaId);
    const defaultRule = sportRules.find((r) => r.dayType === "ALL_DAYS" && r.coversFullDay) ?? sportRules[0];

    const overrides: PricingSummaryEntry["overrides"] = [];
    const overriddenAreaIds = new Set(
      pricingRules.filter((r) => r.facilitySportId === fs.id && r.playingAreaId).map((r) => r.playingAreaId),
    );
    for (const areaId of overriddenAreaIds) {
      const areaRule = pricingRules.find(
        (r) => r.facilitySportId === fs.id && r.playingAreaId === areaId && r.dayType === "ALL_DAYS" && r.coversFullDay,
      ) ?? pricingRules.find((r) => r.facilitySportId === fs.id && r.playingAreaId === areaId);
      if (!areaRule) continue;
      const area = playingAreas.find((a) => a.id === areaId);
      overrides.push({
        playingAreaId: areaId!,
        playingAreaName: area?.name ?? "Playing area",
        amountMinor: areaRule.amountMinor,
      });
    }

    return {
      facilitySportId: fs.id,
      sportName: fs.customSportName || sport?.name || "Sport",
      defaultAmountMinor: defaultRule?.amountMinor ?? null,
      currency: defaultRule?.currency ?? "INR",
      overrides,
    };
  });
}