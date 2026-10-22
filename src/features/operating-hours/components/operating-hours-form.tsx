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
import { useOnboardingStore } from "@/features/onboarding/state/onboarding-store";
import type { Facility } from "@/features/onboarding/types";
import { FacilityContextCard } from "@/features/sports-setup/components/facility-context-card";
import { PlayingAreaSummary } from "@/features/courts-setup/components/playing-area-summary";
import { SaveStatus } from "@/features/onboarding/components/save-status";
import type { FacilitySport, Sport } from "@/features/sports-setup/types";
import type { PlayingArea } from "@/features/courts-setup/types";
import { DISPLAY_ORDER, buildDefaultWeek } from "@/features/operating-hours/constants";
import { DAYS_OF_WEEK, type DayOfWeek, type OperatingDay } from "@/features/operating-hours/types";
import { validateSchedule } from "@/features/operating-hours/validation";
import { DayScheduleCard } from "@/features/operating-hours/components/day-schedule-card";
import { CopyHoursDialog } from "@/features/operating-hours/components/copy-hours-dialog";
import { QuickSetup } from "@/features/operating-hours/components/quick-setup";
import { ScheduleSummary } from "@/features/operating-hours/components/schedule-summary";
import {
  PlayingAreaOverrides,
  type OverrideEntry,
} from "@/features/operating-hours/components/playing-area-overrides";

const ErrorState = dynamic(() =>
  import("@/components/shared/error-state").then((mod) => mod.ErrorState),
);

type LoadState = "loading" | "ready" | "forbidden";

/**
 * `onDone` turns the form into an in-place editor: saving calls it instead of advancing the onboarding step, so the
 * same operating hours form can be used from a popup once the facility is already set up.
 */
