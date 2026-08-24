"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import dynamic from "next/dynamic";
import { useCurrentUser } from "@/features/auth/hooks/use-auth";
import { SubmitButton } from "@/features/auth/components/submit-button";
import { FormMessage } from "@/features/auth/components/form-message";
import { Skeleton } from "@/components/ui/skeleton";
import { getFacilityService } from "@/services/facility";
import { getSportsService } from "@/services/sports";
import { getPlayingAreasService } from "@/services/playing-areas";
import { getOperatingHoursService } from "@/services/operating-hours";
import { getPricingService } from "@/services/pricing";
import { getOnboardingService } from "@/services/onboarding";
import { useOnboardingStore } from "@/features/onboarding/state/onboarding-store";
import type { Facility } from "@/features/onboarding/types";
import { FacilityContextCard } from "@/features/sports-setup/components/facility-context-card";
import { SaveStatus } from "@/features/onboarding/components/save-status";
import type { FacilitySport, Sport } from "@/features/sports-setup/types";
import type { PlayingArea } from "@/features/courts-setup/types";
import { playingAreaLabelFor } from "@/features/courts-setup/constants";
import type { OperatingDay } from "@/features/operating-hours/types";
import { clonePeriods, defaultPeriod, type PeriodDraft } from "@/features/pricing/components/types";
import type { PricingDayType, PricingRule } from "@/features/pricing/types";
import { toMinorUnits, fromMinorUnits } from "@/features/pricing/money";
import { validatePricingRules } from "@/features/pricing/validation";
import { SportPricingCard, type OverrideDraft } from "@/features/pricing/components/sport-pricing-card";
import { CopyPricingDialog } from "@/features/pricing/components/copy-pricing-dialog";
import { PricingSummary } from "@/features/pricing/components/pricing-summary";

const ErrorState = dynamic(() =>
  import("@/components/shared/error-state").then((mod) => mod.ErrorState),
);

type LoadState = "loading" | "ready" | "forbidden";

interface SportPricingState {
  periods: PeriodDraft[];
  advancedEnabled: boolean;
  customizeAreas: boolean;
  overrides: Record<string, OverrideDraft>;
  errors: string[];
}

function toPeriodDrafts(rules: PricingRule[], currency: string): { periods: PeriodDraft[]; advancedEnabled: boolean } {
  if (rules.length === 0) return { periods: [defaultPeriod()], advancedEnabled: false };
  const periods = rules.map((r) => ({
    dayType: r.dayType,
    coversFullDay: r.coversFullDay,
    startTime: r.startTime ?? "06:00",
    endTime: r.endTime ?? "23:00",
    amountInput: String(fromMinorUnits(r.amountMinor, currency)),
  }));
  const advancedEnabled = rules.length > 1 || rules.some((r) => !r.coversFullDay || r.dayType !== "ALL_DAYS");
  return { periods, advancedEnabled };
}

function periodsToRules(
  periods: PeriodDraft[],
  facilitySportId: string,
  playingAreaId: string | undefined,
  currency: string,
): PricingRule[] {
  return periods
    .filter((p) => p.amountInput.trim() !== "")
    .map((p) => ({
      facilitySportId,
      playingAreaId,
      dayType: p.dayType as PricingDayType,
      coversFullDay: p.coversFullDay,
      startTime: p.coversFullDay ? undefined : p.startTime,
      endTime: p.coversFullDay ? undefined : p.endTime,
      amountMinor: toMinorUnits(p.amountInput, currency),
      currency,
      pricingUnit: "PER_HOUR",
      priority: playingAreaId ? 10 : 0,
    }));
}

