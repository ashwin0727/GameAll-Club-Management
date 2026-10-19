"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { getFacilityService } from "@/services/facility";
import { useSportIds } from "@/features/facility/hooks/use-sport-filter";
import type { Facility } from "@/features/onboarding/types";
import { filterFromSearchParams, filterToSearchParams } from "../url-state";
import type { AnalyticsFilter } from "../types";

/**
 * The report filter, sourced from and written back to the URL query string.
 * On first load, when the URL has no facility, the user's first facility is
 * used. `setFilter` replaces (not pushes) so the back button doesn't step
 * through every tweak.
 *
 * The top bar's sport selection is folded in as `facilitySportIds` (kept out of the URL), so every report follows
 * it and reloads when it changes.
 */
export function useAnalyticsFilter(): {
  filter: AnalyticsFilter | null;
  facilities: Facility[];
  setFilter: (next: AnalyticsFilter) => void;
  ready: boolean;
} {
  const router = useRouter();
  const pathname = usePathname();
  const params = useSearchParams();
  const [facilities, setFacilities] = useState<Facility[] | null>(null);

  useEffect(() => {
    let cancelled = false;
    getFacilityService()
      .getFacilities()
      .then((list) => !cancelled && setFacilities(list))
      .catch(() => !cancelled && setFacilities([]));
    return () => {
      cancelled = true;
    };
  }, []);

  const fallbackFacilityId = facilities?.[0]?.id ?? "";
  const urlFilter = useMemo<AnalyticsFilter | null>(() => {
    if (facilities === null || !fallbackFacilityId) return null;
    return filterFromSearchParams(params, fallbackFacilityId);
  }, [facilities, fallbackFacilityId, params]);

  const { sportIds, ready: sportsReady, key: sportKey } = useSportIds(urlFilter?.facilityId);
  const filter = useMemo<AnalyticsFilter | null>(
    () => (urlFilter ? { ...urlFilter, facilitySportIds: sportIds } : null),
    // `sportKey` stands in for the ids so an unchanged selection keeps the same filter object.
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [urlFilter, sportKey],
  );

  const setFilter = useCallback(
    (next: AnalyticsFilter) => {
      router.replace(`${pathname}?${filterToSearchParams(next).toString()}`, { scroll: false });
    },
    [router, pathname],
  );

  return {
    filter,
    facilities: facilities ?? [],
    setFilter,
    // Wait for the sport list too, so a report never loads for All Sports and then again for the chosen sport.
    ready: facilities !== null && Boolean(fallbackFacilityId) && sportsReady,
  };
}
