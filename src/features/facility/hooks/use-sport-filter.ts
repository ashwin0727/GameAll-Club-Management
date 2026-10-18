import { useCallback, useMemo } from "react";
import { useFacilitySportOptions, type FacilitySportOption } from "@/features/facility/hooks/use-facility-sport-options";
import { resolveSportSelection, toggleSportSelection } from "@/features/facility/sport-selection";
import { useUiStore } from "@/stores/ui-store";

export interface SportFilter {
  /** Every sport the facility offers. */
  options: FacilitySportOption[];
  /** The sport list has loaded; until then `sportSet` is null so nothing is hidden. */
  ready: boolean;
  /** The sports in view (all of them under "All Sports"). */
  selectedIds: string[];
  isAll: boolean;
  /**
   * What pages filter by: the ids in view, or `null` for "everything" (All Sports, or the list not loaded yet) —
   * so a not-yet-loaded list never hides anything, and an unfiltered item (one with no sport) still shows.
   */
  sportSet: ReadonlySet<string> | null;
  /** The first sport in view — a sensible default where a flow needs exactly one sport (e.g. creating a plan). */
  primarySportId: string | null;
  toggle: (id: string) => void;
  selectAll: () => void;
}

/**
 * The top bar's "All Sports" choice, for every page: which sports are being looked at, as a set to filter by.
 * One place decides it, so a page can't drift from the bar.
 */
export function useSportFilter(facilityId: string | null | undefined): SportFilter {
  const { data: options = [], isSuccess, isError } = useFacilitySportOptions(facilityId ?? undefined);
  const stored = useUiStore((s) => s.selectedSportIds);
  const setStored = useUiStore((s) => s.setSelectedSportIds);

  const optionIds = useMemo(() => options.map((o) => o.facilitySportId), [options]);
  const resolved = useMemo(() => resolveSportSelection(stored, optionIds), [stored, optionIds]);
  const key = resolved.ids.join("|");
  const sportSet = useMemo(
    () => (!isSuccess || resolved.isAll || optionIds.length === 0 ? null : new Set(resolved.ids)),
    // `key` stands in for the ids so an unchanged selection keeps the same Set (stable memo/query keys downstream).
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [isSuccess, resolved.isAll, optionIds.length, key],
  );

  const toggle = useCallback(
    (id: string) => setStored(toggleSportSelection(useUiStore.getState().selectedSportIds, optionIds, id)),
    [optionIds, setStored],
  );
  const selectAll = useCallback(() => setStored(null), [setStored]);

  return {
    options,
    // A sport list that failed to load counts as ready too: pages then show All Sports instead of waiting forever.
    ready: isSuccess || isError,
    selectedIds: resolved.ids,
    isAll: resolved.isAll,
    sportSet,
    primarySportId: resolved.ids[0] ?? null,
    toggle,
    selectAll,
  };
}

/**
 * The sports in view as what the data layer takes: a stable array of ids, or null for All Sports. `ready` is false
 * until the facility's sport list has loaded, so a page can wait rather than fetch for the wrong sports.
 */
export function useSportIds(facilityId: string | null | undefined): { sportIds: string[] | null; ready: boolean; key: string } {
  const filter = useSportFilter(facilityId);
  const sportIds = useMemo(() => (filter.sportSet ? [...filter.sportSet] : null), [filter.sportSet]);
  return { sportIds, ready: filter.ready, key: sportIds ? sportIds.join("|") : "all" };
}
