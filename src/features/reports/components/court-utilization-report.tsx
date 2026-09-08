"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { Card } from "@/components/ui/card";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { getReportsService } from "@/services/reports";
import { useAnalyticsFilter } from "./use-analytics-filter";
import { AnalyticsFilterBar } from "./analytics-filter-bar";
import { AnalyticsFilterSheet } from "./analytics-filter-sheet";
import { ReportShell, type ReportStatus } from "./report-shell";
import { ReportBarList } from "./report-bar-list";
import { DataTable } from "./data-table";
import { Heatmap } from "./heatmap";
import { PeakHoursChart } from "./peak-hours-chart";
import { filterToSearchParams } from "../url-state";
import { toCsv } from "../aggregation";
import type {
  CourtUtilizationRow,
  HeatmapCell,
  OverallUtilization,
  PeakHourRow,
  SportUtilizationRow,
} from "../types";

type CourtSort = "high" | "low" | "name";

/** Minutes → "12.5 h". */
function formatHours(minutes: number): string {
  return `${(minutes / 60).toFixed(1)} h`;
}

function formatHourLabel(h: number): string {
  const hour12 = h % 12 === 0 ? 12 : h % 12;
  return `${hour12} ${h < 12 ? "AM" : "PM"}`;
}

export function CourtUtilizationReport() {
  const { filter, setFilter, ready } = useAnalyticsFilter();

  const [status, setStatus] = useState<ReportStatus>("loading");
  const [overall, setOverall] = useState<OverallUtilization | null>(null);
  const [courts, setCourts] = useState<CourtUtilizationRow[]>([]);
  const [sports, setSports] = useState<SportUtilizationRow[]>([]);
  const [peak, setPeak] = useState<PeakHourRow[]>([]);
  const [heatmap, setHeatmap] = useState<HeatmapCell[]>([]);
  const [courtSort, setCourtSort] = useState<CourtSort>("high");

  const load = useCallback(async () => {
    if (!filter) return;
    setStatus("loading");
    const svc = getReportsService();
    try {
      const [o, c, s, p, h] = await Promise.all([
        svc.getOverallUtilization(filter),
        svc.getCourtUtilization(filter),
        svc.getSportUtilization(filter),
        svc.getPeakHours(filter),
        svc.getDemandHeatmap(filter),
      ]);
      setOverall(o);
      setCourts(c);
      setSports(s);
      setPeak(p);
      setHeatmap(h);
      setStatus(o.openMinutes === 0 ? "empty" : "ready");
    } catch {
      setStatus("error");
    }
  }, [filter]);

  useEffect(() => {
    if (ready) void load();
  }, [ready, load]);

  const sortedCourts = useMemo(() => {
    const rows = [...courts];
    if (courtSort === "high") rows.sort((a, b) => b.utilizationPct - a.utilizationPct);
    else if (courtSort === "low") rows.sort((a, b) => a.utilizationPct - b.utilizationPct);
    else rows.sort((a, b) => a.courtName.localeCompare(b.courtName));
    return rows;
  }, [courts, courtSort]);

  const filterBar =
    ready && filter ? (
      <>
        <div className="hidden md:block">
          <AnalyticsFilterBar filter={filter} onChange={setFilter} />
        </div>
        <div className="md:hidden">
          <AnalyticsFilterSheet filter={filter} onChange={setFilter} />
        </div>
      </>
    ) : null;

  function courtHref(courtId: string): string {
    return `/reports/court-utilization?${filterToSearchParams({
      ...filter!,
      courtId,
      facilitySportId: null,
    }).toString()}`;
  }
  function sportHref(facilitySportId: string): string {
    return `/reports/court-utilization?${filterToSearchParams({
      ...filter!,
      facilitySportId,
      courtId: null,
    }).toString()}`;
  }

  function handleExport() {
    if (!filter) return;
    const rows: Array<Record<string, string | number>> = [
      ...sortedCourts.map((c) => ({
        section: "Court",
        name: c.courtName,
        available_h: (c.openMinutes / 60).toFixed(1),
        booked_h: (c.bookedMinutes / 60).toFixed(1),
        utilization_pct: c.utilizationPct,
      })),
      ...sports.map((s) => ({
        section: "Sport",
        name: s.sportName,
        available_h: (s.openMinutes / 60).toFixed(1),
        booked_h: (s.bookedMinutes / 60).toFixed(1),
        utilization_pct: s.utilizationPct,
      })),
      ...peak.map((p) => ({
        section: "Peak hour",
        name: formatHourLabel(p.hour),
        available_h: (p.openMinutes / 60).toFixed(1),
        booked_h: (p.bookedMinutes / 60).toFixed(1),
        utilization_pct: p.demandPct,
      })),
    ];
    const blob = new Blob([toCsv(rows)], { type: "text/csv" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `court-utilization-${filter.facilityId}-${filter.preset}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  }

  const courtBars = sortedCourts.map((c) => ({
    label: c.courtName,
    value: c.utilizationPct,
    color: "#00F08A",
    caption: `${c.utilizationPct}% · ${formatHours(c.bookedMinutes)}/${formatHours(c.openMinutes)}`,
  }));
  const sportBars = sports.map((s) => ({
    label: s.sportName,
    value: s.utilizationPct,
    color: "#00F08A",
    caption: `${s.utilizationPct}% · ${formatHours(s.bookedMinutes)}/${formatHours(s.openMinutes)}`,
  }));

  return (
    <ReportShell
      title="Court Utilization"
      description="How hard each court and sport is working."
      status={status}
      onRetry={load}
      emptyMessage="No court activity for this period."
      errorMessage="Unable to calculate utilization. Please try again."
      filterBar={filterBar}
      onExportCsv={handleExport}
    >
      <div className="space-y-5">
        {overall && (
          <Card className="p-4">
            <h2 className="mb-2 text-sm font-semibold">Overall Utilization</h2>
            <p className="text-3xl font-semibold tabular-nums">{`${Math.round(overall.utilizationPct)}%`}</p>
            <div className="mt-3 h-2 overflow-hidden rounded-full bg-muted">
              <div
                className="h-full rounded-full bg-primary"
                style={{ width: `${Math.min(100, overall.utilizationPct)}%` }}
              />
            </div>
            <p className="mt-2 text-xs text-muted-foreground">
              {formatHours(overall.bookedMinutes)} booked of {formatHours(overall.openMinutes)} bookable
            </p>
          </Card>
        )}

        <Card className="p-4">
          <div className="mb-3 flex items-center justify-between gap-3">
            <h2 className="text-sm font-semibold">By Court</h2>
            <Select value={courtSort} onValueChange={(v) => setCourtSort(v as CourtSort)}>
              <SelectTrigger className="h-9 w-40" aria-label="Sort courts">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="high">Highest first</SelectItem>
                <SelectItem value="low">Lowest first</SelectItem>
                <SelectItem value="name">By name</SelectItem>
              </SelectContent>
            </Select>
          </div>
          {sortedCourts.length === 0 ? (
            <p className="text-sm text-muted-foreground">No courts configured.</p>
          ) : (
            <>
              <ReportBarList items={courtBars} max={100} />
              <div className="mt-4">
                <DataTable
                  caption="Court utilization"
                  columns={[
                    { key: "court", label: "Court" },
                    { key: "available", label: "Available (h)", align: "right" },
                    { key: "booked", label: "Booked (h)", align: "right" },
                    { key: "util", label: "Utilization", align: "right" },
                  ]}
                  rows={sortedCourts.map((c) => ({
                    court: c.courtName,
                    available: (c.openMinutes / 60).toFixed(1),
                    booked: (c.bookedMinutes / 60).toFixed(1),
                    util: `${c.utilizationPct}%`,
                  }))}
                  href={(row) => {
                    const match = sortedCourts.find((c) => c.courtName === row.court);
                    return match ? courtHref(match.courtId) : "#";
                  }}
                />
              </div>
            </>
          )}
        </Card>

        {sports.length > 0 && (
          <Card className="p-4">
            <h2 className="mb-3 text-sm font-semibold">By Sport</h2>
            <ReportBarList items={sportBars} max={100} />
            <div className="mt-4">
              <DataTable
                caption="Sport utilization"
                columns={[
                  { key: "sport", label: "Sport" },
                  { key: "available", label: "Available (h)", align: "right" },
                  { key: "booked", label: "Booked (h)", align: "right" },
                  { key: "util", label: "Utilization", align: "right" },
                ]}
                rows={sports.map((s) => ({
                  sport: s.sportName,
                  available: (s.openMinutes / 60).toFixed(1),
                  booked: (s.bookedMinutes / 60).toFixed(1),
                  util: `${s.utilizationPct}%`,
                }))}
                href={(row) => {
                  const match = sports.find((s) => s.sportName === row.sport);
                  return match ? sportHref(match.facilitySportId) : "#";
                }}
              />
            </div>
          </Card>
        )}

        <Card className="p-4">
          <h2 className="mb-3 text-sm font-semibold">Peak Hours</h2>
          <PeakHoursChart rows={peak} />
          {peak.length > 0 && (
            <div className="mt-4">
              <DataTable
                caption="Peak hours"
                columns={[
                  { key: "hour", label: "Hour" },
                  { key: "demand", label: "Demand", align: "right" },
                  { key: "booked", label: "Booked (min)", align: "right" },
                  { key: "open", label: "Open (min)", align: "right" },
                ]}
                rows={peak.map((p) => ({
                  hour: formatHourLabel(p.hour),
                  demand: `${p.demandPct}%`,
                  booked: Math.round(p.bookedMinutes),
                  open: Math.round(p.openMinutes),
                }))}
              />
            </div>
          )}
        </Card>

        <Card className="p-4">
          <h2 className="mb-3 text-sm font-semibold">Demand Heatmap</h2>
          <Heatmap cells={heatmap} />
        </Card>
      </div>
    </ReportShell>
  );
}
