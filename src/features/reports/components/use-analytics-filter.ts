"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { getFacilityService } from "@/services/facility";
import type { Facility } from "@/features/onboarding/types";
import { filterFromSearchParams, filterToSearchParams } from "../url-state";
import type { AnalyticsFilter } from "../types";

/**
 * The report filter, sourced from and written back to the URL query string.
 * On first load, when the URL has no facility, the user's first facility is
 * used. `setFilter` replaces (not pushes) so the back button doesn't step
 * through every tweak.
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
  const filter = useMemo<AnalyticsFilter | null>(() => {
    if (facilities === null || !fallbackFacilityId) return null;
    return filterFromSearchParams(params, fallbackFacilityId);
  }, [facilities, fallbackFacilityId, params]);

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
    ready: facilities !== null && Boolean(fallbackFacilityId),
  };
}
