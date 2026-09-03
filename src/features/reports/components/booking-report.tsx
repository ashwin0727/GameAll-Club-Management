"use client";

import { useCallback, useEffect, useState } from "react";
import { TrendingDown, TrendingUp } from "lucide-react";
import { Card } from "@/components/ui/card";
import { formatCurrency } from "@/features/pricing/money";
import { getReportsService } from "@/services/reports";
import { useAnalyticsFilter } from "./use-analytics-filter";
import { AnalyticsFilterBar } from "./analytics-filter-bar";
import { AnalyticsFilterSheet } from "./analytics-filter-sheet";
import { ReportShell, type ReportStatus } from "./report-shell";
import { KpiStrip, type KpiStripItem } from "./kpi-strip";
import { ReportBarList } from "./report-bar-list";
import { DataTable } from "./data-table";
import { BookingTrendChart } from "./booking-trend-chart";
import { filterToSearchParams } from "../url-state";
import { filterSpanDays, pickGranularityForDays, previousPeriod, toCsv } from "../aggregation";
import type {
  BookingAnalytics,
  BookingSourceRow,
  BookingsBySportRow,
  BookingTrendPoint,
} from "../types";

const INR = "INR";
const SOURCE_COLOUR: Record<BookingSourceRow["source"], string> = {
  GUEST: "#FFB020",
  MEMBER: "#8B5CF6",
};

/** Percent change vs the preceding window of equal length, or null. */
function changePct(current: number, previous: number | null): number | null {
  if (previous === null || previous === 0) return null;
  return Math.round(((current - previous) / Math.abs(previous)) * 1000) / 10;
}

function Delta({ pct, invert }: { pct: number | null; invert?: boolean }) {
  if (pct === null) return <span className="text-muted-foreground">vs last period</span>;
  const good = invert ? pct <= 0 : pct >= 0;
  const Icon = pct >= 0 ? TrendingUp : TrendingDown;
  return (
    <span className={`inline-flex items-center gap-0.5 font-medium ${good ? "text-success" : "text-destructive"}`}>
      <Icon className="h-3 w-3" aria-hidden />
      {pct > 0 ? "+" : ""}
      {pct}%
    </span>
  );
}

