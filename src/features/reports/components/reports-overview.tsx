"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { ArrowRight } from "lucide-react";
import { Card } from "@/components/ui/card";
import { formatCurrency } from "@/features/pricing/money";
import { RevenueTrendChart } from "@/features/finance/components/revenue-trend-chart";
import type { RevenueTrendPoint } from "@/features/finance/types";
import { getReportsService } from "@/services/reports";
import { useAnalyticsFilter } from "./use-analytics-filter";
import { AnalyticsFilterBar } from "./analytics-filter-bar";
import { AnalyticsFilterSheet } from "./analytics-filter-sheet";
import { ReportShell, type ReportStatus } from "./report-shell";
import { KpiStrip, type KpiStripItem } from "./kpi-strip";
import { KpiDelta, changePct } from "./kpi-delta";
import { DataTable } from "./data-table";
import { PeakHoursChart } from "./peak-hours-chart";
import { filterToSearchParams } from "../url-state";
import { filterSpanDays, pickGranularityForDays, previousPeriod, toCsv } from "../aggregation";
import type { AnalyticsOverview, CourtUtilizationRow, PeakHourRow } from "../types";

const INR = "INR";

export function ReportsOverview() {
  const { filter, setFilter, ready } = useAnalyticsFilter();

  const [status, setStatus] = useState<ReportStatus>("loading");
  const [overview, setOverview] = useState<AnalyticsOverview | null>(null);
  const [previous, setPrevious] = useState<AnalyticsOverview | null>(null);
  const [trend, setTrend] = useState<RevenueTrendPoint[]>([]);
  const [courts, setCourts] = useState<CourtUtilizationRow[]>([]);
  const [peak, setPeak] = useState<PeakHourRow[]>([]);

  const load = useCallback(async () => {
    if (!filter) return;
    setStatus("loading");
    const svc = getReportsService();
    const granularity = pickGranularityForDays(filterSpanDays(filter));
    try {
      const [o, t, c, p] = await Promise.all([
        svc.getAnalyticsOverview(filter),
        svc.getRevenueTrend(filter, granularity),
        svc.getCourtUtilization(filter),
        svc.getPeakHours(filter),
      ]);
      setOverview(o);
      setTrend(t);
      setCourts(c);
      setPeak(p);
      setStatus(o.grossRevenueMinor === 0 && o.totalBookings === 0 ? "empty" : "ready");

      const prev = previousPeriod(filter);
      if (prev) {
        try {
          setPrevious(await svc.getAnalyticsOverview(prev));
        } catch {
          setPrevious(null);
        }
      } else {
        setPrevious(null);
      }
    } catch {
      setStatus("error");
    }
  }, [filter]);

  useEffect(() => {
    if (ready) void load();
  }, [ready, load]);

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

  const reportHref = useMemo(
    () => (path: string) => (filter ? `${path}?${filterToSearchParams(filter).toString()}` : path),
    [filter],
  );

  const topCourts = useMemo(
    () => [...courts].sort((a, b) => b.utilizationPct - a.utilizationPct).slice(0, 5),
    [courts],
  );

  const prominent: KpiStripItem[] = overview
    ? [
        {
          key: "totalRevenue",
          label: "Total Revenue",
          value: formatCurrency(overview.grossRevenueMinor, INR),
          accent: "#00D084",
          href: reportHref("/reports/revenue"),
          hint: <KpiDelta pct={changePct(overview.grossRevenueMinor, previous?.grossRevenueMinor ?? null)} />,
        },
        {
          key: "netRevenue",
          label: "Net Revenue",
          value: formatCurrency(overview.netRevenueMinor, INR),
          accent: "#00F08A",
          href: reportHref("/reports/revenue"),
          hint: <KpiDelta pct={changePct(overview.netRevenueMinor, previous?.netRevenueMinor ?? null)} />,
        },
        {
          key: "totalExpenses",
          label: "Total Expenses",
          value: formatCurrency(overview.expensesMinor, INR),
          accent: "#5B6CFF",
          href: "/finance/expenses",
          hint: <KpiDelta pct={changePct(overview.expensesMinor, previous?.expensesMinor ?? null)} invert />,
        },
        {
          key: "totalBookings",
          label: "Total Bookings",
          value: overview.totalBookings.toLocaleString("en-IN"),
          accent: "#00F08A",
          href: reportHref("/reports/bookings"),
          hint: <KpiDelta pct={changePct(overview.totalBookings, previous?.totalBookings ?? null)} />,
        },
        {
          key: "courtUtilization",
          label: "Court Utilization",
          value: `${Math.round(overview.overallUtilizationPct)}%`,
          accent: "#8B5CF6",
          href: reportHref("/reports/court-utilization"),
          hint: (
            <KpiDelta pct={changePct(overview.overallUtilizationPct, previous?.overallUtilizationPct ?? null)} />
          ),
        },
        {
          key: "outstandingPayments",
          label: "Outstanding Payments",
          value: formatCurrency(overview.outstandingMinor, INR),
          accent: "#FFB020",
          href: "/finance/pending-payments",
          hint: <KpiDelta pct={changePct(overview.outstandingMinor, previous?.outstandingMinor ?? null)} invert />,
        },
      ]
    : [];

  const secondary: KpiStripItem[] = overview
    ? [
        {
          key: "bookingRevenue",
          label: "Booking Revenue",
          value: formatCurrency(overview.bookingRevenueMinor, INR),
          accent: "#00D084",
          href: reportHref("/reports/revenue"),
        },
        {
          key: "membershipRevenue",
          label: "Membership Revenue",
          value: formatCurrency(overview.membershipRevenueMinor, INR),
          accent: "#8B5CF6",
          href: reportHref("/reports/memberships"),
        },
        {
          key: "completedBookings",
          label: "Completed Bookings",
          value: overview.completedBookings.toLocaleString("en-IN"),
          accent: "#00D084",
          href: reportHref("/reports/bookings"),
        },
        {
          key: "cancelledBookings",
          label: "Cancelled Bookings",
          value: overview.cancelledBookings.toLocaleString("en-IN"),
          accent: "#FF4D67",
          href: reportHref("/reports/bookings"),
        },
      ]
    : [];

  function courtHref(courtId: string): string {
    if (!filter) return "/reports/court-utilization";
    return `/reports/court-utilization?${filterToSearchParams({
      ...filter,
      courtId,
      facilitySportId: null,
    }).toString()}`;
  }

  function handleExport() {
    if (!overview || !filter) return;
    const rows: Array<Record<string, string | number>> = [
      { metric: "Total Revenue", value: formatCurrency(overview.grossRevenueMinor, INR) },
      { metric: "Booking Revenue", value: formatCurrency(overview.bookingRevenueMinor, INR) },
      { metric: "Membership Revenue", value: formatCurrency(overview.membershipRevenueMinor, INR) },
      { metric: "Total Expenses", value: formatCurrency(overview.expensesMinor, INR) },
      { metric: "Net Revenue", value: formatCurrency(overview.netRevenueMinor, INR) },
      { metric: "Outstanding Payments", value: formatCurrency(overview.outstandingMinor, INR) },
      { metric: "Total Bookings", value: overview.totalBookings },
      { metric: "Completed Bookings", value: overview.completedBookings },
      { metric: "Cancelled Bookings", value: overview.cancelledBookings },
      { metric: "Court Utilization", value: `${overview.overallUtilizationPct}%` },
      ...topCourts.map((c) => ({ metric: `Court · ${c.courtName}`, value: `${c.utilizationPct}%` })),
    ];
    const blob = new Blob([toCsv(rows)], { type: "text/csv" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `overview-${filter.facilityId}-${filter.preset}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  }

  return (
    <ReportShell
      title="Reports & Analytics"
      description="Business performance at a glance."
      status={status}
      onRetry={load}
      emptyMessage="No activity for this period yet."
      errorMessage="Unable to load analytics. Please try again."
      filterBar={filterBar}
      onExportCsv={handleExport}
    >
      <div className="space-y-5">
        <KpiStrip items={prominent} />
        <KpiStrip items={secondary} />

        <Card className="p-4">
          <h2 className="mb-3 text-sm font-semibold">Revenue Trend</h2>
          <RevenueTrendChart points={trend} />
        </Card>

        <div className="grid gap-4 lg:grid-cols-2">
          <Card className="p-4">
            <div className="mb-3 flex items-center justify-between gap-3">
              <h2 className="text-sm font-semibold">Top Courts</h2>
              <Link
                href={reportHref("/reports/court-utilization")}
                className="inline-flex items-center gap-1 text-xs font-medium text-primary hover:underline"
              >
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
                href={(row) => {
                  const match = topCourts.find((c) => c.courtName === row.court);
                  return match ? courtHref(match.courtId) : "#";
                }}
              />
            )}
          </Card>

          <Card className="p-4">
            <div className="mb-3 flex items-center justify-between gap-3">
              <h2 className="text-sm font-semibold">Peak Hours</h2>
              <Link
                href={reportHref("/reports/court-utilization")}
                className="inline-flex items-center gap-1 text-xs font-medium text-primary hover:underline"
              >
                View all <ArrowRight className="h-3.5 w-3.5" aria-hidden />
              </Link>
            </div>
            <PeakHoursChart rows={peak} />
          </Card>
        </div>
      </div>
    </ReportShell>
  );
}
