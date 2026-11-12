"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import dynamic from "next/dynamic";
import { ArrowLeft, ArrowRight, FileText, Loader2 } from "lucide-react";
import { toast } from "sonner";
import { Skeleton } from "@/components/ui/skeleton";
import { FormMessage } from "@/features/auth/components/form-message";
import { useCurrentUser } from "@/features/auth/hooks/use-auth";
import { DEFAULT_BOOKING_ENABLED, DEFAULT_PLAYING_AREA_STATUS } from "@/features/courts-setup/constants";
import {
  applyToSport,
  draftFromPlayingArea,
  newCourtDraft,
  validateCourtDrafts,
  type CourtDraft,
  type CourtProblems,
  type CourtSettings,
} from "@/features/courts-setup/court-draft";
import type { PlayingArea } from "@/features/courts-setup/types";
import { useOnboardingStore } from "@/features/onboarding/state/onboarding-store";
import type { Facility } from "@/features/onboarding/types";
import { OTHER_SPORT_CODE, SINGLE_SPORT_TYPE_CODE_MAP } from "@/features/sports-setup/constants";
import type { FacilitySport, Sport } from "@/features/sports-setup/types";
import { otherSportNameSchema } from "@/features/sports-setup/validation";
import { CourtsConfig, type ConfigMode, type SelectedSport } from "@/features/sports-courts/components/courts-config";
import { CourtsPreview } from "@/features/sports-courts/components/courts-preview";
import { CUSTOM_SPORT_ICON, SportsPicker, orderSports } from "@/features/sports-courts/components/sports-picker";
import { getFacilityService } from "@/services/facility";
import { getPlayingAreasService } from "@/services/playing-areas";
import { ServiceError } from "@/services/shared/service-error";
import { getSportsService } from "@/services/sports";

const ErrorState = dynamic(() => import("@/components/shared/error-state").then((mod) => mod.ErrorState));

type LoadState = "loading" | "ready" | "forbidden";

const NO_PROBLEMS: CourtProblems = { byCourt: {}, bySport: {}, ok: true };

/** The id a sport the owner added themselves goes by while editing (it has no catalogue id of its own). */
const CUSTOM_PREFIX = "custom:";
const customKey = (name: string) => `${CUSTOM_PREFIX}${name.trim().toLowerCase()}`;

/**
 * Sports & Courts (setup step 2): pick the sports on offer, then describe each court — name, indoor/outdoor, surface, lighting and
 * amenities — one by one or in bulk per sport. Everything is saved together on Next (or Save as Draft).
 */
