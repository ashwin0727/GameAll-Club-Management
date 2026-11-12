"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import dynamic from "next/dynamic";
import {
  ArrowLeft,
  ArrowRight,
  FileText,
  Layers,
  LayoutGrid,
  Loader2,
} from "lucide-react";
import { toast } from "sonner";
import { Skeleton } from "@/components/ui/skeleton";
import { FormMessage } from "@/features/auth/components/form-message";
import { useCurrentUser } from "@/features/auth/hooks/use-auth";
import type { PlayingArea } from "@/features/courts-setup/types";
import { ChoiceCards } from "@/features/onboarding/components/setup-choice-cards";
import { useOnboardingStore } from "@/features/onboarding/state/onboarding-store";
import type { Facility } from "@/features/onboarding/types";
import type { OperatingDay } from "@/features/operating-hours/types";
import {
  PricingPreviewCard,
  PricingSettingsCard,
} from "@/features/pricing/setup/pricing-side";
import {
  DEFAULT_PRICING_SETTINGS,
  cloneSetup,
  emptySetup,
  hasSetupProblems,
  openSpan,
  rulesFromSetup,
  setupFromRules,
  validateSetup,
  type PriceSetup,
  type PricingMode,
  type PricingSettings,
  type SetupProblems,
} from "@/features/pricing/setup/pricing-setup-model";
import {
  CourtList,
  CourtPricingPanel,
  SportPricingView,
  type CourtEntry,
  type SportEntry,
} from "@/features/pricing/setup/pricing-views";
import { CUSTOM_SPORT_ICON } from "@/features/sports-courts/components/sports-picker";
import { OTHER_SPORT_CODE } from "@/features/sports-setup/constants";
import type { FacilitySport, Sport } from "@/features/sports-setup/types";
import { getFacilityService } from "@/services/facility";
import { getOperatingHoursService } from "@/services/operating-hours";
import { getPlayingAreasService } from "@/services/playing-areas";
import { getPricingService } from "@/services/pricing";
import { getSportsService } from "@/services/sports";

const ErrorState = dynamic(() =>
  import("@/components/shared/error-state").then((mod) => mod.ErrorState),
);

type LoadState = "loading" | "ready" | "forbidden";

const priced = (s: PriceSetup | undefined) => !!s && Number(s.basePrice) > 0;

/**
 * Pricing (setup step 4): By Sport (one set of prices per sport, applied to all its courts) or By Court (each court on its own).
 * Each has a base price, optional time slots for weekdays / weekends / chosen days, and optional member and coaching rates.
 * Everything is saved together on Next (or Save as Draft).
 */
