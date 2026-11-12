"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import dynamic from "next/dynamic";
import { ArrowLeft, ArrowRight, FileText, Loader2 } from "lucide-react";
import { toast } from "sonner";
import { Skeleton } from "@/components/ui/skeleton";
import { FormMessage } from "@/features/auth/components/form-message";
import { useCurrentUser } from "@/features/auth/hooks/use-auth";
import { CUSTOM_SPORT_ICON } from "@/features/sports-courts/components/sports-picker";
import { useOnboardingStore } from "@/features/onboarding/state/onboarding-store";
import type { Facility } from "@/features/onboarding/types";
import type { PlayingArea } from "@/features/courts-setup/types";
import { OTHER_SPORT_CODE } from "@/features/sports-setup/constants";
import type { FacilitySport, Sport } from "@/features/sports-setup/types";
import { ClosuresCard } from "@/features/operating-hours/setup/closures-card";
import {
  AdditionalSettings,
  CustomHoursTable,
  ModeCards,
  StandardPanel,
  WeeklyPreview,
} from "@/features/operating-hours/setup/hours-parts";
import {
  SportHoursCard,
  type SportHoursEntry,
} from "@/features/operating-hours/setup/sport-hours";
import {
  applyStandard,
  dailyMinutes,
  defaultPlans,
  detectMode,
  formatHours,
  hasProblems,
  plansFromSchedule,
  scheduleFromPlans,
  validatePlans,
  type BreakTime,
  type DayPlan,
  type HoursMode,
  type PlanProblems,
} from "@/features/operating-hours/setup-model";
import type {
  DayOfWeek,
  FacilityClosure,
} from "@/features/operating-hours/types";
import { getFacilityService } from "@/services/facility";
import { getOperatingHoursService } from "@/services/operating-hours";
import { getPlayingAreasService } from "@/services/playing-areas";
import { getSportsService } from "@/services/sports";

const ErrorState = dynamic(() =>
  import("@/components/shared/error-state").then((mod) => mod.ErrorState),
);

type LoadState = "loading" | "ready" | "forbidden";

const DEFAULT_BREAK: BreakTime = { start: "13:00", end: "14:00" };

interface Standard {
  days: DayOfWeek[];
  open: string;
  close: string;
  is24Hours: boolean;
}

function standardFromPlans(plans: DayPlan[]): Standard {
  const open = plans.filter((p) => p.isOpen);
  const first = open[0];
  return {
    days: open.map((p) => p.dayOfWeek),
    open: first?.open ?? "06:00",
    close: first?.close ?? "23:00",
    is24Hours: open.length > 0 && open.every((p) => p.is24Hours),
  };
}

const plansFromStandard = (s: Standard): DayPlan[] =>
  applyStandard(s.days, s.open, s.close, s.is24Hours);

/**
 * Operating Hours (setup step 3): standard hours (the same hours on the chosen days) or custom hours (each day on its own), the
 * venue's holidays and closures, and the extras — bookings outside hours, a daily break and sport-wise hours. Everything is saved
 * together on Next (or Save as Draft).
 */
