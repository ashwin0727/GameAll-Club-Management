"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import {
  ArrowRight,
  BadgeIndianRupee,
  Banknote,
  BookOpen,
  CalendarCheck2,
  Coins,
  Crown,
  Download,
  GraduationCap,
  IndianRupee,
  Receipt,
  TrendingUp,
  UserRound,
  Wallet,
  type LucideIcon,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { cn } from "@/lib/utils";
import { formatCurrency } from "@/features/pricing/money";
import { useFacility } from "@/features/facility/hooks/use-facility";
import { useSportFilter } from "@/features/facility/hooks/use-sport-filter";
import { sportSelectionLabel } from "@/features/facility/sport-selection";
import { DayRangeFilter } from "@/features/finance/components/day-range-filter";
import { currentMonthRange, fillTrendBuckets, type DayRange } from "@/features/finance/day-range";
import { downloadCsv } from "@/features/finance/export";
import { MembershipStatCard, MembershipStatCardSkeleton } from "@/features/memberships/components/membership-stat-card";
import { getReportsService } from "@/services/reports";
import { MetricTrendChart } from "./metric-trend-chart";
import { DataTable } from "./data-table";
import { PeakHoursChart } from "./peak-hours-chart";
import { OVERVIEW_METRICS, buildOverviewCsv, metricDef, scopeWord, trendGranularity } from "../overview-metrics";
import { filterToSearchParams } from "../url-state";
import type { AnalyticsFilter, CourtUtilizationRow, OverviewMetricKey, OverviewTrendPoint, PeakHourRow, ReportsOverviewMetrics } from "../types";

const INR = "INR";

/** Icon and chip colours for each card. */
const CARD_STYLE: Record<OverviewMetricKey, { icon: LucideIcon; bg: string; fg: string }> = {
  REVENUE: { icon: Banknote, bg: "bg-success/15", fg: "text-success" },
  EXPENSES: { icon: Wallet, bg: "bg-destructive/15", fg: "text-destructive" },
  NET: { icon: TrendingUp, bg: "bg-indigo-500/15", fg: "text-indigo-600 dark:text-indigo-400" },
  GUEST_BOOKINGS: { icon: CalendarCheck2, bg: "bg-sky-500/15", fg: "text-sky-600 dark:text-sky-400" },
  MEMBERS: { icon: Crown, bg: "bg-purple-500/15", fg: "text-purple-600 dark:text-purple-400" },
  PROGRAMS: { icon: BookOpen, bg: "bg-amber-500/15", fg: "text-amber-600 dark:text-amber-400" },
  COACHES: { icon: UserRound, bg: "bg-teal-500/15", fg: "text-teal-600 dark:text-teal-400" },
  STUDENTS: { icon: GraduationCap, bg: "bg-pink-500/15", fg: "text-pink-600 dark:text-pink-400" },
  GUEST_BOOKING_REVENUE: { icon: IndianRupee, bg: "bg-success/15", fg: "text-success" },
  MEMBERSHIP_REVENUE: { icon: BadgeIndianRupee, bg: "bg-purple-500/15", fg: "text-purple-600 dark:text-purple-400" },
  COACHING_REVENUE: { icon: Coins, bg: "bg-amber-500/15", fg: "text-amber-600 dark:text-amber-400" },
  COACHING_EXPENSES: { icon: Receipt, bg: "bg-destructive/15", fg: "text-destructive" },
};

/**
 * Reports & Analytics — Overview. Twelve cards for the dates picked (the whole current month until changed) and the sports
 * in the top bar; tap a card and the chart below becomes that figure over the same dates. Every number is computed by the
 * database (get_reports_overview / get_reports_overview_trend, migration 0140).
 */
