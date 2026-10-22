"use client";

import type { SupabaseClient } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";
import { getFacilityService } from "@/services/facility";
import { getSportsService } from "@/services/sports";
import { getPlayingAreasService } from "@/services/playing-areas";
import { getOperatingHoursService } from "@/services/operating-hours";
import { getPricingService } from "@/services/pricing";
import type { Facility } from "@/features/onboarding/types";
import { groupOperatingDays } from "@/features/operating-hours/summary";
import type { SetupStatus, SetupSummary } from "@/features/onboarding-summary/types";
import {
  buildMissingRequirements,
  computeSetupStatus,
  detectMissingOperatingHours,
  detectMissingPlayingAreas,
  detectMissingPricing,
  detectPartiallyPricedSports,
  detectMissingSports,
  transformPricingSummary,
  transformSportsSummary,
} from "@/features/onboarding-summary/validation";
import type { OnboardingService } from "@/services/onboarding/onboarding.service";
import { ServiceError, mapSupabaseError } from "@/services/shared/service-error";
import type { Database } from "@/types/database.types";

export class SupabaseOnboardingService implements OnboardingService {
  private readonly supabase: SupabaseClient<Database>;

  constructor(client?: SupabaseClient<Database>) {
    this.supabase = client ?? createClient();
  }

  async getSetupSummary(facilityId: string): Promise<SetupSummary> {
    const facility = await getFacilityService().getFacility();
    if (!facility || facility.id !== facilityId) throw new ServiceError("FACILITY_NOT_FOUND");

    const [facilitySports, sports, playingAreas, schedule, plan] = await Promise.all([
      getSportsService().getFacilitySports(facilityId),
      getSportsService().getActiveSports(),
      getPlayingAreasService().getPlayingAreas(facilityId),
      getOperatingHoursService().getFacilitySchedule(facilityId),
      getPricingService().getPricingPlan(facilityId),
    ]);

    const pricingRules = plan?.rules ?? [];
    const missingSports = detectMissingSports(facilitySports);
    const missingPlayingAreas = detectMissingPlayingAreas(playingAreas);
    const missingOperatingHours = detectMissingOperatingHours(schedule);
    const sportsMissingPricing = missingSports ? [] : detectMissingPricing(facilitySports, sports, pricingRules, playingAreas);
    const payout = await this.supabase
      .from("facility_payout_methods" as never)
      .select("id", { count: "exact", head: true })
      .eq("facility_id", facilityId);
    // A failed lookup must not read as "missing" — treat it as present rather than block a finished setup.
    const missingPayout = !payout.error && (payout.count ?? 0) === 0;
    const sportsPartiallyPriced = detectPartiallyPricedSports(facilitySports, sports, pricingRules, playingAreas);

    const missingRequirements = buildMissingRequirements({
      missingSports,
      missingPlayingAreas,
      missingOperatingHours,
      sportsMissingPricing,
      sportsPartiallyPriced,
      missingPayout,
    });

    return {
      facility,
      sports: transformSportsSummary(facilitySports, sports, playingAreas),
      totalSports: facilitySports.length,
      totalPlayingAreas: playingAreas.length,
      operatingHoursGroups: schedule ? groupOperatingDays(schedule.days) : null,
      pricing: transformPricingSummary(facilitySports, sports, playingAreas, pricingRules),
      setupStatus: computeSetupStatus(missingRequirements),
      missingRequirements,
    };
  }

  async validateSetup(facilityId: string): Promise<SetupStatus> {
    const summary = await this.getSetupSummary(facilityId);
    return summary.setupStatus;
  }

  async completeSetup(facilityId: string): Promise<Facility> {
    const { data, error } = await this.supabase.rpc("complete_facility_setup", {
      p_facility_id: facilityId,
    });

    if (error) throw mapSupabaseError(error, { invalid: "SETUP_INCOMPLETE" });
    if (!data) throw new ServiceError("DATABASE_ERROR");

    const facility = await getFacilityService().getFacility();
    if (!facility) throw new ServiceError("DATABASE_ERROR");
    return facility;
  }

  async getOnboardingStatus(facilityId: string): Promise<Facility["onboardingStep"]> {
    const facility = await getFacilityService().getFacility();
    if (!facility || facility.id !== facilityId) throw new ServiceError("FACILITY_NOT_FOUND");
    return facility.onboardingStep;
  }
}