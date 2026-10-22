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
import { useOnboardingStore } from "@/features/onboarding/state/onboarding-store";
import type { Facility } from "@/features/onboarding/types";
import { FacilityContextCard } from "@/features/sports-setup/components/facility-context-card";
import { SaveStatus } from "@/features/onboarding/components/save-status";
import type { FacilitySport, Sport } from "@/features/sports-setup/types";
import type { PlayingArea } from "@/features/courts-setup/types";
import { playingAreaLabelFor } from "@/features/courts-setup/constants";
import type { OperatingDay } from "@/features/operating-hours/types";
import { clonePeriods, defaultPeriod, rulesToPeriods, type PeriodDraft } from "@/features/pricing/components/types";
import type { PricingDayType, PricingRule } from "@/features/pricing/types";
import { toMinorUnits } from "@/features/pricing/money";
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
  const periods = rulesToPeriods(rules, currency);
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

/**
 * `onDone` turns the form into an in-place editor: saving calls it instead of advancing the onboarding step, so the
 * same pricing form can be used from a popup once the facility is already set up.
 */
export function PricingForm({ onDone }: { onDone?: () => void } = {}) {
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
  // Shown beside Continue when something blocks it — the offending field can be far above the button.
  const [attention, setAttention] = useState<string | null>(null);
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

        // A sport with any court-specific rate is in Individual mode: every court gets a draft, a court that had no
        // rate of its own starting from the sport's rate.
        if (hasOverride) {
          for (const area of areasForSport) {
            overrides[area.id] ??= { active: true, periods: clonePeriods(periods), advancedEnabled, errors: [] };
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

  /** Switch a sport between one default rate and a rate per court. Each side keeps what was typed on it. */
  function handleChangePricingMode(facilitySportId: string, individual: boolean) {
    setSportState((prev) => {
      const sport = prev[facilitySportId]!;
      if (!individual) return { ...prev, [facilitySportId]: { ...sport, customizeAreas: false, errors: [] } };
      const overrides = { ...sport.overrides };
      for (const area of playingAreas.filter((a) => a.facilitySportId === facilitySportId)) {
        if (!overrides[area.id]?.active) {
          overrides[area.id] = { active: true, periods: clonePeriods(sport.periods), advancedEnabled: sport.advancedEnabled, errors: [] };
        }
      }
      return { ...prev, [facilitySportId]: { ...sport, customizeAreas: true, overrides, errors: [] } };
    });
    setDirtyToken((t) => t + 1);
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
      const areasForSport = playingAreas.filter((a) => a.facilitySportId === fs.id);
      const overrides = { ...sport.overrides };
      let sportErrors: string[] = [];

      if (!sport.customizeAreas) {
        // Default rate: one rate for every court of the sport. Individual rates aren't collected or saved.
        const sportRules = periodsToRules(sport.periods, fs.id, undefined, currency);
        const result = validatePricingRules(sportRules, operatingDays ?? undefined);
        if (sportRules.length === 0) result.ruleErrors.push("Set a rate for this sport.");
        sportErrors = result.ruleErrors.length > 0 ? result.ruleErrors : result.overlapError ? [result.overlapError] : [];
        allRules.push(...sportRules);
      } else {
        // Individual rate: every court needs its own rate, and the sport has no default to fill in.
        for (const area of areasForSport) {
          const override = overrides[area.id] ?? { active: true, periods: [defaultPeriod()], advancedEnabled: false, errors: [] };
          const areaRules = periodsToRules(override.periods, fs.id, area.id, currency);
          const result = validatePricingRules(areaRules, operatingDays ?? undefined);
          const errors = result.ruleErrors.length > 0 ? result.ruleErrors : result.overlapError ? [result.overlapError] : [];
          if (areaRules.length === 0) errors.push(`Set a rate for ${area.name}.`);
          overrides[area.id] = { ...override, active: true, errors };
          if (errors.length > 0) hasErrors = true;
          allRules.push(...areaRules);
        }
      }

      nextState[fs.id] = { ...sport, overrides, errors: sportErrors };
      if (sportErrors.length > 0) hasErrors = true;
    }

    setSportState(nextState);
    if (hasErrors) {
      setAttention("Some pricing needs attention — fix the highlighted fields above, then continue.");
      // Take the user to the first problem instead of leaving Continue looking dead.
      requestAnimationFrame(() => document.querySelector("[data-pricing-error]")?.scrollIntoView({ behavior: "smooth", block: "center" }));
      return;
    }
    setAttention(null);

    setIsSaving(true);
    setSaveError(null);

    try {
      await getPricingService().savePricingRules(facility.id, allRules);
      if (onDone) {
        setIsSaving(false);
        onDone();
        return;
      }
      // Setup is completed on the next step, once a payout method has been added.
      await getFacilityService().updateOnboardingStep(facility.id, "PAYMENTS");
      completePricing();
      setIsSaving(false);
      router.push("/onboarding/payments");
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
    return <ErrorState title="Access Denied" message="You don't have access to this facility." />;
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
      periods: sportState[fs.id]?.customizeAreas ? [] : (sportState[fs.id]?.periods ?? []),
      // Each court/turf with its own pricing — what it really charges instead of the sport's rate.
      customized: areasForSport
        .filter((a) => sportState[fs.id]?.customizeAreas && sportState[fs.id]?.overrides[a.id]?.active)
        .map((a) => ({ areaName: a.name, periods: sportState[fs.id]!.overrides[a.id]!.periods })),
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
              individualPricing={state.customizeAreas}
              overrides={state.overrides}
              onChangePeriods={(periods) => updateSport(fs.id, { periods })}
              onToggleAdvanced={(advancedEnabled) => updateSport(fs.id, { advancedEnabled })}
              onChangePricingMode={(individual) => handleChangePricingMode(fs.id, individual)}
              onOverrideChange={(areaId, periods) => handleOverrideChange(fs.id, areaId, periods)}
              onOverrideToggleAdvanced={(areaId, enabled) => handleOverrideToggleAdvanced(fs.id, areaId, enabled)}
              onCopyRequest={() => setCopyDialogSportId(fs.id)}
            />
          );
        })}
      </div>

      <PricingSummary entries={summaryEntries} currency={currency} totalPlayingAreas={playingAreas.length} />

      {attention && <FormMessage>{attention}</FormMessage>}

      <div className="flex items-center justify-between gap-4">
        <SaveStatus dirtyToken={dirtyToken} />
        <SubmitButton
          type="button"
          onClick={handleContinue}
          pending={isSaving}
          pendingLabel="Saving…"
          className="w-auto sm:min-w-[10rem]"
        >
          {onDone ? "Save changes" : "Continue →"}
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