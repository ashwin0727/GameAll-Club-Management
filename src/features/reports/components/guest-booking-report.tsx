"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
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
import { filterToSearchParams } from "../url-state";
import { toCsv } from "../aggregation";
import type {
  GuestBookingAnalytics,
  GuestBookingsByCourtRow,
  GuestBookingsBySportRow,
  GuestPeakHourRow,
} from "../types";

const INR = "INR";

function formatHourLabel(h: number): string {
  const hour12 = h % 12 === 0 ? 12 : h % 12;
  return `${hour12} ${h < 12 ? "AM" : "PM"}`;
}

export function GuestBookingReport() {
  const { filter, setFilter, ready } = useAnalyticsFilter();

  const [status, setStatus] = useState<ReportStatus>("loading");
  const [analytics, setAnalytics] = useState<GuestBookingAnalytics | null>(null);
  const [bySport, setBySport] = useState<GuestBookingsBySportRow[]>([]);
  const [byCourt, setByCourt] = useState<GuestBookingsByCourtRow[]>([]);
  const [peak, setPeak] = useState<GuestPeakHourRow[]>([]);

  const load = useCallback(async () => {
    if (!filter) return;
    setStatus("loading");
    const svc = getReportsService();
    try {
      const [a, s, c, p] = await Promise.all([
        svc.getGuestBookingAnalytics(filter),
        svc.getGuestBookingsBySport(filter),
        svc.getGuestBookingsByCourt(filter),
        svc.getGuestPeakHours(filter),
      ]);
      setAnalytics(a);
      setBySport(s);
      setByCourt(c);
      setPeak(p);
      setStatus(a.total === 0 ? "empty" : "ready");
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
          label: "Total Guest Bookings",
          value: analytics.total.toLocaleString("en-IN"),
          accent: "#FFB020",
        },
        {
          key: "completedBookings",
          label: "Completed",
          value: analytics.completed.toLocaleString("en-IN"),
          accent: "#00D084",
        },
        {
          key: "cancelledBookings",
          label: "Cancelled",
          value: analytics.cancelled.toLocaleString("en-IN"),
          accent: "#FF4D67",
        },
        {
          key: "guestBookingRevenue",
          label: "Guest Revenue",
          value: formatCurrency(analytics.revenueMinor, INR),
          accent: "#00D084",
        },
        {
          key: "averageBookingValue",
          label: "Avg Booking Value",
          value: formatCurrency(analytics.avgBookingValueMinor, INR),
          accent: "#8B5CF6",
        },
        {
          key: "guestBookingCollectionRate",
          label: "Collection Rate",
          value: `${analytics.collectionRatePct}%`,
          accent: "#5B6CFF",
        },
      ]
    : [];

  const sportBars = bySport
    .filter((r) => r.bookingCount > 0)
    .map((r) => ({
      label: r.sportName,
      value: r.bookingCount,
      color: "#FFB020",
      caption: `${r.bookingCount} · ${formatCurrency(r.revenueMinor, INR)}`,
    }));
  const courtBars = byCourt
    .filter((r) => r.bookingCount > 0)
    .map((r) => ({
      label: r.courtName,
      value: r.bookingCount,
      color: "#FFB020",
      caption: `${r.bookingCount} · ${formatCurrency(r.revenueMinor, INR)}`,
    }));
  const hourBars = peak.map((r) => ({ label: formatHourLabel(r.hour), value: r.bookingCount, color: "#FFB020" }));

  function handleExport() {
    if (!analytics || !filter) return;
    const rows: Array<Record<string, string | number>> = [
      { section: "Summary", label: "Total", value: analytics.total },
      { section: "Summary", label: "Completed", value: analytics.completed },
      { section: "Summary", label: "Cancelled", value: analytics.cancelled },
      { section: "Summary", label: "Guest revenue", value: formatCurrency(analytics.revenueMinor, INR) },
      { section: "Summary", label: "Avg booking value", value: formatCurrency(analytics.avgBookingValueMinor, INR) },
      { section: "Summary", label: "Collected", value: formatCurrency(analytics.collectedMinor, INR) },
      { section: "Summary", label: "Outstanding", value: formatCurrency(analytics.outstandingMinor, INR) },
      { section: "Summary", label: "Collection rate", value: `${analytics.collectionRatePct}%` },
      ...bySport.map((r) => ({ section: "By sport", label: r.sportName, value: r.bookingCount })),
      ...byCourt.map((r) => ({ section: "By court", label: r.courtName, value: r.bookingCount })),
      ...peak.map((r) => ({ section: "Peak hour", label: formatHourLabel(r.hour), value: r.bookingCount })),
    ];
    const blob = new Blob([toCsv(rows)], { type: "text/csv" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `guest-bookings-${filter.facilityId}-${filter.preset}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  }

  return (
    <ReportShell
      title="Guest Booking Report"
      description="Guest volume, value and collection."
      status={status}
      onRetry={load}
      emptyMessage="No guest bookings for this period."
      errorMessage="Unable to load the guest booking report. Please try again."
      filterBar={filterBar}
      onExportCsv={handleExport}
    >
      <div className="space-y-5">
        <KpiStrip items={kpis} />

        <div className="grid gap-4 lg:grid-cols-2">
          <Card className="p-4">
            <h2 className="mb-3 text-sm font-semibold">Guest Bookings by Sport</h2>
            {sportBars.length === 0 ? (
              <p className="text-sm text-muted-foreground">No guest bookings by sport.</p>
            ) : (
              <>
                <ReportBarList items={sportBars} />
                <div className="mt-4">
                  <DataTable
                    caption="Guest bookings by sport"
                    columns={[
                      { key: "sport", label: "Sport" },
                      { key: "bookings", label: "Bookings", align: "right" },
                      { key: "revenue", label: "Revenue", align: "right" },
                    ]}
                    rows={bySport.map((r) => ({
                      sport: r.sportName,
                      bookings: r.bookingCount,
                      revenue: formatCurrency(r.revenueMinor, INR),
                    }))}
                    href={(row) => {
                      const match = bySport.find((r) => r.sportName === row.sport);
                      return match
                        ? `/reports/guest-bookings?${filterToSearchParams({
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
            <h2 className="mb-3 text-sm font-semibold">Guest Bookings by Court</h2>
            {courtBars.length === 0 ? (
              <p className="text-sm text-muted-foreground">No guest bookings by court.</p>
            ) : (
              <>
                <ReportBarList items={courtBars} />
                <div className="mt-4">
                  <DataTable
                    caption="Guest bookings by court"
                    columns={[
                      { key: "court", label: "Court" },
                      { key: "bookings", label: "Bookings", align: "right" },
                      { key: "revenue", label: "Revenue", align: "right" },
                    ]}
                    rows={byCourt.map((r) => ({
                      court: r.courtName,
                      bookings: r.bookingCount,
                      revenue: formatCurrency(r.revenueMinor, INR),
                    }))}
                    href={(row) => {
                      const match = byCourt.find((r) => r.courtName === row.court);
                      return match
                        ? `/reports/guest-bookings?${filterToSearchParams({
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

        <div className="grid gap-4 lg:grid-cols-2">
          <Card className="p-4">
            <h2 className="mb-3 text-sm font-semibold">Peak Guest Hours</h2>
            {hourBars.length === 0 ? (
              <p className="text-sm text-muted-foreground">No guest booking activity.</p>
            ) : (
              <>
                <ReportBarList items={hourBars} />
                <div className="mt-4">
                  <DataTable
                    caption="Peak guest hours"
                    columns={[
                      { key: "hour", label: "Hour" },
                      { key: "bookings", label: "Bookings", align: "right" },
                    ]}
                    rows={peak.map((r) => ({ hour: formatHourLabel(r.hour), bookings: r.bookingCount }))}
                  />
                </div>
              </>
            )}
          </Card>

          {analytics && (
            <Card className="p-4">
              <h2 className="mb-3 text-sm font-semibold">Payment Collection</h2>
              <DataTable
                caption="Guest payment collection"
                columns={[
                  { key: "metric", label: "Metric" },
                  { key: "value", label: "Value", align: "right" },
                ]}
                rows={[
                  { metric: "Collected", value: formatCurrency(analytics.collectedMinor, INR) },
                  { metric: "Outstanding", value: formatCurrency(analytics.outstandingMinor, INR) },
                  { metric: "Collection rate", value: `${analytics.collectionRatePct}%` },
                ]}
              />
              <p className="mt-3 text-xs text-muted-foreground">
                <Link href="/finance/pending-payments" className="text-primary hover:underline">
                  Collect outstanding →
                </Link>
              </p>
            </Card>
          )}
        </div>
      </div>
    </ReportShell>
  );
}
