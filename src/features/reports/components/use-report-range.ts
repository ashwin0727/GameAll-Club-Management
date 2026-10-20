"use client";

import { useMemo, useState } from "react";
import { useFacility } from "@/features/facility/hooks/use-facility";
import { useSportIds } from "@/features/facility/hooks/use-sport-filter";
import { currentMonthRange, type DayRange } from "@/features/finance/day-range";
import type { AnalyticsFilter } from "../types";

/**
 * What a report page filters by now that the pickers are gone: the facility (there is only the one), the sports ticked
 * in the top bar, and a From / To range — the whole current month until the user applies other dates. `filter` is the
 * same shape every report RPC already takes.
 */
export function useReportRange(): {
  filter: AnalyticsFilter | null;
  range: DayRange;
  setRange: (next: DayRange) => void;
  ready: boolean;
  noFacility: boolean;
} {
  const { data: facility, isLoading } = useFacility();
  const facilityId = facility?.id ?? null;
  const { sportIds, ready: sportsReady } = useSportIds(facilityId);
  const [range, setRange] = useState<DayRange>(() => currentMonthRange());

  const filter = useMemo<AnalyticsFilter | null>(
    () => (facilityId ? { facilityId, preset: "CUSTOM", startDate: range.from, endDate: range.to, facilitySportIds: sportIds } : null),
    [facilityId, range, sportIds],
  );

  return { filter, range, setRange, ready: Boolean(facilityId) && sportsReady, noFacility: !isLoading && !facility };
}