export function BookingReport() {
  const { filter, setFilter, ready } = useAnalyticsFilter();

  const [status, setStatus] = useState<ReportStatus>("loading");
  const [analytics, setAnalytics] = useState<BookingAnalytics | null>(null);
  const [previous, setPrevious] = useState<BookingAnalytics | null>(null);
  const [trend, setTrend] = useState<BookingTrendPoint[]>([]);
  const [bySport, setBySport] = useState<BookingsBySportRow[]>([]);
  const [sourceSplit, setSourceSplit] = useState<BookingSourceRow[]>([]);

  const load = useCallback(async () => {
    if (!filter) return;
    setStatus("loading");
    const svc = getReportsService();
    const granularity = pickGranularityForDays(filterSpanDays(filter));
    try {
      const [a, t, s, src] = await Promise.all([
        svc.getBookingAnalytics(filter),
        svc.getBookingTrend(filter, granularity),
        svc.getBookingsBySport(filter),
        svc.getBookingSourceSplit(filter),
      ]);
      setAnalytics(a);
      setTrend(t);
      setBySport(s);
      setSourceSplit(src);
      setStatus(a.total === 0 ? "empty" : "ready");

      const prev = previousPeriod(filter);
      if (prev) {
        try {
          setPrevious(await svc.getBookingAnalytics(prev));
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

  const kpis: KpiStripItem[] = analytics
    ? [
        {
          key: "totalBookings",
          label: "Total Bookings",
          value: analytics.total.toLocaleString("en-IN"),
          accent: "#00F08A",
          hint: <Delta pct={changePct(analytics.total, previous?.total ?? null)} />,
        },
        {
          key: "completedBookings",
          label: "Completed",
          value: analytics.completed.toLocaleString("en-IN"),
          accent: "#00D084",
          hint: <Delta pct={changePct(analytics.completed, previous?.completed ?? null)} />,
        },
        {
          key: "confirmedBookings",
          label: "Confirmed",
          value: analytics.confirmed.toLocaleString("en-IN"),
          accent: "#5B6CFF",
        },
        {
          key: "pendingBookings",
          label: "Pending",
          value: analytics.pending.toLocaleString("en-IN"),
          accent: "#FFB020",
        },
        {
          key: "cancelledBookings",
          label: "Cancelled",
          value: analytics.cancelled.toLocaleString("en-IN"),
          accent: "#FF4D67",
          hint: <Delta pct={changePct(analytics.cancelled, previous?.cancelled ?? null)} invert />,
        },
        {
          key: "averageBookingValue",
          label: "Avg Guest Booking",
          value: formatCurrency(analytics.avgGuestBookingValueMinor, INR),
          accent: "#8B5CF6",
        },
      ]
    : [];

  const sportBars = bySport.map((r) => ({ label: r.sportName, value: r.bookingCount, color: "#00F08A" }));
  const sourceBars = sourceSplit.map((r) => ({
    label: r.source === "GUEST" ? "Guest" : "Member",
    value: r.bookingCount,
    color: SOURCE_COLOUR[r.source],
  }));

  function handleExport() {
    if (!analytics || !filter) return;
    const rows: Array<Record<string, string | number>> = [
      { section: "Summary", label: "Total Bookings", value: analytics.total },
      { section: "Summary", label: "Completed", value: analytics.completed },
      { section: "Summary", label: "Confirmed", value: analytics.confirmed },
      { section: "Summary", label: "Pending", value: analytics.pending },
      { section: "Summary", label: "Cancelled", value: analytics.cancelled },
      { section: "Summary", label: "Guest bookings", value: analytics.guestCount },
      { section: "Summary", label: "Member bookings", value: analytics.memberCount },
      {
        section: "Summary",
        label: "Avg guest booking value",
        value: formatCurrency(analytics.avgGuestBookingValueMinor, INR),
      },
      ...bySport.map((r) => ({ section: "By sport", label: r.sportName, value: r.bookingCount })),
      ...trend.map((p) => ({ section: "Trend", label: p.date, value: p.total })),
    ];
    const blob = new Blob([toCsv(rows)], { type: "text/csv" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `bookings-${filter.facilityId}-${filter.preset}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  }

  return (
    <ReportShell
      title="Booking Report"
      description="Volume, status mix and demand by sport."
      status={status}
      onRetry={load}
      emptyMessage="No booking data for this period."
      errorMessage="Unable to load the booking report. Please try again."
      filterBar={filterBar}
      onExportCsv={handleExport}
    >
      <div className="space-y-5">
        <KpiStrip items={kpis} />

        <Card className="p-4">
          <h2 className="mb-3 text-sm font-semibold">Bookings Over Time</h2>
          <BookingTrendChart points={trend} />
          {trend.length > 0 && (
            <div className="mt-4">
              <DataTable
                caption="Bookings over time"
                columns={[
                  { key: "date", label: "Date" },
                  { key: "total", label: "Total", align: "right" },
                  { key: "completed", label: "Completed", align: "right" },
                  { key: "cancelled", label: "Cancelled", align: "right" },
                ]}
                rows={trend.map((p) => ({
                  date: new Date(p.date).toLocaleDateString("en-IN", { day: "2-digit", month: "short" }),
                  total: p.total,
                  completed: p.completed,
                  cancelled: p.cancelled,
                }))}
              />
            </div>
          )}
        </Card>

        <div className="grid gap-4 lg:grid-cols-2">
          <Card className="p-4">
            <h2 className="mb-3 text-sm font-semibold">Bookings by Sport</h2>
            {sportBars.length === 0 ? (
              <p className="text-sm text-muted-foreground">No sports configured.</p>
            ) : (
              <>
                <ReportBarList items={sportBars} />
                <div className="mt-4">
                  <DataTable
                    caption="Bookings by sport"
                    columns={[
                      { key: "sport", label: "Sport" },
                      { key: "count", label: "Bookings", align: "right" },
                    ]}
                    rows={bySport.map((r) => ({ sport: r.sportName, count: r.bookingCount }))}
                    href={(row) =>
                      `/reports/bookings?${filterToSearchParams({
                        ...filter!,
                        facilitySportId:
                          bySport.find((r) => r.sportName === row.sport)?.facilitySportId ?? null,
                        courtId: null,
                      }).toString()}`
                    }
                  />
                </div>
              </>
            )}
          </Card>

          <Card className="p-4">
            <h2 className="mb-3 text-sm font-semibold">Booking Source</h2>
            {sourceBars.every((b) => b.value === 0) ? (
              <p className="text-sm text-muted-foreground">No bookings to split.</p>
            ) : (
              <ReportBarList items={sourceBars} />
            )}
          </Card>
        </div>
      </div>
    </ReportShell>
  );
}