export function ReportsOverview() {
  const { data: facility, isLoading: facilityLoading } = useFacility();
  const facilityId = facility?.id ?? null;
  const sports = useSportFilter(facilityId);
  const sportIds = useMemo(() => (sports.sportSet ? [...sports.sportSet] : null), [sports.sportSet]);
  const sportsSelected = sportIds !== null;
  const scope = scopeWord(sportsSelected);
  const sportsLabel = useMemo(
    () => (sports.isAll ? null : sportSelectionLabel({ ids: sports.selectedIds, isAll: false }, new Map(sports.options.map((o) => [o.facilitySportId, o.name])))),
    [sports.isAll, sports.selectedIds, sports.options],
  );

  const [range, setRange] = useState<DayRange>(() => currentMonthRange());
  const [dirty, setDirty] = useState(false);
  const [selected, setSelected] = useState<OverviewMetricKey>("REVENUE");

  const [metrics, setMetrics] = useState<ReportsOverviewMetrics | null>(null);
  const [trend, setTrend] = useState<OverviewTrendPoint[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [courts, setCourts] = useState<CourtUtilizationRow[]>([]);
  const [peak, setPeak] = useState<{ rows: PeakHourRow[] } | null>(null);

  const granularity = trendGranularity(range);
  const def = metricDef(selected);

  const load = useCallback(async () => {
    if (!facilityId || !sports.ready) return;
    setError(null);
    setMetrics(null);
    const svc = getReportsService();
    const filter: AnalyticsFilter = { facilityId, preset: "CUSTOM", startDate: range.from, endDate: range.to, facilitySportIds: sportIds };
    try {
      const [m, c, p] = await Promise.all([
        svc.getReportsOverview(facilityId, range, sportIds),
        svc.getCourtUtilization(filter),
        svc.getPeakHours(filter),
      ]);
      setMetrics(m);
      setCourts(c);
      setPeak({ rows: p });
    } catch {
      setError("Unable to load analytics. Please try again.");
    }
  }, [facilityId, sports.ready, range, sportIds]);

  useEffect(() => {
    void load();
  }, [load]);

  // The chart follows the selected card, the dates and the sports.
  useEffect(() => {
    if (!facilityId || !sports.ready) return;
    let cancelled = false;
    setTrend(null);
    getReportsService()
      .getReportsOverviewTrend(facilityId, selected, range, granularity, sportIds)
      .then((points) => {
        if (cancelled) return;
        // Quiet days are shown as zero, so the chart spans exactly the dates that were picked.
        setTrend(fillTrendBuckets(points, range, granularity, (date) => ({ date, value: 0 })));
      })
      .catch(() => !cancelled && setTrend([]));
    return () => {
      cancelled = true;
    };
  }, [facilityId, sports.ready, selected, range, granularity, sportIds]);

  const topCourts = useMemo(() => [...courts].sort((a, b) => b.utilizationPct - a.utilizationPct).slice(0, 5), [courts]);

  const reportHref = (path: string) =>
    `${path}?${filterToSearchParams({ facilityId: facilityId ?? "", preset: "CUSTOM", startDate: range.from, endDate: range.to }).toString()}`;

  function handleExport() {
    if (!metrics) return;
    downloadCsv(
      `reports-overview-${range.from}-to-${range.to}.csv`,
      buildOverviewCsv({
        range,
        sportsLabel,
        metrics,
        chart: { title: def.heading(scope), kind: def.kind, points: trend ?? [] },
      }),
    );
  }

  if (facilityLoading) return <Skeleton className="h-96 w-full rounded-xl" />;
  if (!facility) return <p className="text-sm text-muted-foreground">Complete your facility setup to see reports.</p>;

  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="text-xl font-semibold">Reports &amp; Analytics</h1>
          <p className="text-sm text-muted-foreground">
            {sportsSelected ? `Business performance for ${sportsLabel}.` : "Business performance at a glance — all sports."}
          </p>
        </div>
        <div className="flex flex-wrap items-start gap-3">
          <DayRangeFilter value={range} onApply={setRange} onDirtyChange={setDirty} />
          <div className="pt-5">
            <Button
              type="button"
              variant="outline"
              size="sm"
              className="min-h-9"
              disabled={!metrics || dirty}
              title={dirty ? "Apply the new dates first — the export is for the dates on screen." : "Export the dates on screen"}
              onClick={handleExport}
            >
              <Download className="h-4 w-4" aria-hidden /> Export
            </Button>
          </div>
        </div>
      </div>

      {error && (
        <Card className="flex items-center justify-between gap-3 border-destructive/40 p-4">
          <p className="text-sm text-destructive">{error}</p>
          <Button type="button" variant="outline" size="sm" onClick={() => void load()}>
            Try Again
          </Button>
        </Card>
      )}

      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        {metrics === null
          ? Array.from({ length: 12 }).map((_, i) => <MembershipStatCardSkeleton key={i} />)
          : OVERVIEW_METRICS.map((m, i) => {
              const style = CARD_STYLE[m.key];
              const value = m.read(metrics);
              const active = selected === m.key;
              return (
                <button
                  key={m.key}
                  type="button"
                  aria-pressed={active}
                  aria-label={`${m.title}: chart this figure`}
                  onClick={() => setSelected(m.key)}
                  className="rounded-xl text-left focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                >
                  <MembershipStatCard
                    icon={style.icon}
                    iconBg={style.bg}
                    iconColor={style.fg}
                    value={m.kind === "money" ? formatCurrency(value, INR) : value.toLocaleString("en-IN")}
                    countTo={value}
                    format={(v) => (m.kind === "money" ? formatCurrency(Math.round(v), INR) : Math.round(v).toLocaleString("en-IN"))}
                    label={m.title}
                    sub={m.describe(scope) + (m.facilityWide && sportsSelected ? " (not split by sport)" : "")}
                    index={i}
                    className={cn("h-full cursor-pointer transition-all", active ? "border-primary ring-2 ring-primary/30" : "hover:border-primary/40")}
                  />
                </button>
              );
            })}
      </div>

      <Card className="p-4">
        <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
          <div>
            <h2 className="text-sm font-semibold">{def.heading(scope)}</h2>
            <p className="text-xs text-muted-foreground">
              {range.from} to {range.to}
              {def.snapshot ? ` · the card counts those active at any point in these dates; the chart shows how many were added in each ${granularity === "daily" ? "day" : granularity === "weekly" ? "week" : "month"}` : ""}
              {" · select another card above to chart it"}
            </p>
          </div>
        </div>
        {trend === null ? <Skeleton className="h-72 w-full rounded-lg" /> : <MetricTrendChart points={trend} kind={def.kind} color={def.color} name={def.title} />}
      </Card>

      <div className="grid gap-4 lg:grid-cols-2">
        <Card className="p-4">
          <div className="mb-3 flex items-center justify-between gap-3">
            <h2 className="text-sm font-semibold">Top Courts</h2>
            <Link href={reportHref("/reports/court-utilization")} className="inline-flex items-center gap-1 text-xs font-medium text-primary hover:underline">
              View all <ArrowRight className="h-3.5 w-3.5" aria-hidden />
            </Link>
          </div>
          {topCourts.length === 0 ? (
            <p className="text-sm text-muted-foreground">No court activity yet.</p>
          ) : (
            <DataTable
              caption="Top courts by utilization"
              columns={[
                { key: "court", label: "Court" },
                { key: "util", label: "Utilization", align: "right" },
              ]}
              rows={topCourts.map((c) => ({ court: c.courtName, util: `${c.utilizationPct}%` }))}
            />
          )}
        </Card>

        <Card className="p-4">
          <div className="mb-3 flex items-center justify-between gap-3">
            <h2 className="text-sm font-semibold">Peak Hours</h2>
            <Link href={reportHref("/reports/court-utilization")} className="inline-flex items-center gap-1 text-xs font-medium text-primary hover:underline">
              View all <ArrowRight className="h-3.5 w-3.5" aria-hidden />
            </Link>
          </div>
          <PeakHoursChart rows={peak?.rows ?? []} />
        </Card>
      </div>
    </div>
  );
}
