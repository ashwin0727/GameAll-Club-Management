"use client";

import { useEffect, useState } from "react";
import dynamic from "next/dynamic";
import { useRouter } from "next/navigation";
import { useCurrentUser } from "@/features/auth/hooks/use-auth";
import { SubmitButton } from "@/features/auth/components/submit-button";
import { FormMessage } from "@/features/auth/components/form-message";
import { Skeleton } from "@/components/ui/skeleton";

// Pulls in framer-motion but only renders on the rare forbidden-facility
// path — deferred off the common happy-path bundle for this form.
const ErrorState = dynamic(() =>
  import("@/components/shared/error-state").then((mod) => mod.ErrorState),
);
import { MockFacilityService } from "@/features/onboarding/services/mock-facility-service";
import { useOnboardingStore } from "@/features/onboarding/state/onboarding-store";
import type { Facility } from "@/features/onboarding/types";
import { FacilityContextCard } from "@/features/sports-setup/components/facility-context-card";
import { SportGrid } from "@/features/sports-setup/components/sport-grid";
import { OtherSportInput } from "@/features/sports-setup/components/other-sport-input";
import { SelectedSportsSummary } from "@/features/sports-setup/components/selected-sports-summary";
import { SaveStatus } from "@/features/onboarding/components/save-status";
import { AVAILABLE_SPORTS, OTHER_SPORT_ID, SINGLE_SPORT_TYPE_MAP } from "@/features/sports-setup/constants";
import { MockSportService } from "@/features/sports-setup/services/mock-sport-service";
import { otherSportNameSchema } from "@/features/sports-setup/validation";

type LoadState = "loading" | "ready" | "forbidden";

// Resolves once the onboarding store has hydrated from localStorage. The
// store uses skipHydration so the first client render matches the server's
// empty-state HTML; this lets the load effect below wait for the real
// persisted values before deciding whether to preselect a sport.
function waitForOnboardingHydration(): Promise<void> {
  if (useOnboardingStore.persist.hasHydrated()) return Promise.resolve();
  return new Promise((resolve) => {
    const unsubscribe = useOnboardingStore.persist.onFinishHydration(() => {
      unsubscribe();
      resolve();
    });
    useOnboardingStore.persist.rehydrate();
  });
}

