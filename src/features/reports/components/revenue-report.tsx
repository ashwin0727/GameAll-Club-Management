"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { Card } from "@/components/ui/card";
import { Donut, type DonutSegment } from "@/components/shared/donut";
import { formatCurrency } from "@/features/pricing/money";
import { RevenueTrendChart } from "@/features/finance/components/revenue-trend-chart";
import type { RevenueTrendPoint } from "@/features/finance/types";
import { getReportsService } from "@/services/reports";
import { useAnalyticsFilter } from "./use-analytics-filter";
import { AnalyticsFilterBar } from "./analytics-filter-bar";
import { AnalyticsFilterSheet } from "./analytics-filter-sheet";
import { ReportShell, type ReportStatus } from "./report-shell";
import { KpiStrip, type KpiStripItem } from "./kpi-strip";
import { ReportBarList } from "./report-bar-list";
import { DataTable } from "./data-table";
import { filterToSearchParams } from "../url-state";
import { filterSpanDays, pickGranularityForDays, toCsv } from "../aggregation";
import type {
  PaymentMethodSlice,
  RevenueBreakdown,
  RevenueByCourtRow,
  RevenueBySportRow,
  RevenueSummary,
} from "../types";

const INR = "INR";
const REVENUE_COLOURS = ["#FFB020", "#8B5CF6", "#00D084", "#5B6CFF"];
const METHOD_COLOURS = ["#5B6CFF", "#00D084", "#8B5CF6", "#FFB020", "#FF4D67"];

/** Drops zero slices and assigns a colour + formatted caption (from finance-dashboard.tsx). */
function segmentsFrom(rows: { label: string; value: number }[], colours: string[]): DonutSegment[] {
  const live = rows.filter((r) => r.value > 0);
  const total = live.reduce((sum, r) => sum + r.value, 0);
  return live.map((row, i) => ({
    label: row.label,
    value: row.value,
    color: colours[i % colours.length]!,
    caption: `${formatCurrency(row.value, INR)} (${total ? Math.round((row.value / total) * 1000) / 10 : 0}%)`,
  }));
}

function totalOf(segments: DonutSegment[]): number {
  return segments.reduce((sum, s) => sum + s.value, 0);
}

