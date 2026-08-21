"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import dynamic from "next/dynamic";
import { useCurrentUser } from "@/features/auth/hooks/use-auth";
import { SubmitButton } from "@/features/auth/components/submit-button";
import { FormMessage } from "@/features/auth/components/form-message";
import { Skeleton } from "@/components/ui/skeleton";
import { MockFacilityService } from "@/features/onboarding/services/mock-facility-service";
import { useOnboardingStore } from "@/features/onboarding/state/onboarding-store";
import type { Facility } from "@/features/onboarding/types";
import { FacilityContextCard } from "@/features/sports-setup/components/facility-context-card";
import { PlayingAreaSummary } from "@/features/courts-setup/components/playing-area-summary";
import { SportSection } from "@/features/courts-setup/components/sport-section";
import { RemovePlayingAreaDialog } from "@/features/courts-setup/components/remove-playing-area-dialog";
import { SaveStatus } from "@/features/onboarding/components/save-status";
import { AVAILABLE_SPORTS, OTHER_SPORT_ID } from "@/features/sports-setup/constants";
import { MockSportService } from "@/features/sports-setup/services/mock-sport-service";
import type { FacilitySport } from "@/features/sports-setup/types";
import {
  DEFAULT_BOOKING_ENABLED,
  DEFAULT_PLAYING_AREA_STATUS,
  DEFAULT_PLAYING_AREA_TYPE,
  playingAreaLabelFor,
} from "@/features/courts-setup/constants";
import { MockPlayingAreaService } from "@/features/courts-setup/services/mock-playing-area-service";
import type { PlayingArea, PlayingAreaInput } from "@/features/courts-setup/types";

const ErrorState = dynamic(() =>
  import("@/components/shared/error-state").then((mod) => mod.ErrorState),
);

type LoadState = "loading" | "ready" | "forbidden";

const DEBOUNCE_MS = 400;