export function SportsSetupForm() {
  const router = useRouter();
  const { data: user, isLoading: userLoading } = useCurrentUser();
  const setSelectedSportIdsInStore = useOnboardingStore((s) => s.setSelectedSportIds);
  const setOtherSportNameInStore = useOnboardingStore((s) => s.setOtherSportName);
  const completeSports = useOnboardingStore((s) => s.completeSports);

  const [facility, setFacility] = useState<Facility | null>(null);
  const [loadState, setLoadState] = useState<LoadState>("loading");
  const [selectedSportIds, setSelectedSportIds] = useState<string[]>([]);
  const [otherSportName, setOtherSportName] = useState("");
  const [otherNameError, setOtherNameError] = useState<string | null>(null);
  const [selectionError, setSelectionError] = useState<string | null>(null);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [isSaving, setIsSaving] = useState(false);

  // Facility/sport loading: client-side only, since MockFacilityService and
  // MockSportService are localStorage-backed and cannot run on the server.
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
      // Guaranteed true by construction (the service already filters by
      // ownerId) — kept as an explicit check per spec rather than trusted
      // silently.
      if (loadedFacility.ownerId !== user.id) {
        setLoadState("forbidden");
        return;
      }

      const existing = await MockSportService.getFacilitySports(loadedFacility.id);
      if (cancelled) return;

      let initialIds = existing.map((row) => row.sportId);
      let initialOtherName = existing.find((row) => row.sportId === OTHER_SPORT_ID)?.customSportName ?? "";

      // Preselection only applies on a genuinely first-ever visit — never
      // overrides an existing saved selection. But an in-progress selection
      // that was never confirmed via Continue (only auto-saved into the
      // store's draft) still takes priority over facility-type preselection —
      // otherwise reloading the page silently discards the owner's picks.
      if (existing.length === 0) {
        await waitForOnboardingHydration();
        if (cancelled) return;
        const persisted = useOnboardingStore.getState();
        if (persisted.selectedSportIds.length > 0) {
          initialIds = persisted.selectedSportIds;
          initialOtherName = persisted.otherSportName;
        } else {
          const preselected = SINGLE_SPORT_TYPE_MAP[loadedFacility.type];
          if (preselected) initialIds = [preselected];
        }
      }

      setFacility(loadedFacility);
      setSelectedSportIds(initialIds);
      setOtherSportName(initialOtherName);
      setSelectedSportIdsInStore(initialIds);
      setOtherSportNameInStore(initialOtherName);
      setLoadState("ready");
    })();

    return () => {
      cancelled = true;
    };
  }, [user, userLoading, router, setSelectedSportIdsInStore, setOtherSportNameInStore]);

  // Debounced auto-save of the draft selection — same ~400ms pattern as
  // FacilityDetailsForm, per spec: don't persist on every click immediately.
  useEffect(() => {
    if (loadState !== "ready") return;
    const timeout = setTimeout(() => {
      setSelectedSportIdsInStore(selectedSportIds);
      setOtherSportNameInStore(otherSportName);
    }, 400);
    return () => clearTimeout(timeout);
  }, [selectedSportIds, otherSportName, loadState, setSelectedSportIdsInStore, setOtherSportNameInStore]);

  function toggleSport(sportId: string) {
    setSelectionError(null);
    setSelectedSportIds((prev) => (prev.includes(sportId) ? prev.filter((id) => id !== sportId) : [...prev, sportId]));
  }

  async function handleContinue() {
    if (selectedSportIds.length === 0) {
      setSelectionError("Select at least one sport to continue.");
      return;
    }

    if (selectedSportIds.includes(OTHER_SPORT_ID)) {
      const result = otherSportNameSchema.safeParse(otherSportName);
      if (!result.success) {
        setOtherNameError(result.error.issues[0]?.message ?? "Enter the sport name.");
        return;
      }
    }
    setOtherNameError(null);
    setSelectionError(null);

    if (!facility) return;
    setIsSaving(true);
    setSaveError(null);

    try {
      await MockSportService.saveFacilitySports(
        facility.id,
        selectedSportIds.map((sportId) => ({
          facilityId: facility.id,
          sportId,
          enabled: true,
          customSportName: sportId === OTHER_SPORT_ID ? otherSportName.trim() : undefined,
        })),
      );

      completeSports();
      setIsSaving(false);
      router.push("/onboarding/courts");
    } catch {
      setSaveError("Unable to save your sports. Please try again.");
      setIsSaving(false);
    }
  }

  if (userLoading || loadState === "loading") {
    return (
      <div className="space-y-6">
        <Skeleton className="h-24 w-full rounded-xl" />
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {Array.from({ length: 6 }).map((_, index) => (
            <Skeleton key={index} className="h-28 w-full rounded-xl" />
          ))}
        </div>
      </div>
    );
  }

  if (loadState === "forbidden") {
    return <ErrorState title="Access denied" message="You don't have access to this facility." />;
  }

  if (!facility) return null;

  return (
    <div className="space-y-8">
      <FacilityContextCard facility={facility} />

      {saveError && <FormMessage>{saveError}</FormMessage>}

      <SportGrid sports={AVAILABLE_SPORTS} selectedSportIds={selectedSportIds} onToggle={toggleSport} />

      {selectedSportIds.includes(OTHER_SPORT_ID) && (
        <OtherSportInput
          value={otherSportName}
          onChange={(value) => {
            setOtherSportName(value);
            setOtherNameError(null);
          }}
          error={otherNameError}
        />
      )}

      {selectionError && <FormMessage>{selectionError}</FormMessage>}

      <div className="flex items-center justify-between gap-4">
        <div className="space-y-1">
          <SelectedSportsSummary count={selectedSportIds.length} />
          <SaveStatus dirtyToken={JSON.stringify({ selectedSportIds, otherSportName })} />
        </div>
        <SubmitButton
          type="button"
          onClick={handleContinue}
          pending={isSaving}
          disabled={selectedSportIds.length === 0}
          pendingLabel="Saving…"
          className="w-auto sm:min-w-[10rem]"
        >
          Continue →
        </SubmitButton>
      </div>
    </div>
  );
}