export function RevenueReport() {
  const { filter, setFilter, ready } = useAnalyticsFilter();
  const scoped = Boolean(filter?.facilitySportId || filter?.courtId);

  const [status, setStatus] = useState<ReportStatus>("loading");
  const [summary, setSummary] = useState<RevenueSummary | null>(null);
  const [trend, setTrend] = useState<RevenueTrendPoint[]>([]);
  const [breakdown, setBreakdown] = useState<RevenueBreakdown | null>(null);
  const [methods, setMethods] = useState<PaymentMethodSlice[]>([]);
  const [bySport, setBySport] = useState<RevenueBySportRow[]>([]);
  const [byCourt, setByCourt] = useState<RevenueByCourtRow[]>([]);

  const load = useCallback(async () => {
    if (!filter) return;
    setStatus("loading");
    const svc = getReportsService();
    const isScoped = Boolean(filter.facilitySportId || filter.courtId);
    try {
      const [sport, court] = await Promise.all([
        svc.getRevenueBySport(filter),
        svc.getRevenueByCourt(filter),
      ]);
      setBySport(sport);
      setByCourt(court);

      if (isScoped) {
        setSummary(null);
        setTrend([]);
        setBreakdown(null);
        setMethods([]);
        setStatus(sport.every((r) => r.revenueMinor === 0) ? "empty" : "ready");
        return;
      }

      const granularity = pickGranularityForDays(filterSpanDays(filter));
      const [s, t, b, m] = await Promise.all([
        svc.getRevenueSummary(filter),
        svc.getRevenueTrend(filter, granularity),
        svc.getRevenueBreakdown(filter),
        svc.getPaymentMethodBreakdown(filter),
      ]);
      setSummary(s);
      setTrend(t);
      setBreakdown(b);
      setMethods(m);
      setStatus(s.grossMinor === 0 ? "empty" : "ready");
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

  const kpis: KpiStripItem[] = summary
    ? [
        { key: "totalRevenue", label: "Total Revenue", value: formatCurrency(summary.grossMinor, INR), accent: "#00D084" },
        { key: "netRevenue", label: "Net Revenue", value: formatCurrency(summary.netMinor, INR), accent: "#00F08A" },
        { key: "refunds", label: "Refunds", value: formatCurrency(summary.refundsMinor, INR), accent: "#FF4D67" },
        { key: "totalExpenses", label: "Expenses", value: formatCurrency(summary.expensesMinor, INR), accent: "#5B6CFF" },
      ]
    : [];

  const sportRows: RevenueBySportRow[] = breakdown
    ? [...bySport, { facilitySportId: "__membership__", sportName: "Memberships", revenueMinor: breakdown.membershipMinor }]
    : bySport;

  const sportBars = sportRows
    .filter((r) => r.revenueMinor > 0)
    .map((r) => ({ label: r.sportName, value: r.revenueMinor, color: "#00D084", caption: formatCurrency(r.revenueMinor, INR) }));
  const courtBars = byCourt
    .filter((r) => r.revenueMinor > 0)
    .map((r) => ({ label: r.courtName, value: r.revenueMinor, color: "#00D084", caption: formatCurrency(r.revenueMinor, INR) }));

  const revenueSegments = breakdown
    ? segmentsFrom(
        [
          { label: "Guest Bookings", value: breakdown.guestBookingMinor },
          { label: "Memberships", value: breakdown.membershipMinor },
          { label: "Member Bookings", value: breakdown.memberBookingMinor },
        ],
        REVENUE_COLOURS,
      )
    : [];
  const methodSegments = segmentsFrom(
    methods.map((m) => ({ label: m.method, value: m.amountMinor })),
    METHOD_COLOURS,
  );

  function handleExport() {
    if (!filter) return;
    const rows: Array<Record<string, string | number>> = [
      ...sportRows.map((r) => ({ section: "By sport", name: r.sportName, revenue: formatCurrency(r.revenueMinor, INR) })),
      ...byCourt.map((r) => ({ section: "By court", name: r.courtName, revenue: formatCurrency(r.revenueMinor, INR) })),
      ...trend.map((p) => ({ section: "Trend", name: p.date, revenue: formatCurrency(p.grossMinor, INR) })),
    ];
    const blob = new Blob([toCsv(rows)], { type: "text/csv" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `revenue-${filter.facilityId}-${filter.preset}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  }

  return (
    <ReportShell
      title="Revenue Report"
      description="Trend, breakdown and payment methods."
      status={status}
      onRetry={load}
      emptyMessage="No revenue data for this period."
      errorMessage="Unable to load the revenue report. Please try again."
      filterBar={filterBar}
      onExportCsv={handleExport}
    >
      <div className="space-y-5">
        {scoped && filter && (
          <p className="text-xs text-muted-foreground">
            Trend, breakdown and payment methods show the whole facility.{" "}
            <Link
              href={`/reports/revenue?facility=${filter.facilityId}&preset=${filter.preset}`}
              className="text-primary hover:underline"
            >
              Clear sport &amp; court
            </Link>
          </p>
        )}

        {kpis.length > 0 && <KpiStrip items={kpis} />}

        {!scoped && (
          <Card className="p-4">
            <h2 className="mb-3 text-sm font-semibold">Revenue Trend</h2>
            <RevenueTrendChart points={trend} />
            {trend.length > 0 && (
              <div className="mt-4">
                <DataTable
                  caption="Revenue over time"
                  columns={[
                    { key: "date", label: "Date" },
                    { key: "gross", label: "Gross", align: "right" },
                    { key: "refunds", label: "Refunds", align: "right" },
                    { key: "net", label: "Net", align: "right" },
                  ]}
                  rows={trend.map((p) => ({
                    date: new Date(p.date).toLocaleDateString("en-IN", { day: "2-digit", month: "short" }),
                    gross: formatCurrency(p.grossMinor, INR),
                    refunds: formatCurrency(p.refundMinor, INR),
                    net: formatCurrency(p.netMinor, INR),
                  }))}
                />
              </div>
            )}
          </Card>
        )}

        {!scoped && (
          <div className="grid gap-4 lg:grid-cols-2">
            <Card className="p-4">
              <h2 className="mb-3 text-sm font-semibold">Revenue Breakdown</h2>
              {revenueSegments.length === 0 ? (
                <p className="text-sm text-muted-foreground">No revenue to break down yet.</p>
              ) : (
                <>
                  <Donut
                    segments={revenueSegments}
                    centreValue={formatCurrency(totalOf(revenueSegments), INR)}
                    centreLabel="Total"
                  />
                  <div className="mt-4">
                    <DataTable
                      caption="Revenue breakdown"
                      columns={[
                        { key: "source", label: "Source" },
                        { key: "amount", label: "Revenue", align: "right" },
                      ]}
                      rows={revenueSegments.map((s) => ({ source: s.label, amount: formatCurrency(s.value, INR) }))}
                    />
                  </div>
                </>
              )}
            </Card>

            <Card className="p-4">
              <h2 className="mb-3 text-sm font-semibold">Payment Methods</h2>
              {methodSegments.length === 0 ? (
                <p className="text-sm text-muted-foreground">No payments taken in this period.</p>
              ) : (
                <>
                  <Donut
                    segments={methodSegments}
                    centreValue={formatCurrency(totalOf(methodSegments), INR)}
                    centreLabel="Total"
                  />
                  <div className="mt-4">
                    <DataTable
                      caption="Payment methods"
                      columns={[
                        { key: "method", label: "Method" },
                        { key: "amount", label: "Collected", align: "right" },
                      ]}
                      rows={methodSegments.map((s) => ({ method: s.label, amount: formatCurrency(s.value, INR) }))}
                    />
                  </div>
                </>
              )}
            </Card>
          </div>
        )}

        <Card className="p-4">
          <h2 className="mb-3 text-sm font-semibold">Revenue by Sport</h2>
          {sportBars.length === 0 ? (
            <p className="text-sm text-muted-foreground">No sport revenue in this period.</p>
          ) : (
            <>
              <ReportBarList items={sportBars} />
              <div className="mt-4">
                <DataTable
                  caption="Revenue by sport"
                  columns={[
                    { key: "sport", label: "Sport" },
                    { key: "revenue", label: "Revenue", align: "right" },
                  ]}
                  rows={sportRows.map((r) => ({ sport: r.sportName, revenue: formatCurrency(r.revenueMinor, INR) }))}
                  href={(row) => {
                    const match = bySport.find((r) => r.sportName === row.sport);
                    return match
                      ? `/reports/revenue?${filterToSearchParams({
                          ...filter!,
                          facilitySportId: match.facilitySportId,
                          courtId: null,
                        }).toString()}`
                      : "#";
                  }}
                />
              </div>
            </>
          )}
        </Card>

        <Card className="p-4">
          <h2 className="mb-3 text-sm font-semibold">Revenue by Court</h2>
          {courtBars.length === 0 ? (
            <p className="text-sm text-muted-foreground">No court revenue in this period.</p>
          ) : (
            <>
              <ReportBarList items={courtBars} />
              <div className="mt-4">
                <DataTable
                  caption="Revenue by court"
                  columns={[
                    { key: "court", label: "Court" },
                    { key: "revenue", label: "Revenue", align: "right" },
                  ]}
                  rows={byCourt.map((r) => ({ court: r.courtName, revenue: formatCurrency(r.revenueMinor, INR) }))}
                  href={(row) => {
                    const match = byCourt.find((r) => r.courtName === row.court);
                    return match
                      ? `/reports/revenue?${filterToSearchParams({
                          ...filter!,
                          courtId: match.courtId,
                          facilitySportId: null,
                        }).toString()}`
                      : "#";
                  }}
                />
              </div>
            </>
          )}
        </Card>
      </div>
    </ReportShell>
  );
}