export function OperatingHoursForm({ onDone }: { onDone?: () => void } = {}) {
  const router = useRouter();
  const { data: user, isLoading: userLoading } = useCurrentUser();
  const completeOperatingHours = useOnboardingStore((s) => s.completeOperatingHours);

  const [facility, setFacility] = useState<Facility | null>(null);
  const [facilitySports, setFacilitySports] = useState<FacilitySport[]>([]);
  const [sports, setSports] = useState<Sport[]>([]);
  const [playingAreas, setPlayingAreas] = useState<PlayingArea[]>([]);
  const [loadState, setLoadState] = useState<LoadState>("loading");

  const [days, setDays] = useState<OperatingDay[]>(buildDefaultWeek());
  const [dayErrors, setDayErrors] = useState<Partial<Record<DayOfWeek, string>>>({});
  // Off by default: the facility hours editor stays folded away and each court's hours can be customized below.
  const [applyToAll, setApplyToAll] = useState(false);
  const [overrides, setOverrides] = useState<Record<string, OverrideEntry>>({});
  const [copyDialogDay, setCopyDialogDay] = useState<DayOfWeek | null>(null);

  const [saveError, setSaveError] = useState<string | null>(null);
  const [isSaving, setIsSaving] = useState(false);
  const [dirtyToken, setDirtyToken] = useState(0);

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

      const existingSchedule = await getOperatingHoursService().getFacilitySchedule(loadedFacility.id);
      if (cancelled) return;

      const scheduleDays = existingSchedule
        ? DAYS_OF_WEEK.map(
            (d) => existingSchedule.days.find((day) => day.dayOfWeek === d) ?? buildDefaultWeek()[d]!,
          )
        : buildDefaultWeek();

      const overrideEntries = await Promise.all(
        areas.map(async (area) => {
          const schedule = await getOperatingHoursService().getPlayingAreaSchedule(area.id);
          return [area.id, schedule] as const;
        }),
      );
      if (cancelled) return;

      const nextOverrides: Record<string, OverrideEntry> = {};
      for (const [areaId, schedule] of overrideEntries) {
        if (schedule) {
          nextOverrides[areaId] = {
            active: true,
            days: DAYS_OF_WEEK.map(
              (d) => schedule.days.find((day) => day.dayOfWeek === d) ?? buildDefaultWeek()[d]!,
            ),
            errors: {},
          };
        }
      }

      setFacility(loadedFacility);
      setFacilitySports(facSports);
      setSports(availableSports);
      setPlayingAreas(areas);
      setDays(scheduleDays);
      setOverrides(nextOverrides);
      setLoadState("ready");
    })();

    return () => {
      cancelled = true;
    };
  }, [user, userLoading, router]);

  function updateDay(next: OperatingDay) {
    setDays((prev) => prev.map((d) => (d.dayOfWeek === next.dayOfWeek ? next : d)));
    setDayErrors((prev) => {
      if (!(next.dayOfWeek in prev)) return prev;
      const copy = { ...prev };
      delete copy[next.dayOfWeek];
      return copy;
    });
    setDirtyToken((t) => t + 1);
  }

  function applyPreset(preset: OperatingDay[]) {
    setDays(preset);
    setDayErrors({});
    setDirtyToken((t) => t + 1);
  }

  function handleCopy(toDays: DayOfWeek[]) {
    if (copyDialogDay === null) return;
    const source = days.find((d) => d.dayOfWeek === copyDialogDay);
    if (!source) return;
    setDays((prev) =>
      prev.map((d) =>
        toDays.includes(d.dayOfWeek)
          ? { ...source, dayOfWeek: d.dayOfWeek, slots: source.slots.map((s) => ({ ...s })) }
          : d,
      ),
    );
    setDirtyToken((t) => t + 1);
  }

  function handleCustomize(playingAreaId: string) {
    setOverrides((prev) => ({
      ...prev,
      [playingAreaId]: prev[playingAreaId]?.active
        ? prev[playingAreaId]
        : { active: true, days: days.map((d) => ({ ...d, slots: d.slots.map((s) => ({ ...s })) })), errors: {} },
    }));
  }

  async function handleUseFacilityHours(playingAreaId: string) {
    setOverrides((prev) => {
      const copy = { ...prev };
      delete copy[playingAreaId];
      return copy;
    });
    try {
      await getOperatingHoursService().deletePlayingAreaOverride(playingAreaId);
    } catch {
      setSaveError("Unable to update this playing area. Please try again.");
    }
  }

  function handleOverrideDayChange(playingAreaId: string, day: OperatingDay) {
    setOverrides((prev) => {
      const entry = prev[playingAreaId];
      if (!entry) return prev;
      const nextDays = entry.days.map((d) => (d.dayOfWeek === day.dayOfWeek ? day : d));
      const nextErrors = { ...entry.errors };
      delete nextErrors[day.dayOfWeek];
      return { ...prev, [playingAreaId]: { ...entry, days: nextDays, errors: nextErrors } };
    });
  }

  async function handleContinue() {
    if (!facility) return;

    const facilityResult = validateSchedule(days);
    let overridesValid = true;
    const nextOverrides = { ...overrides };
    for (const [areaId, entry] of Object.entries(overrides)) {
      if (!entry.active || applyToAll) continue;
      const result = validateSchedule(entry.days);
      nextOverrides[areaId] = { ...entry, errors: result.dayErrors };
      if (!result.isValid) overridesValid = false;
    }

    setDayErrors(facilityResult.dayErrors);
    setOverrides(nextOverrides);

    if (!facilityResult.isValid || !overridesValid) return;

    setIsSaving(true);
    setSaveError(null);

    try {
      await getOperatingHoursService().saveFacilitySchedule(facility.id, days);

      for (const [areaId, entry] of Object.entries(overrides)) {
        if (!entry.active) continue;
        if (applyToAll) {
          // "Use the same hours for all courts" — a court's own hours no longer apply.
          await getOperatingHoursService().deletePlayingAreaOverride(areaId);
        } else {
          await getOperatingHoursService().savePlayingAreaSchedule(areaId, facility.id, entry.days);
        }
      }

      if (onDone) {
        setIsSaving(false);
        onDone();
        return;
      }
      await getFacilityService().updateOnboardingStep(facility.id, "PRICING");
      completeOperatingHours();
      setIsSaving(false);
      router.push("/onboarding/pricing");
    } catch {
      setSaveError("Unable to save operating hours. Please try again.");
      setIsSaving(false);
    }
  }

  if (userLoading || loadState === "loading") {
    return (
      <div className="space-y-6">
        <p className="text-sm text-muted-foreground">Loading operating hours…</p>
        <Skeleton className="h-24 w-full rounded-xl" />
        {Array.from({ length: 3 }).map((_, i) => (
          <Skeleton key={i} className="h-32 w-full rounded-xl" />
        ))}
      </div>
    );
  }

  if (loadState === "forbidden") {
    return <ErrorState title="Access Denied" message="You don't have access to this facility." />;
  }

  if (!facility) return null;

  const customizedCount = applyToAll ? 0 : Object.values(overrides).filter((o) => o.active).length;
  const orderedDays = DISPLAY_ORDER.map((d) => days.find((day) => day.dayOfWeek === d)).filter(
    (d): d is OperatingDay => Boolean(d),
  );

  return (
    <div className="space-y-8">
      <FacilityContextCard facility={facility} />
      <PlayingAreaSummary sportCount={facilitySports.length} playingAreaCount={playingAreas.length} />

      {saveError && <FormMessage>{saveError}</FormMessage>}

      {/* Left: the hours editor. Right: the final Operating Hours, which stays in view while the page scrolls. */}
      <div className="grid items-start gap-6 lg:grid-cols-[minmax(0,1fr)_320px]">
        <div className="min-w-0 space-y-8">
        <div className="space-y-4 rounded-xl border border-border bg-card p-5 sm:p-6">
          <div>
            <h2 className="text-sm font-semibold">Facility Operating Hours</h2>
            <p className="text-xs text-muted-foreground">
              These hours will apply to all courts and turfs by default.
            </p>
          </div>

          <button
            type="button"
            role="checkbox"
            aria-checked={applyToAll}
            onClick={() => setApplyToAll((v) => !v)}
            className="flex h-11 items-center gap-2 text-sm"
          >
            <span
              className={`flex h-5 w-5 items-center justify-center rounded border ${
                applyToAll ? "border-primary bg-primary text-primary-foreground" : "border-input"
              }`}
            >
              {applyToAll ? "✓" : ""}
            </span>
            Use the same hours for all courts and turfs
          </button>

          {applyToAll && (
            <>
              <QuickSetup onApply={applyPreset} />

              <div className="space-y-3">
                {orderedDays.map((day) => (
                  <DayScheduleCard
                    key={day.dayOfWeek}
                    day={day}
                    error={dayErrors[day.dayOfWeek]}
                    onChange={updateDay}
                    onCopyRequest={() => setCopyDialogDay(day.dayOfWeek)}
                  />
                ))}
              </div>
            </>
          )}
        </div>

        {/* Individual customization only when "same hours for all" is off. */}
        {!applyToAll && (
          <div className="rounded-xl border border-border bg-card p-5 sm:p-6">
            <PlayingAreaOverrides
              facilitySports={facilitySports}
              playingAreas={playingAreas}
              sports={sports}
              overrides={overrides}
              onCustomize={handleCustomize}
              onUseFacilityHours={handleUseFacilityHours}
              onDayChange={handleOverrideDayChange}
            />
          </div>
        )}

        </div>

        <aside className="lg:sticky lg:top-6" aria-label="Operating Hours Summary">
          <ScheduleSummary days={days} playingAreaCount={playingAreas.length} customizedCount={customizedCount} />
        </aside>
      </div>

      {/* The Saved status and Continue stay pinned to the bottom of the page. */}
      <div className="sticky bottom-0 z-20 -mx-1 border-t border-border bg-background/95 px-1 pb-3 pt-3 backdrop-blur">
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
      </div>

      {copyDialogDay !== null && (
        <CopyHoursDialog
          open={copyDialogDay !== null}
          onOpenChange={(open) => {
            if (!open) setCopyDialogDay(null);
          }}
          fromDay={copyDialogDay}
          onCopy={handleCopy}
        />
      )}
    </div>
  );
}