export function CourtsSetupForm() {
  const router = useRouter();
  const { data: user, isLoading: userLoading } = useCurrentUser();
  const completeCourts = useOnboardingStore((s) => s.completeCourts);

  const [facility, setFacility] = useState<Facility | null>(null);
  const [facilitySports, setFacilitySports] = useState<FacilitySport[]>([]);
  const [playingAreas, setPlayingAreas] = useState<PlayingArea[]>([]);
  const [loadState, setLoadState] = useState<LoadState>("loading");
  const [nameErrors, setNameErrors] = useState<Record<string, string>>({});
  const [sectionErrors, setSectionErrors] = useState<Record<string, string>>({});
  const [saveError, setSaveError] = useState<string | null>(null);
  const [isSaving, setIsSaving] = useState(false);
  const [removeTarget, setRemoveTarget] = useState<{ id: string; label: string } | null>(null);

  // Tracks which local playing-area ids have never made it to the service
  // yet (still a local-only draft, per spec §14). Once the debounce for an
  // id fires and createPlayingArea resolves, that id is removed here and
  // the local record's id is swapped for the service-assigned one.
  const unsavedIds = useRef<Set<string>>(new Set());
  const playingAreasRef = useRef<PlayingArea[]>([]);
  const timeouts = useRef<Record<string, ReturnType<typeof setTimeout>>>({});
  playingAreasRef.current = playingAreas;

  useEffect(() => {
    if (userLoading) return;
    if (!user) {
      router.replace("/login");
      return;
    }

    let cancelled = false;

    (async () => {
      const loadedFacility = await MockFacilityService.getFacility(user.id);
      if (cancelled) return;
      if (!loadedFacility) {
        router.replace("/onboarding/facility");
        return;
      }
      if (loadedFacility.ownerId !== user.id) {
        setLoadState("forbidden");
        return;
      }

      const sports = await MockSportService.getFacilitySports(loadedFacility.id);
      if (cancelled) return;
      if (sports.length === 0) {
        router.replace("/onboarding/sports");
        return;
      }

      const areas = await MockPlayingAreaService.getPlayingAreas(loadedFacility.id);
      if (cancelled) return;

      setFacility(loadedFacility);
      setFacilitySports(sports);
      setPlayingAreas(areas);
      setLoadState("ready");
    })();

    return () => {
      cancelled = true;
    };
  }, [user, userLoading, router]);

  const persistArea = useCallback(async (id: string) => {
    const area = playingAreasRef.current.find((a) => a.id === id);
    if (!area) return;

    if (unsavedIds.current.has(id)) {
      const input: PlayingAreaInput = {
        facilityId: area.facilityId,
        facilitySportId: area.facilitySportId,
        sportId: area.sportId,
        name: area.name,
        type: area.type,
        status: area.status,
        bookingEnabled: area.bookingEnabled,
        archived: area.archived,
        displayOrder: area.displayOrder,
      };
      const created = await MockPlayingAreaService.createPlayingArea(input);
      unsavedIds.current.delete(id);
      setPlayingAreas((prev) => prev.map((a) => (a.id === id ? created : a)));
    } else {
      await MockPlayingAreaService.updatePlayingArea(id, {
        name: area.name,
        type: area.type,
        status: area.status,
        bookingEnabled: area.bookingEnabled,
      });
    }
  }, []);

  function scheduleSave(id: string) {
    clearTimeout(timeouts.current[id]);
    timeouts.current[id] = setTimeout(() => {
      persistArea(id);
    }, DEBOUNCE_MS);
  }

  useEffect(() => {
    const pending = timeouts.current;
    return () => {
      Object.values(pending).forEach(clearTimeout);
    };
  }, []);

  function updateArea(id: string, patch: Partial<PlayingArea>) {
    setPlayingAreas((prev) => prev.map((a) => (a.id === id ? { ...a, ...patch } : a)));
    setNameErrors((prev) => {
      if (!("name" in patch)) return prev;
      const next = { ...prev };
      delete next[id];
      return next;
    });
    scheduleSave(id);
  }

  function handleAdd(facilitySport: FacilitySport) {
    if (!facility) return;
    const sport = AVAILABLE_SPORTS.find((s) => s.id === facilitySport.sportId);
    const label = playingAreaLabelFor(sport?.code ?? "OTHER");
    const existingForSport = playingAreas.filter((a) => a.facilitySportId === facilitySport.id);
    const nextNumber = existingForSport.length + 1;

    const id = crypto.randomUUID();
    const now = new Date().toISOString();
    const newArea: PlayingArea = {
      id,
      facilityId: facility.id,
      facilitySportId: facilitySport.id,
      sportId: facilitySport.sportId,
      name: `${label} ${nextNumber}`,
      type: DEFAULT_PLAYING_AREA_TYPE,
      status: DEFAULT_PLAYING_AREA_STATUS,
      bookingEnabled: DEFAULT_BOOKING_ENABLED,
      archived: false,
      displayOrder: existingForSport.length,
      createdAt: now,
      updatedAt: now,
    };

    unsavedIds.current.add(id);
    setPlayingAreas((prev) => [...prev, newArea]);
    setSectionErrors((prev) => {
      const next = { ...prev };
      delete next[facilitySport.id];
      return next;
    });
    scheduleSave(id);
  }

  function requestRemove(id: string, label: string) {
    if (unsavedIds.current.has(id)) {
      clearTimeout(timeouts.current[id]);
      unsavedIds.current.delete(id);
      setPlayingAreas((prev) => prev.filter((a) => a.id !== id));
      return;
    }
    setRemoveTarget({ id, label });
  }

  async function confirmRemove() {
    if (!removeTarget) return;
    const { id } = removeTarget;
    await MockPlayingAreaService.removePlayingArea(id);
    setPlayingAreas((prev) => prev.filter((a) => a.id !== id));
    setRemoveTarget(null);
  }

  async function handleContinue() {
    const errors: Record<string, string> = {};
    const seenNames: Record<string, Set<string>> = {};

    for (const area of playingAreas) {
      const trimmed = area.name.trim();
      if (trimmed.length < 2 || trimmed.length > 50) {
        errors[area.id] = "Name must be between 2 and 50 characters.";
        continue;
      }
      const key = area.facilitySportId;
      seenNames[key] ??= new Set();
      const normalized = trimmed.toLowerCase();
      if (seenNames[key].has(normalized)) {
        errors[area.id] = "This name is already used for this sport.";
        continue;
      }
      seenNames[key].add(normalized);
    }

    const sectionErrs: Record<string, string> = {};
    for (const facilitySport of facilitySports) {
      const count = playingAreas.filter((a) => a.facilitySportId === facilitySport.id).length;
      if (count === 0) {
        const sport = AVAILABLE_SPORTS.find((s) => s.id === facilitySport.sportId);
        const label = playingAreaLabelFor(sport?.code ?? "OTHER");
        const sportName =
          facilitySport.sportId === OTHER_SPORT_ID
            ? facilitySport.customSportName || "this sport"
            : sport?.name ?? "this sport";
        sectionErrs[facilitySport.id] = `Add at least one ${label.toLowerCase()} for ${sportName}.`;
      }
    }

    setNameErrors(errors);
    setSectionErrors(sectionErrs);

    if (Object.keys(errors).length > 0 || Object.keys(sectionErrs).length > 0) {
      return;
    }

    if (!facility) return;
    setIsSaving(true);
    setSaveError(null);

    try {
      // Flush any pending debounced saves before navigating away.
      await Promise.all(playingAreas.map((area) => persistArea(area.id)));
      completeCourts();
      router.push("/onboarding/operating-hours");
    } catch {
      setSaveError("Unable to save your courts. Please try again.");
      setIsSaving(false);
    }
  }

  if (userLoading || loadState === "loading") {
    return (
      <div className="space-y-6">
        <Skeleton className="h-24 w-full rounded-xl" />
        {Array.from({ length: 2 }).map((_, i) => (
          <Skeleton key={i} className="h-40 w-full rounded-xl" />
        ))}
      </div>
    );
  }

  if (loadState === "forbidden") {
    return <ErrorState title="Access denied" message="You don't have access to this facility." />;
  }

  if (!facility) return null;

  const totalPlayingAreas = playingAreas.length;

  return (
    <div className="space-y-8">
      <FacilityContextCard facility={facility} />

      <PlayingAreaSummary sportCount={facilitySports.length} playingAreaCount={totalPlayingAreas} />

      {saveError && <FormMessage>{saveError}</FormMessage>}

      {facilitySports.map((facilitySport) => {
        const sport = AVAILABLE_SPORTS.find((s) => s.id === facilitySport.sportId);
        if (!sport) return null;
        const displayName =
          facilitySport.sportId === OTHER_SPORT_ID && facilitySport.customSportName
            ? facilitySport.customSportName
            : sport.name;
        const areasForSport = playingAreas
          .filter((a) => a.facilitySportId === facilitySport.id)
          .sort((a, b) => a.displayOrder - b.displayOrder);

        return (
          <SportSection
            key={facilitySport.id}
            sport={sport}
            sportDisplayName={displayName}
            playingAreas={areasForSport}
            nameErrors={nameErrors}
            sectionError={sectionErrors[facilitySport.id]}
            onAdd={() => handleAdd(facilitySport)}
            onNameChange={(id, value) => updateArea(id, { name: value })}
            onTypeChange={(id, value) => updateArea(id, { type: value })}
            onStatusChange={(id, value) => updateArea(id, { status: value })}
            onBookingEnabledChange={(id, value) => updateArea(id, { bookingEnabled: value })}
            onRemoveRequest={(id) => {
              const label = playingAreaLabelFor(sport.code);
              requestRemove(id, label);
            }}
          />
        );
      })}

      <div className="flex items-center justify-between gap-4">
        <SaveStatus dirtyToken={JSON.stringify(playingAreas)} />
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

      {removeTarget && (
        <RemovePlayingAreaDialog
          open={Boolean(removeTarget)}
          onOpenChange={(open) => {
            if (!open) setRemoveTarget(null);
          }}
          label={removeTarget.label}
          onConfirm={confirmRemove}
        />
      )}
    </div>
  );
}