export function SportsCourtsForm() {
  const router = useRouter();
  const { data: user, isLoading: userLoading } = useCurrentUser();
  const completeSports = useOnboardingStore((s) => s.completeSports);
  const completeCourts = useOnboardingStore((s) => s.completeCourts);

  const [facility, setFacility] = React.useState<Facility | null>(null);
  const [sports, setSports] = React.useState<Sport[]>([]);
  const [loadState, setLoadState] = React.useState<LoadState>("loading");

  const [selectedIds, setSelectedIds] = React.useState<string[]>([]);
  /** The sports the owner added themselves (any number). */
  const [customNames, setCustomNames] = React.useState<string[]>([]);
  const [drafts, setDrafts] = React.useState<CourtDraft[]>([]);
  const [activeSportId, setActiveSportId] = React.useState<string | undefined>();
  const [mode, setMode] = React.useState<ConfigMode>("court");

  const [sportsError, setSportsError] = React.useState<string | null>(null);
  const [problems, setProblems] = React.useState<CourtProblems>(NO_PROBLEMS);
  const [saveError, setSaveError] = React.useState<string | null>(null);
  const [saving, setSaving] = React.useState<"draft" | "next" | null>(null);

  /** Courts that were already in the database when the page loaded (so a removal can archive them on save). */
  const loadedCourtIds = React.useRef<Set<string>>(new Set());

  const otherSport = sports.find((s) => s.code === OTHER_SPORT_CODE);
  const otherId = otherSport?.id;

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

        const [catalogue, existingSports] = await Promise.all([getSportsService().getActiveSports(), getSportsService().getFacilitySports(loaded.id)]);
        if (cancelled) return;
        const existingAreas = await getPlayingAreasService().getPlayingAreas(loaded.id);
        if (cancelled) return;

        const otherIdLocal = catalogue.find((s) => s.code === OTHER_SPORT_CODE)?.id;
        const codeOf = (sportId: string) => catalogue.find((s) => s.id === sportId)?.code ?? OTHER_SPORT_CODE;
        // every saved sport gets an editing key: its catalogue id, or custom:<name> for one the owner added
        const keyOf = (r: FacilitySport) => (r.sportId === otherIdLocal ? customKey(r.customSportName ?? "") : r.sportId);
        const keyByFacilitySport = new Map(existingSports.map((r: FacilitySport) => [r.id, keyOf(r)]));

        let ids = existingSports.filter((r: FacilitySport) => r.sportId !== otherIdLocal).map((r: FacilitySport) => r.sportId);
        const customs = existingSports
          .filter((r: FacilitySport) => r.sportId === otherIdLocal && r.customSportName?.trim())
          .map((r: FacilitySport) => (r.customSportName ?? "").trim());
        if (ids.length === 0 && customs.length === 0) {
          const preselected = catalogue.find((s) => s.code === SINGLE_SPORT_TYPE_CODE_MAP[loaded.type])?.id;
          if (preselected) ids = [preselected];
        }

        const initial: CourtDraft[] = [];
        for (const a of existingAreas as PlayingArea[]) {
          const key = keyByFacilitySport.get(a.facilitySportId);
          if (key) initial.push({ ...draftFromPlayingArea(a, codeOf(a.sportId)), sportId: key });
        }
        loadedCourtIds.current = new Set(existingAreas.map((a: PlayingArea) => a.id));

        setFacility(loaded);
        setSports(catalogue);
        setSelectedIds(ids);
        setCustomNames(customs);
        setDrafts(initial);
        setLoadState("ready");
      } catch {
        if (!cancelled) setSaveError("We couldn't load your sports and courts. Please refresh and try again.");
        if (!cancelled) setLoadState("ready");
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [user, userLoading, router]);

  // ── the selected sports, in display order ─────────────────────────
  const selectedSports: SelectedSport[] = React.useMemo(() => {
    const list: SelectedSport[] = orderSports(sports)
      .filter((s) => selectedIds.includes(s.id))
      .map((s) => ({ id: s.id, name: s.name, code: s.code, icon: s.icon }));
    for (const name of customNames) list.push({ id: customKey(name), name, code: OTHER_SPORT_CODE, icon: CUSTOM_SPORT_ICON });
    return list;
  }, [sports, selectedIds, customNames]);

  // a selected sport always starts with one court, so there is something to configure
  React.useEffect(() => {
    if (loadState !== "ready") return;
    const missing = selectedSports.filter((s) => !drafts.some((d) => d.sportId === s.id));
    if (missing.length === 0) return;
    setDrafts((prev) => {
      let next = prev;
      for (const s of missing) {
        if (next.some((d) => d.sportId === s.id)) continue;
        next = [...next, newCourtDraft({ id: crypto.randomUUID(), sportId: s.id, sportCode: s.code, sportName: s.name, existing: next })];
      }
      return next;
    });
  }, [selectedSports, drafts, loadState]);

  // keep a valid sport on screen in the configure card
  React.useEffect(() => {
    if (selectedSports.length === 0) {
      if (activeSportId !== undefined) setActiveSportId(undefined);
    } else if (!selectedSports.some((s) => s.id === activeSportId)) {
      setActiveSportId(selectedSports[0]?.id);
    }
  }, [selectedSports, activeSportId]);

  // ── editing ───────────────────────────────────────────────────────
  function toggleSport(sportId: string) {
    setSportsError(null);
    setSelectedIds((prev) => (prev.includes(sportId) ? prev.filter((id) => id !== sportId) : [...prev, sportId]));
    setActiveSportId(sportId);
  }

  /** Adds a sport the owner types in; returns a message when it can't be added, else null. */
  function addCustom(raw: string): string | null {
    const name = raw.trim().replace(/\s+/g, " ");
    const parsed = otherSportNameSchema.safeParse(name);
    if (!parsed.success) return parsed.error.issues[0]?.message ?? "Enter the sport name.";
    const lower = name.toLowerCase();
    if (customNames.some((n) => n.toLowerCase() === lower) || sports.some((s) => s.code !== OTHER_SPORT_CODE && s.name.toLowerCase() === lower)) {
      return `"${name}" is already in the list.`;
    }
    setSportsError(null);
    setCustomNames((prev) => [...prev, name]);
    setActiveSportId(customKey(name));
    return null;
  }

  function removeCustom(name: string) {
    const key = customKey(name);
    setCustomNames((prev) => prev.filter((n) => n !== name));
    setDrafts((prev) => prev.filter((d) => d.sportId !== key));
  }

  function changeCourt(id: string, patch: Partial<CourtDraft>) {
    setDrafts((prev) => prev.map((c) => (c.id === id ? { ...c, ...patch } : c)));
    setProblems((prev) => {
      if (!prev.byCourt[id]) return prev;
      const byCourt = { ...prev.byCourt };
      delete byCourt[id];
      return { ...prev, byCourt };
    });
  }

  function addCourt(sportId: string) {
    const sport = selectedSports.find((s) => s.id === sportId);
    if (!sport) return;
    setDrafts((prev) => [...prev, newCourtDraft({ id: crypto.randomUUID(), sportId, sportCode: sport.code, sportName: sport.name, existing: prev })]);
    setProblems((prev) => {
      const bySport = { ...prev.bySport };
      delete bySport[sportId];
      return { ...prev, bySport };
    });
  }

  function removeCourt(id: string) {
    setDrafts((prev) => prev.filter((c) => c.id !== id));
  }

  function bulkApply(sportId: string, patch: Partial<CourtSettings>) {
    setDrafts((prev) => applyToSport(prev, sportId, patch));
  }

  function editFromPreview(court: CourtDraft) {
    setMode("court");
    setActiveSportId(court.sportId);
    window.setTimeout(() => document.getElementById(`court-${court.id}-name`)?.focus(), 50);
  }

  // ── save ──────────────────────────────────────────────────────────
  function checkSelection(): boolean {
    if (selectedIds.length + customNames.length === 0) {
      setSportsError("Select at least one sport to continue.");
      return false;
    }
    if (customNames.length > 0 && !otherId) {
      setSportsError("Adding your own sport isn't available right now. Please pick from the list.");
      return false;
    }
    return true;
  }

  async function persist(advance: boolean) {
    if (!facility) return;
    setSaveError(null);
    const selectionOk = checkSelection();
    const found = validateCourtDrafts(
      drafts.filter((d) => selectedSports.some((s) => s.id === d.sportId)),
      selectedSports,
    );
    setProblems(found);
    if (!selectionOk || !found.ok) {
      setSaveError("Please fix the highlighted fields to continue.");
      return;
    }

    setSaving(advance ? "next" : "draft");
    try {
      const keep = drafts.filter((d) => selectedSports.some((s) => s.id === d.sportId));
      const keepSaved = new Set(keep.map((d) => d.savedId).filter((v): v is string => !!v));

      // 1. courts that were removed (or belong to a sport that was switched off) are archived first
      const toArchive = [...loadedCourtIds.current].filter((id) => !keepSaved.has(id));
      for (const id of toArchive) await getPlayingAreasService().removePlayingArea(id);
      loadedCourtIds.current = new Set([...loadedCourtIds.current].filter((id) => keepSaved.has(id)));

      // 2. the sports
      const saved = await getSportsService().saveFacilitySports(facility.id, [
        ...selectedIds.map((sportId) => ({ facilityId: facility.id, sportId, enabled: true })),
        ...customNames.map((name) => ({ facilityId: facility.id, sportId: otherId as string, enabled: true, customSportName: name })),
      ]);
      const facilitySportFor = (key: string) =>
        key.startsWith(CUSTOM_PREFIX)
          ? saved.find((r) => r.sportId === otherId && (r.customSportName ?? "").trim().toLowerCase() === key.slice(CUSTOM_PREFIX.length))?.id
          : saved.find((r) => r.sportId === key && !r.customSportName)?.id;

      // 3. the courts
      const next: CourtDraft[] = [];
      const orderWithinSport: Record<string, number> = {};
      for (const court of keep) {
        const facilitySportId = facilitySportFor(court.sportId);
        if (!facilitySportId) throw new ServiceError("FACILITY_SPORT_NOT_FOUND");
        const order = (orderWithinSport[court.sportId] = (orderWithinSport[court.sportId] ?? -1) + 1);
        const common = {
          name: court.name.trim(),
          type: court.type,
          surface: court.surface.trim(),
          lighting: court.lighting || undefined,
          amenities: court.amenities,
          displayOrder: order,
        };
        if (court.savedId) {
          await getPlayingAreasService().updatePlayingArea(court.savedId, common);
          next.push(court);
        } else {
          const created = await getPlayingAreasService().createPlayingArea({
            id: court.id,
            facilityId: facility.id,
            facilitySportId,
            // a sport the owner added is the catalogue's "Other" sport with its own name
            sportId: court.sportId.startsWith(CUSTOM_PREFIX) ? (otherId as string) : court.sportId,
            status: DEFAULT_PLAYING_AREA_STATUS,
            bookingEnabled: DEFAULT_BOOKING_ENABLED,
            archived: false,
            ...common,
          });
          loadedCourtIds.current.add(created.id);
          next.push({ ...court, savedId: created.id });
        }
      }
      setDrafts((prev) => prev.map((d) => next.find((n) => n.id === d.id) ?? d));

      if (advance) {
        await getFacilityService().updateOnboardingStep(facility.id, "OPERATING_HOURS");
        completeSports();
        completeCourts();
        router.push("/onboarding/operating-hours");
      } else {
        toast.success("Draft saved. You can pick up where you left off.");
      }
    } catch (e) {
      setSaveError(e instanceof ServiceError && e.message ? e.message : "We couldn't save your sports and courts. Please try again.");
    } finally {
      setSaving(null);
    }
  }

  // ── render ────────────────────────────────────────────────────────
  if (userLoading || loadState === "loading") {
    return (
      <div className="space-y-5">
        <Skeleton className="h-44 w-full rounded-2xl" />
        <Skeleton className="h-72 w-full rounded-2xl" />
      </div>
    );
  }
  if (loadState === "forbidden") return <ErrorState title="Access Denied" message="You don't have access to this facility." />;
  if (!facility) return null;

  return (
    <div className="space-y-5">
      {saveError && <FormMessage>{saveError}</FormMessage>}

      <SportsPicker
        sports={sports}
        selectedIds={selectedIds}
        onToggle={toggleSport}
        customSports={customNames}
        onAddCustom={addCustom}
        onRemoveCustom={removeCustom}
        error={sportsError}
      />

      <CourtsConfig
        sports={selectedSports}
        drafts={drafts.filter((d) => selectedSports.some((s) => s.id === d.sportId))}
        activeSportId={activeSportId}
        onActiveSport={setActiveSportId}
        mode={mode}
        onModeChange={setMode}
        onChange={changeCourt}
        onBulk={bulkApply}
        onAdd={addCourt}
        onRemove={removeCourt}
        problems={problems}
      />

      <CourtsPreview
        sports={selectedSports}
        drafts={drafts.filter((d) => selectedSports.some((s) => s.id === d.sportId))}
        onEdit={editFromPreview}
        onRemove={removeCourt}
      />

      <div className="flex flex-wrap items-center justify-between gap-3 border-t border-[#E5E1EF] pt-5">
        <button
          type="button"
          onClick={() => void persist(false)}
          disabled={saving !== null}
          className="flex h-12 items-center gap-2 rounded-lg border border-[#E5E1EF] bg-white px-5 text-sm font-semibold hover:bg-[#FBFAFE] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#4817C2] disabled:opacity-60"
        >
          {saving === "draft" ? <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" /> : <FileText className="h-4 w-4" aria-hidden="true" />}
          Save as Draft
        </button>
        <div className="flex items-center gap-3">
          <button
            type="button"
            onClick={() => router.push("/onboarding/facility")}
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
