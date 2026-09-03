"use client";

import { useEffect, useState } from "react";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { getFacilityService } from "@/services/facility";
import { getSportsService } from "@/services/sports";
import { getPlayingAreasService } from "@/services/playing-areas";
import type { Facility } from "@/features/onboarding/types";
import { ANALYTICS_PRESETS, PRESET_LABELS, type AnalyticsFilter, type AnalyticsPreset } from "../types";

const ALL_SPORTS = "__all_sports__";
const ALL_COURTS = "__all_courts__";

interface SportOption {
  id: string;
  name: string;
}
interface CourtOption {
  id: string;
  name: string;
  facilitySportId: string;
}

/**
 * The report filter bar (spec §3). Controlled — it holds no filter state of
 * its own, it renders `filter` and calls `onChange` with the next one. The
 * option lists come from the existing facility / sports / playing-area
 * services (Reports never queries those tables itself).
 */
export function AnalyticsFilterBar({
  filter,
  onChange,
  layout = "row",
}: {
  filter: AnalyticsFilter;
  onChange: (next: AnalyticsFilter) => void;
  layout?: "row" | "stack";
}) {
  const [facilities, setFacilities] = useState<Facility[]>([]);
  const [sports, setSports] = useState<SportOption[]>([]);
  const [courts, setCourts] = useState<CourtOption[]>([]);

  useEffect(() => {
    let cancelled = false;
    getFacilityService()
      .getFacilities()
      .then((l) => !cancelled && setFacilities(l))
      .catch(() => {});
    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    let cancelled = false;
    const fid = filter.facilityId;
    if (!fid) return;
    Promise.all([
      getSportsService().getActiveSports(),
      getSportsService().getFacilitySports(fid),
      getPlayingAreasService().getPlayingAreas(fid),
    ])
      .then(([catalog, fs, cs]) => {
        if (cancelled) return;
        setSports(
          fs.map((s) => ({
            id: s.id,
            name: s.customSportName?.trim() || catalog.find((c) => c.id === s.sportId)?.name || "Sport",
          })),
        );
        setCourts(cs.map((c) => ({ id: c.id, name: c.name, facilitySportId: c.facilitySportId })));
      })
      .catch(() => {
        if (!cancelled) {
          setSports([]);
          setCourts([]);
        }
      });
    return () => {
      cancelled = true;
    };
  }, [filter.facilityId]);

  const visibleCourts = filter.facilitySportId
    ? courts.filter((c) => c.facilitySportId === filter.facilitySportId)
    : courts;

  const triggerWidth = layout === "stack" ? "w-full" : undefined;
  const containerClass = layout === "stack" ? "flex flex-col gap-2" : "flex flex-wrap items-center gap-2";

  return (
    <div className={containerClass}>
      {facilities.length > 1 && (
        <Select
          value={filter.facilityId}
          onValueChange={(v) => onChange({ ...filter, facilityId: v, facilitySportId: null, courtId: null })}
        >
          <SelectTrigger className={triggerWidth ?? "w-[180px]"} aria-label="Facility">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            {facilities.map((f) => (
              <SelectItem key={f.id} value={f.id}>
                {f.name}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      )}

      <Select
        value={filter.preset}
        onValueChange={(v) =>
          onChange({
            ...filter,
            preset: v as AnalyticsPreset,
            startDate: v === "CUSTOM" ? (filter.startDate ?? null) : null,
            endDate: v === "CUSTOM" ? (filter.endDate ?? null) : null,
          })
        }
      >
        <SelectTrigger className={triggerWidth ?? "w-[160px]"} aria-label="Date range">
          <SelectValue />
        </SelectTrigger>
        <SelectContent>
          {ANALYTICS_PRESETS.map((p) => (
            <SelectItem key={p} value={p}>
              {PRESET_LABELS[p]}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>

      {filter.preset === "CUSTOM" && (
        <>
          <Input
            type="date"
            aria-label="Start date"
            className={triggerWidth ?? "w-[150px]"}
            value={filter.startDate ?? ""}
            onChange={(e) => onChange({ ...filter, startDate: e.target.value })}
          />
          <span className="text-sm text-muted-foreground">to</span>
          <Input
            type="date"
            aria-label="End date"
            className={triggerWidth ?? "w-[150px]"}
            value={filter.endDate ?? ""}
            onChange={(e) => onChange({ ...filter, endDate: e.target.value })}
          />
        </>
      )}

      <Select
        value={filter.facilitySportId ?? ALL_SPORTS}
        onValueChange={(v) =>
          onChange({ ...filter, facilitySportId: v === ALL_SPORTS ? null : v, courtId: null })
        }
      >
        <SelectTrigger className={triggerWidth ?? "w-[150px]"} aria-label="Sport">
          <SelectValue />
        </SelectTrigger>
        <SelectContent>
          <SelectItem value={ALL_SPORTS}>All Sports</SelectItem>
          {sports.map((s) => (
            <SelectItem key={s.id} value={s.id}>
              {s.name}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>

      <Select
        value={filter.courtId ?? ALL_COURTS}
        onValueChange={(v) => onChange({ ...filter, courtId: v === ALL_COURTS ? null : v })}
      >
        <SelectTrigger className={triggerWidth ?? "w-[150px]"} aria-label="Court">
          <SelectValue />
        </SelectTrigger>
        <SelectContent>
          <SelectItem value={ALL_COURTS}>All Courts</SelectItem>
          {visibleCourts.map((c) => (
            <SelectItem key={c.id} value={c.id}>
              {c.name}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>
    </div>
  );
}