export function PricingSetupForm({ onDone }: { onDone?: () => void } = {}) {
  const editing = !!onDone;
  const router = useRouter();
  const { data: user, isLoading: userLoading } = useCurrentUser();
  const completePricing = useOnboardingStore((s) => s.completePricing);

  const [facility, setFacility] = React.useState<Facility | null>(null);
  const [sports, setSports] = React.useState<Sport[]>([]);
  const [facilitySports, setFacilitySports] = React.useState<FacilitySport[]>(
    [],
  );
  const [areas, setAreas] = React.useState<PlayingArea[]>([]);
  const [operatingDays, setOperatingDays] = React.useState<
    OperatingDay[] | null
  >(null);
  const [loadState, setLoadState] = React.useState<LoadState>("loading");

  const [settings, setSettings] = React.useState<PricingSettings>(
    DEFAULT_PRICING_SETTINGS,
  );
  const [sportSetups, setSportSetups] = React.useState<
    Record<string, PriceSetup>
  >({});
  const [courtSetups, setCourtSetups] = React.useState<
    Record<string, PriceSetup>
  >({});
  const [expandedSport, setExpandedSport] = React.useState<string | null>(null);
  const [selectedCourt, setSelectedCourt] = React.useState<string | null>(null);
  const [courtFilter, setCourtFilter] = React.useState("ALL");

  const [problems, setProblems] = React.useState<Record<string, SetupProblems>>(
    {},
  );
  const [saveError, setSaveError] = React.useState<string | null>(null);
  const [saving, setSaving] = React.useState<"draft" | "next" | null>(null);

  const span = React.useMemo(() => openSpan(operatingDays), [operatingDays]);

  // ── load ──────────────────────────────────────────────────────────
  React.useEffect(() => {
    if (userLoading) return;
    if (!user) {
      router.replace("/login");
      return;
    }
    let cancelled = false;

    (async () => {
      try {
        const loaded = await getFacilityService().getFacility();
        if (cancelled) return;
        if (!loaded) {
          router.replace("/onboarding/facility");
          return;
        }
        if (loaded.ownerId !== user.id) {
          setLoadState("forbidden");
          return;
        }
        const [catalogue, facSports] = await Promise.all([
          getSportsService().getActiveSports(),
          getSportsService().getFacilitySports(loaded.id),
        ]);
        if (cancelled) return;
        const courts = await getPlayingAreasService().getPlayingAreas(
          loaded.id,
        );
        if (cancelled) return;
        if (facSports.length === 0 || courts.length === 0) {
          router.replace("/onboarding/sports");
          return;
        }
        const [schedule, plan] = await Promise.all([
          getOperatingHoursService().getFacilitySchedule(loaded.id),
          getPricingService().getPricingPlan(loaded.id),
        ]);
        if (cancelled) return;

        const rules = plan?.rules ?? [];
        const loadedSpan = openSpan(schedule?.days ?? null);
        const saved = loaded.pricingSettings ?? DEFAULT_PRICING_SETTINGS;

        const sportMap: Record<string, PriceSetup> = {};
        for (const fs of facSports)
          sportMap[fs.id] = setupFromRules(
            rules.filter(
              (r) => r.facilitySportId === fs.id && !r.playingAreaId,
            ),
            loadedSpan,
          );
        const courtMap: Record<string, PriceSetup> = {};
        for (const c of courts) {
          const own = rules.filter((r) => r.playingAreaId === c.id);
          // a court with no rate of its own starts from its sport's, so switching to By Court is one click
          courtMap[c.id] =
            own.length > 0
              ? setupFromRules(own, loadedSpan)
              : cloneSetup(sportMap[c.facilitySportId] ?? emptySetup());
        }

        setFacility(loaded);
        setSports(catalogue);
        setFacilitySports(facSports);
        setAreas(courts);
        setOperatingDays(schedule?.days ?? null);
        setSettings(saved);
        setSportSetups(sportMap);
        setCourtSetups(courtMap);
        setExpandedSport(
          facSports.find((fs) => !priced(sportMap[fs.id]))?.id ??
            facSports[0]?.id ??
            null,
        );
        setSelectedCourt(courts[0]?.id ?? null);
        setLoadState("ready");
      } catch {
        if (!cancelled) {
          setSaveError(
            "We couldn't load your pricing. Please refresh and try again.",
          );
          setLoadState("ready");
        }
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [user, userLoading, router]);

  const sportEntries: SportEntry[] = facilitySports.map((fs) => {
    const sport = sports.find((s) => s.id === fs.sportId);
    const isCustom = sport?.code === OTHER_SPORT_CODE;
    return {
      id: fs.id,
      name: isCustom
        ? (fs.customSportName ?? "Sport")
        : (sport?.name ?? "Sport"),
      icon: isCustom ? CUSTOM_SPORT_ICON : (sport?.icon ?? CUSTOM_SPORT_ICON),
    };
  });
  const courtEntries: CourtEntry[] = areas.map((a) => ({
    id: a.id,
    name: a.name,
    sportId: a.facilitySportId,
    type: a.type,
    surface: a.surface,
    ac: (a.amenities ?? []).includes("ac"),
  }));

  // ── editing ───────────────────────────────────────────────────────
  function clearProblemsFor(id: string) {
    setProblems((prev) => {
      if (!prev[id]) return prev;
      const next = { ...prev };
      delete next[id];
      return next;
    });
    setSaveError(null);
  }

  function changeSport(id: string, next: PriceSetup) {
    setSportSetups((prev) => ({ ...prev, [id]: next }));
    clearProblemsFor(id);
  }

  function changeCourt(id: string, next: PriceSetup) {
    setCourtSetups((prev) => ({ ...prev, [id]: next }));
    clearProblemsFor(id);
  }

  function setMode(mode: PricingMode) {
    if (mode === "BY_COURT") {
      // a court with nothing entered yet starts from its sport's price as it is now
      setCourtSetups((prev) => {
        const next = { ...prev };
        for (const c of areas) {
          const own = prev[c.id];
          const sportSetup = sportSetups[c.facilitySportId];
          if (priced(sportSetup) && (!own || (own.basePrice.trim() === "" && !own.timeBased))) next[c.id] = cloneSetup(sportSetup!);
        }
        return next;
      });
    }
    setSettings((s) => ({ ...s, mode }));
    setProblems({});
    setSaveError(null);
  }

  function addSportPricing() {
    const next = facilitySports.find((fs) => !priced(sportSetups[fs.id]));
    if (next) setExpandedSport(next.id);
  }

  // ── save ──────────────────────────────────────────────────────────
  async function persist(advance: boolean) {
    if (!facility) return;
    setSaveError(null);

    const found: Record<string, SetupProblems> = {};
    const scopes =
      settings.mode === "BY_SPORT"
        ? facilitySports.map((fs) => ({
            id: fs.id,
            setup: sportSetups[fs.id] ?? emptySetup(),
            scope: { facilitySportId: fs.id },
          }))
        : areas.map((a) => ({
            id: a.id,
            setup: courtSetups[a.id] ?? emptySetup(),
            scope: { facilitySportId: a.facilitySportId, playingAreaId: a.id },
          }));
    for (const s of scopes) {
      const p = validateSetup(s.setup, s.scope, settings, operatingDays);
      if (hasSetupProblems(p)) found[s.id] = p;
    }
    setProblems(found);
    const firstBad = Object.keys(found)[0];
    if (firstBad) {
      if (settings.mode === "BY_SPORT") setExpandedSport(firstBad);
      else setSelectedCourt(firstBad);
      const name =
        settings.mode === "BY_SPORT"
          ? sportEntries.find((s) => s.id === firstBad)?.name
          : areas.find((a) => a.id === firstBad)?.name;
      setSaveError(
        `Please fix the highlighted fields to continue${name ? ` (${name})` : ""}.`,
      );
      return;
    }

    setSaving(advance ? "next" : "draft");
    try {
      const rules = scopes.flatMap((s) =>
        rulesFromSetup(s.setup, s.scope, settings),
      );
      await getPricingService().savePricingRules(facility.id, rules);
      await getFacilityService().updateFacility(facility.id, {
        pricingSettings: settings,
      });
      if (advance && editing) {
        toast.success("Pricing saved");
        onDone?.();
      } else if (advance) {
        await getFacilityService().updateOnboardingStep(
          facility.id,
          "PAYMENTS",
        );
        completePricing();
        router.push("/onboarding/payments");
      } else {
        toast.success("Draft saved. You can pick up where you left off.");
      }
    } catch (e) {
      setSaveError(
        e instanceof Error && e.message
          ? e.message
          : "We couldn't save your pricing. Please try again.",
      );
    } finally {
      setSaving(null);
    }
  }

  // ── render ────────────────────────────────────────────────────────
  if (userLoading || loadState === "loading") {
    return (
      <div className="space-y-5">
        <Skeleton className="h-20 w-full rounded-2xl" />
        <Skeleton className="h-64 w-full rounded-2xl" />
      </div>
    );
  }
  if (loadState === "forbidden")
    return (
      <ErrorState
        title="Access Denied"
        message="You don't have access to this facility."
      />
    );
  if (!facility) return null;

  const court = courtEntries.find((c) => c.id === selectedCourt);
  const courtSport = sportEntries.find((s) => s.id === court?.sportId);
  const side = (
    <div className="min-w-0 space-y-5">
      <PricingSettingsCard
        settings={settings}
        onChange={(next) => setSettings(next)}
      />
      <PricingPreviewCard
        mode={settings.mode}
        settings={settings}
        sports={sportEntries}
        sportSetups={sportSetups}
        court={court}
        courtSetup={court ? courtSetups[court.id] : undefined}
      />
    </div>
  );

  return (
    <div className="space-y-5">
      {saveError && <FormMessage>{saveError}</FormMessage>}

      <ChoiceCards
        label="How do you set your prices?"
        value={settings.mode}
        onChange={setMode}
        options={[
          {
            value: "BY_SPORT",
            title: "By Sport",
            hint: "Set prices for each sport (applies to all courts)",
            icon: Layers,
          },
          {
            value: "BY_COURT",
            title: "By Court",
            hint: "Set prices for individual courts",
            icon: LayoutGrid,
          },
        ]}
      />

      {settings.mode === "BY_SPORT" ? (
        <div className={`grid items-start gap-5 ${editing ? "" : "xl:grid-cols-[minmax(0,1.6fr)_minmax(0,1fr)]"}`}>
          <SportPricingView
            sports={sportEntries}
            setups={sportSetups}
            onChange={changeSport}
            expandedId={expandedSport}
            onExpand={setExpandedSport}
            onAddSportPricing={addSportPricing}
            canAddSportPricing={facilitySports.some(
              (fs) => !priced(sportSetups[fs.id]),
            )}
            settings={settings}
            span={span}
            problems={problems}
          />
          {side}
        </div>
      ) : (
        <div className={`grid items-start gap-5 ${editing ? "" : "xl:grid-cols-[minmax(0,270px)_minmax(0,1.4fr)_minmax(0,1fr)]"}`}>
          <CourtList
            sports={sportEntries}
            courts={courtEntries}
            setups={courtSetups}
            selectedId={selectedCourt}
            onSelect={setSelectedCourt}
            filter={courtFilter}
            onFilter={setCourtFilter}
          />
          {court && courtSetups[court.id] ? (
            <CourtPricingPanel
              court={court}
              sport={courtSport}
              setup={courtSetups[court.id]!}
              onChange={(next) => changeCourt(court.id, next)}
              settings={settings}
              span={span}
              problems={problems[court.id] ?? { slots: {}, groups: {} }}
            />
          ) : (
            <p className="rounded-2xl border border-dashed border-[#E5E1EF] p-8 text-center text-sm text-[#666666]">
              Choose a court to set its price.
            </p>
          )}
          {side}
        </div>
      )}

      <div className="flex flex-wrap items-center justify-between gap-3 border-t border-[#E5E1EF] pt-5">
        {!editing && (
          <button
            type="button"
            onClick={() => void persist(false)}
            disabled={saving !== null}
            className="flex h-12 items-center gap-2 rounded-lg border border-[#E5E1EF] bg-white px-5 text-sm font-semibold hover:bg-[#FBFAFE] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#4817C2] disabled:opacity-60"
          >
            {saving === "draft" ? (
              <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" />
            ) : (
              <FileText className="h-4 w-4" aria-hidden="true" />
            )}
            Save as Draft
          </button>
        )}
        <div
          className={
            editing
              ? "ml-auto flex items-center gap-3"
              : "flex items-center gap-3"
          }
        >
          {!editing && (
            <button
              type="button"
              onClick={() => router.push("/onboarding/operating-hours")}
              disabled={saving !== null}
              className="flex h-12 items-center gap-2 rounded-lg border border-[#E5E1EF] bg-white px-6 text-sm font-semibold hover:bg-[#FBFAFE] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#4817C2] disabled:opacity-60"
            >
              <ArrowLeft className="h-4 w-4" aria-hidden="true" />
              Back
            </button>
          )}
          <button
            type="button"
            onClick={() => void persist(true)}
            disabled={saving !== null}
            className="flex h-12 min-w-[130px] items-center justify-center gap-2 rounded-lg bg-[#4817C2] px-7 text-sm font-semibold text-white transition-colors hover:bg-[#39109F] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#4817C2] focus-visible:ring-offset-2 disabled:opacity-70"
          >
            {saving === "next" ? (
              <>
                <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" />
                Saving…
              </>
            ) : (
              <>
                {editing ? "Save" : "Next"}
                {!editing && (
                  <ArrowRight className="h-4 w-4" aria-hidden="true" />
                )}
              </>
            )}
          </button>
        </div>
      </div>
    </div>
  );
}