export function PricingForm() {
  const router = useRouter();
  const { data: user, isLoading: userLoading } = useCurrentUser();
  const completePricing = useOnboardingStore((s) => s.completePricing);

  const [facility, setFacility] = useState<Facility | null>(null);
  const [facilitySports, setFacilitySports] = useState<FacilitySport[]>([]);
  const [sports, setSports] = useState<Sport[]>([]);
  const [playingAreas, setPlayingAreas] = useState<PlayingArea[]>([]);
  const [operatingDays, setOperatingDays] = useState<OperatingDay[] | null>(null);
  const [loadState, setLoadState] = useState<LoadState>("loading");

  const [sportState, setSportState] = useState<Record<string, SportPricingState>>({});
  const [copyDialogSportId, setCopyDialogSportId] = useState<string | null>(null);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [isSaving, setIsSaving] = useState(false);
  const [dirtyToken, setDirtyToken] = useState(0);

  const currency = "INR";

  useEffect(() => {
    if (userLoading) return;
    if (!user) {
      router.replace("/login");
      return;
    }

    let cancelled = false;

    (async () => {
      const loadedFacility = await getFacilityService().getFacility();
      if (cancelled) return;
      if (!loadedFacility) {
        router.replace("/onboarding/facility");
        return;
      }
      if (loadedFacility.ownerId !== user.id) {
        setLoadState("forbidden");
        return;
      }

      const [availableSports, facSports] = await Promise.all([
        getSportsService().getActiveSports(),
        getSportsService().getFacilitySports(loadedFacility.id),
      ]);
      if (cancelled) return;
      if (facSports.length === 0) {
        router.replace("/onboarding/sports");
        return;
      }

      const areas = await getPlayingAreasService().getPlayingAreas(loadedFacility.id);
      if (cancelled) return;
      if (areas.length === 0) {
        router.replace("/onboarding/courts");
        return;
      }

      const [schedule, plan] = await Promise.all([
        getOperatingHoursService().getFacilitySchedule(loadedFacility.id),
        getPricingService().getPricingPlan(loadedFacility.id),
      ]);
      if (cancelled) return;

      const rules = plan?.rules ?? [];
      const nextState: Record<string, SportPricingState> = {};
      for (const fs of facSports) {
        const sportRules = rules.filter((r) => r.facilitySportId === fs.id && !r.playingAreaId);
        const { periods, advancedEnabled } = toPeriodDrafts(sportRules, currency);

        const areasForSport = areas.filter((a) => a.facilitySportId === fs.id);
        const overrides: Record<string, OverrideDraft> = {};
        let hasOverride = false;
        for (const area of areasForSport) {
          const areaRules = rules.filter((r) => r.facilitySportId === fs.id && r.playingAreaId === area.id);
          if (areaRules.length > 0) {
            hasOverride = true;
            const { periods: areaPeriods, advancedEnabled: areaAdvanced } = toPeriodDrafts(areaRules, currency);
            overrides[area.id] = { active: true, periods: areaPeriods, advancedEnabled: areaAdvanced, errors: [] };
          }
        }

        nextState[fs.id] = { periods, advancedEnabled, customizeAreas: hasOverride, overrides, errors: [] };
      }

      setFacility(loadedFacility);
      setFacilitySports(facSports);
      setSports(availableSports);
      setPlayingAreas(areas);
      setOperatingDays(schedule?.days ?? null);
      setSportState(nextState);
      setLoadState("ready");
    })();

    return () => {
      cancelled = true;
    };
  }, [user, userLoading, router]);

  function updateSport(facilitySportId: string, patch: Partial<SportPricingState>) {
    setSportState((prev) => ({ ...prev, [facilitySportId]: { ...prev[facilitySportId]!, ...patch, errors: [] } }));
    setDirtyToken((t) => t + 1);
  }

  function handleCustomizeArea(facilitySportId: string, areaId: string) {
    setSportState((prev) => {
      const sport = prev[facilitySportId]!;
      if (sport.overrides[areaId]?.active) return prev;
      return {
        ...prev,
        [facilitySportId]: {
          ...sport,
          overrides: {
            ...sport.overrides,
            [areaId]: {
              active: true,
              periods: clonePeriods(sport.periods),
              advancedEnabled: sport.advancedEnabled,
              errors: [],
            },
          },
        },
      };
    });
  }

  function handleUseDefaultForArea(facilitySportId: string, areaId: string) {
    setSportState((prev) => {
      const sport = prev[facilitySportId]!;
      const overrides = { ...sport.overrides };
      delete overrides[areaId];
      return { ...prev, [facilitySportId]: { ...sport, overrides } };
    });
  }

  function handleOverrideChange(facilitySportId: string, areaId: string, periods: PeriodDraft[]) {
    setSportState((prev) => {
      const sport = prev[facilitySportId]!;
      const existing = sport.overrides[areaId]!;
      return {
        ...prev,
        [facilitySportId]: {
          ...sport,
          overrides: { ...sport.overrides, [areaId]: { ...existing, periods, errors: [] } },
        },
      };
    });
  }

  function handleOverrideToggleAdvanced(facilitySportId: string, areaId: string, enabled: boolean) {
    setSportState((prev) => {
      const sport = prev[facilitySportId]!;
      const existing = sport.overrides[areaId]!;
      return {
        ...prev,
        [facilitySportId]: {
          ...sport,
          overrides: { ...sport.overrides, [areaId]: { ...existing, advancedEnabled: enabled } },
        },
      };
    });
  }

  function handleCopy(fromSportId: string, toSportIds: string[]) {
    setSportState((prev) => {
      const source = prev[fromSportId]!;
      const next = { ...prev };
      for (const targetId of toSportIds) {
        next[targetId] = {
          ...next[targetId]!,
          periods: clonePeriods(source.periods),
          advancedEnabled: source.advancedEnabled,
          errors: [],
        };
      }
      return next;
    });
    setDirtyToken((t) => t + 1);
  }

  async function handleContinue() {
    if (!facility) return;

    let hasErrors = false;
    const nextState = { ...sportState };
    const allRules: PricingRule[] = [];

    for (const fs of facilitySports) {
      const sport = nextState[fs.id]!;
      const sportRules = periodsToRules(sport.periods, fs.id, undefined, currency);
      const sportResult = validatePricingRules(sportRules, operatingDays ?? undefined);
      if (sportRules.length === 0) sportResult.ruleErrors.push("Set a rate for this sport.");

      const overrides = { ...sport.overrides };
      for (const [areaId, override] of Object.entries(overrides)) {
        const areaRules = periodsToRules(override.periods, fs.id, areaId, currency);
        const areaResult = validatePricingRules(areaRules, operatingDays ?? undefined);
        overrides[areaId] = { ...override, errors: areaResult.ruleErrors.length > 0 ? areaResult.ruleErrors : areaResult.overlapError ? [areaResult.overlapError] : [] };
        if (!areaResult.isValid || areaRules.length === 0) hasErrors = true;
        allRules.push(...areaRules);
      }

      const errors = sportResult.ruleErrors.length > 0 ? sportResult.ruleErrors : sportResult.overlapError ? [sportResult.overlapError] : [];
      nextState[fs.id] = { ...sport, overrides, errors };
      if (errors.length > 0) hasErrors = true;
      allRules.push(...sportRules);
    }

    setSportState(nextState);
    if (hasErrors) return;

    setIsSaving(true);
    setSaveError(null);

    try {
      await getPricingService().savePricingRules(facility.id, allRules);
      // Goes through the complete_facility_setup RPC (not a raw onboarding_step
      // write) so profiles.onboarding_completed is flipped in the same
      // transaction — otherwise the next sign-in would send the owner right
      // back into onboarding despite the facility being fully set up.
      await getOnboardingService().completeSetup(facility.id);
      completePricing();
      setIsSaving(false);
      router.push("/onboarding/complete");
    } catch {
      setSaveError("Unable to save pricing. Please try again.");
      setIsSaving(false);
    }
  }

  if (userLoading || loadState === "loading") {
    return (
      <div className="space-y-6">
        <p className="text-sm text-muted-foreground">Loading pricing…</p>
        <Skeleton className="h-24 w-full rounded-xl" />
        {Array.from({ length: 3 }).map((_, i) => (
          <Skeleton key={i} className="h-40 w-full rounded-xl" />
        ))}
      </div>
    );
  }

  if (loadState === "forbidden") {
    return <ErrorState title="Access denied" message="You don't have access to this facility." />;
  }

  if (!facility) return null;

  const summaryEntries = facilitySports.map((fs) => {
    const sport = sports.find((s) => s.id === fs.sportId);
    const areasForSport = playingAreas.filter((a) => a.facilitySportId === fs.id);
    const label = playingAreaLabelFor(sport?.code ?? "OTHER");
    return {
      sportName: sport?.name ?? "Sport",
      areaLabel: label,
      areaCount: areasForSport.length,
      defaultPeriod: sportState[fs.id]?.periods[0],
    };
  });

  const copySourceSport = copyDialogSportId ? sports.find((s) => s.id === facilitySports.find((fs) => fs.id === copyDialogSportId)?.sportId) : null;

  return (
    <div className="space-y-8">
      <FacilityContextCard facility={facility} />

      {saveError && <FormMessage>{saveError}</FormMessage>}

      <div className="space-y-5">
        {facilitySports.map((fs) => {
          const sport = sports.find((s) => s.id === fs.sportId);
          const state = sportState[fs.id];
          if (!sport || !state) return null;
          const areasForSport = playingAreas.filter((a) => a.facilitySportId === fs.id);
          const label = playingAreaLabelFor(sport.code);

          return (
            <SportPricingCard
              key={fs.id}
              sportName={fs.customSportName || sport.name}
              sportIcon={sport.icon}
              areaLabel={label}
              playingAreas={areasForSport}
              currency={currency}
              periods={state.periods}
              advancedEnabled={state.advancedEnabled}
              errors={state.errors}
              customizeAreas={state.customizeAreas}
              overrides={state.overrides}
              onChangePeriods={(periods) => updateSport(fs.id, { periods })}
              onToggleAdvanced={(advancedEnabled) => updateSport(fs.id, { advancedEnabled })}
              onToggleCustomizeAreas={(customizeAreas) => updateSport(fs.id, { customizeAreas })}
              onCustomizeArea={(areaId) => handleCustomizeArea(fs.id, areaId)}
              onUseDefaultForArea={(areaId) => handleUseDefaultForArea(fs.id, areaId)}
              onOverrideChange={(areaId, periods) => handleOverrideChange(fs.id, areaId, periods)}
              onOverrideToggleAdvanced={(areaId, enabled) => handleOverrideToggleAdvanced(fs.id, areaId, enabled)}
              onCopyRequest={() => setCopyDialogSportId(fs.id)}
            />
          );
        })}
      </div>

      <PricingSummary entries={summaryEntries} currency={currency} totalPlayingAreas={playingAreas.length} />

      <div className="flex items-center justify-between gap-4">
        <SaveStatus dirtyToken={dirtyToken} />
        <SubmitButton
          type="button"
          onClick={handleContinue}
          pending={isSaving}
          pendingLabel="Saving…"
          className="w-auto sm:min-w-[10rem]"
        >
          Continue →
        </SubmitButton>
      </div>

      {copyDialogSportId && copySourceSport && (
        <CopyPricingDialog
          open={Boolean(copyDialogSportId)}
          onOpenChange={(open) => {
            if (!open) setCopyDialogSportId(null);
          }}
          fromLabel={copySourceSport.name}
          targets={facilitySports
            .filter((fs) => fs.id !== copyDialogSportId)
            .map((fs) => ({ id: fs.id, label: sports.find((s) => s.id === fs.sportId)?.name ?? "Sport" }))}
          onCopy={(targetIds) => handleCopy(copyDialogSportId, targetIds)}
        />
      )}
    </div>
  );
}