export function OperatingHoursSetupForm() {
  const router = useRouter();
  const { data: user, isLoading: userLoading } = useCurrentUser();
  const completeOperatingHours = useOnboardingStore(
    (s) => s.completeOperatingHours,
  );

  const [facility, setFacility] = React.useState<Facility | null>(null);
  const [sports, setSports] = React.useState<Sport[]>([]);
  const [facilitySports, setFacilitySports] = React.useState<FacilitySport[]>(
    [],
  );
  const [areas, setAreas] = React.useState<PlayingArea[]>([]);
  const [loadState, setLoadState] = React.useState<LoadState>("loading");

  const [mode, setMode] = React.useState<HoursMode>("standard");
  const [standard, setStandard] = React.useState<Standard>(() =>
    standardFromPlans(defaultPlans()),
  );
  const [custom, setCustom] = React.useState<DayPlan[]>(defaultPlans());
  const [closures, setClosures] = React.useState<FacilityClosure[]>([]);
  const [allowOutside, setAllowOutside] = React.useState(true);
  const [breakOn, setBreakOn] = React.useState(false);
  const [brk, setBrk] = React.useState<BreakTime>(DEFAULT_BREAK);
  const [sportWise, setSportWise] = React.useState(false);
  const [sportPlans, setSportPlans] = React.useState<Record<string, DayPlan[]>>(
    {},
  );

  const [problems, setProblems] = React.useState<PlanProblems>({ byDay: {} });
  const [sportErrors, setSportErrors] = React.useState<Record<string, string>>(
    {},
  );
  const [saveError, setSaveError] = React.useState<string | null>(null);
  const [saving, setSaving] = React.useState<"draft" | "next" | null>(null);

  /** What was in the database when the page loaded, so switching sport-wise hours off can clear the courts' own hours. */
  const hadSportWise = React.useRef(false);
  const courtsWithOverride = React.useRef<Set<string>>(new Set());

  const plans = mode === "standard" ? plansFromStandard(standard) : custom;
  const activeBreak = breakOn ? brk : null;

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
        if (facSports.length === 0) {
          router.replace("/onboarding/sports");
          return;
        }
        const courts = await getPlayingAreasService().getPlayingAreas(
          loaded.id,
        );
        if (cancelled) return;
        if (courts.length === 0) {
          router.replace("/onboarding/sports");
          return;
        }

        const hours = getOperatingHoursService();
        const [schedule, savedClosures] = await Promise.all([
          hours.getFacilitySchedule(loaded.id),
          hours.getClosures(loaded.id),
        ]);
        if (cancelled) return;

        const settings = loaded.hoursSettings;
        const savedBreak =
          settings?.breakStart && settings.breakEnd
            ? { start: settings.breakStart, end: settings.breakEnd }
            : null;
        const loadedPlans = schedule
          ? plansFromSchedule(schedule.days, savedBreak)
          : defaultPlans();

        // each court's own hours (from an earlier visit), so a sport can show the hours its courts follow
        const overrides = new Map<string, DayPlan[]>();
        await Promise.all(
          courts.map(async (c) => {
            const o = await hours.getPlayingAreaSchedule(c.id);
            if (o) overrides.set(c.id, plansFromSchedule(o.days));
          }),
        );
        if (cancelled) return;

        const perSport: Record<string, DayPlan[]> = {};
        for (const fs of facSports) {
          const firstWithOverride = courts.find(
            (c) => c.facilitySportId === fs.id && overrides.has(c.id),
          );
          perSport[fs.id] = firstWithOverride
            ? overrides.get(firstWithOverride.id)!
            : loadedPlans.map((p) => ({ ...p }));
        }
        courtsWithOverride.current = new Set(overrides.keys());
        hadSportWise.current = settings?.sportWiseHours ?? false;

        setFacility(loaded);
        setSports(catalogue);
        setFacilitySports(facSports);
        setAreas(courts);
        setMode(detectMode(loadedPlans));
        setStandard(standardFromPlans(loadedPlans));
        setCustom(loadedPlans);
        setClosures(savedClosures);
        setAllowOutside(settings?.allowBookingsOutsideHours ?? true);
        setBreakOn(!!savedBreak);
        if (savedBreak) setBrk(savedBreak);
        setSportWise(settings?.sportWiseHours ?? false);
        setSportPlans(perSport);
        setLoadState("ready");
      } catch {
        if (!cancelled) {
          setSaveError(
            "We couldn't load your operating hours. Please refresh and try again.",
          );
          setLoadState("ready");
        }
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [user, userLoading, router]);

  // ── editing ───────────────────────────────────────────────────────
  function clearProblems() {
    setProblems({ byDay: {} });
    setSaveError(null);
  }

  function switchMode(next: HoursMode) {
    if (next === mode) return;
    if (next === "custom") setCustom(plansFromStandard(standard));
    else setStandard(standardFromPlans(custom));
    setMode(next);
    clearProblems();
  }

  function patchStandard(patch: Partial<Standard>) {
    setStandard((s) => ({ ...s, ...patch }));
    clearProblems();
  }

  function patchDay(day: DayOfWeek, patch: Partial<DayPlan>) {
    setCustom((list) =>
      list.map((p) =>
        p.dayOfWeek === day
          ? {
              ...p,
              ...patch,
              is24Hours: patch.isOpen === false ? false : p.is24Hours,
            }
          : p,
      ),
    );
    clearProblems();
  }

  function toggleSportWise(on: boolean) {
    setSportWise(on);
    if (on) {
      // start every sport from the venue's current hours (only the sports that have none of their own yet)
      setSportPlans((prev) =>
        Object.fromEntries(
          facilitySports.map((fs) => [
            fs.id,
            prev[fs.id] ?? plans.map((p) => ({ ...p })),
          ]),
        ),
      );
    }
    setSportErrors({});
  }

  const sportEntries: SportHoursEntry[] = facilitySports.map((fs) => {
    const sport = sports.find((s) => s.id === fs.sportId);
    const isCustom = sport?.code === OTHER_SPORT_CODE;
    return {
      id: fs.id,
      name: isCustom
        ? (fs.customSportName ?? "Sport")
        : (sport?.name ?? "Sport"),
      icon: isCustom ? CUSTOM_SPORT_ICON : (sport?.icon ?? CUSTOM_SPORT_ICON),
      courts: areas.filter((a) => a.facilitySportId === fs.id).length,
    };
  });

  // ── save ──────────────────────────────────────────────────────────
  async function persist(advance: boolean) {
    if (!facility) return;
    setSaveError(null);

    // with sport-wise hours on, the venue-wide hours and break are not used, so they are not checked
    const found = sportWise
      ? validatePlans(plans, null)
      : validatePlans(plans, activeBreak);
    setProblems(found);
    const sportProblems: Record<string, string> = {};
    if (sportWise) {
      for (const entry of sportEntries) {
        const result = validatePlans(sportPlans[entry.id] ?? [], null);
        const message = result.general ?? Object.values(result.byDay)[0];
        if (message) sportProblems[entry.id] = message;
      }
    }
    setSportErrors(sportProblems);
    if (hasProblems(found) || Object.keys(sportProblems).length > 0) {
      setSaveError("Please fix the highlighted fields to continue.");
      return;
    }

    setSaving(advance ? "next" : "draft");
    try {
      const hours = getOperatingHoursService();
      await hours.saveFacilitySchedule(
        facility.id,
        scheduleFromPlans(plans, activeBreak),
      );
      await hours.replaceClosures(facility.id, closures);
      await getFacilityService().updateFacility(facility.id, {
        hoursSettings: {
          allowBookingsOutsideHours: allowOutside,
          breakStart: activeBreak?.start,
          breakEnd: activeBreak?.end,
          sportWiseHours: sportWise,
        },
      });

      if (sportWise) {
        for (const entry of sportEntries) {
          const days = scheduleFromPlans(sportPlans[entry.id] ?? [], null);
          for (const court of areas.filter(
            (a) => a.facilitySportId === entry.id,
          )) {
            await hours.savePlayingAreaSchedule(court.id, facility.id, days);
            courtsWithOverride.current.add(court.id);
          }
        }
      } else if (hadSportWise.current) {
        // sport-wise hours were on and are now off: the courts go back to the venue's hours
        for (const courtId of courtsWithOverride.current)
          await hours.deletePlayingAreaOverride(courtId);
        courtsWithOverride.current = new Set();
      }
      hadSportWise.current = sportWise;

      if (advance) {
        await getFacilityService().updateOnboardingStep(facility.id, "PRICING");
        completeOperatingHours();
        router.push("/onboarding/pricing");
      } else {
        toast.success("Draft saved. You can pick up where you left off.");
      }
    } catch {
      setSaveError("We couldn't save your operating hours. Please try again.");
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

  const dailyTotal = formatHours(
    standard.is24Hours
      ? 1440
      : dailyMinutes(
          {
            dayOfWeek: 1,
            isOpen: true,
            open: standard.open,
            close: standard.close,
            is24Hours: false,
          },
          activeBreak,
        ),
  );

  const settingsCard = (
    <AdditionalSettings
      allowOutside={allowOutside}
      onAllowOutside={setAllowOutside}
      breakOn={breakOn}
      onBreakOn={(v) => {
        setBreakOn(v);
        clearProblems();
      }}
      brk={brk}
      onBreak={(next) => {
        setBrk(next);
        clearProblems();
      }}
      breakError={problems.breakTime}
      sportWise={sportWise}
      onSportWise={toggleSportWise}
    />
  );
  const closuresCard = (
    <ClosuresCard closures={closures} onChange={setClosures} />
  );

  return (
    <div className="space-y-5">
      {saveError && <FormMessage>{saveError}</FormMessage>}

      {!sportWise && <ModeCards mode={mode} onChange={switchMode} />}

      <div className="grid items-start gap-5 xl:grid-cols-[minmax(0,1.45fr)_minmax(0,1fr)]">
        <div className="min-w-0 space-y-5">
          {sportWise ? (
            <SportHoursCard
              sports={sportEntries}
              plans={sportPlans}
              onChange={(id, next) =>
                setSportPlans((prev) => ({ ...prev, [id]: next }))
              }
              errors={sportErrors}
            />
          ) : mode === "standard" ? (
            <>
              <StandardPanel
                openDays={standard.days}
                onDays={(days) => patchStandard({ days })}
                open={standard.open}
                close={standard.close}
                onOpen={(open) => patchStandard({ open })}
                onClose={(close) => patchStandard({ close })}
                is24Hours={standard.is24Hours}
                onIs24Hours={(is24Hours) => patchStandard({ is24Hours })}
                dailyTotal={dailyTotal}
                daysError={problems.general}
                timeError={Object.values(problems.byDay)[0]}
              />
              <WeeklyPreview plans={plans} brk={activeBreak} />
            </>
          ) : (
            <>
              {problems.general && (
                <FormMessage>{problems.general}</FormMessage>
              )}
              <CustomHoursTable
                plans={custom}
                onChange={patchDay}
                errors={problems.byDay}
                brk={activeBreak}
              />
            </>
          )}
        </div>
        <div className="min-w-0 space-y-5">
          {mode === "standard" || sportWise ? (
            <>
              {settingsCard}
              {closuresCard}
            </>
          ) : (
            <>
              {closuresCard}
              {settingsCard}
            </>
          )}
        </div>
      </div>

      <div className="flex flex-wrap items-center justify-between gap-3 border-t border-[#E5E1EF] pt-5">
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
        <div className="flex items-center gap-3">
          <button
            type="button"
            onClick={() => router.replace("/onboarding/sports")}
            disabled={saving !== null}
            className="flex h-12 items-center gap-2 rounded-lg border border-[#E5E1EF] bg-white px-6 text-sm font-semibold hover:bg-[#FBFAFE] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#4817C2] disabled:opacity-60"
          >
            <ArrowLeft className="h-4 w-4" aria-hidden="true" />
            Back
          </button>
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
                Next
                <ArrowRight className="h-4 w-4" aria-hidden="true" />
              </>
            )}
          </button>
        </div>
      </div>
    </div>
  );
}
