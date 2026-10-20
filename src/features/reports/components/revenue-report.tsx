"use client";

import { useCallback, useEffect, useState } from "react";
import { Banknote, TrendingUp, Undo2, Wallet } from "lucide-react";
import { Card } from "@/components/ui/card";
import { Donut, type DonutSegment } from "@/components/shared/donut";
import { formatCurrency } from "@/features/pricing/money";
import { RevenueTrendChart } from "@/features/finance/components/revenue-trend-chart";
import type { RevenueTrendPoint } from "@/features/finance/types";
import { getReportsService } from "@/services/reports";
import { useReportRange } from "./use-report-range";
import { DayRangeFilter } from "@/features/finance/components/day-range-filter";
import { MembershipStatCard } from "@/features/memberships/components/membership-stat-card";
import { ReportShell, type ReportStatus } from "./report-shell";
import { ReportBarList } from "./report-bar-list";
import { DataTable } from "./data-table";
import { filterSpanDays, pickGranularityForDays, toCsv } from "../aggregation";
import type {
  PaymentMethodSlice,
  RevenueBreakdown,
  RevenueByCourtRow,
  RevenueBySportRow,
  RevenueSummary,
} from "../types";

const INR = "INR";
const REVENUE_COLOURS = ["#FFB020", "#8B5CF6", "#00D084", "#5B6CFF", "#F97316"];
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
  const { filter, range, setRange, ready } = useReportRange();
  const [dirty, setDirty] = useState(false);

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
    try {
      const [sport, court] = await Promise.all([
        svc.getRevenueBySport(filter),
        svc.getRevenueByCourt(filter),
      ]);
      setBySport(sport);
      setByCourt(court);

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

  // Just the dates: the facility is the one facility, and the sports come from the top bar.
  const filterBar = ready ? <DayRangeFilter value={range} onApply={setRange} onDirtyChange={setDirty} /> : null;

  // Every sport's own revenue — its bookings, its memberships (the sport the member is in) and its coaching. Revenue that
  // belongs to no sport is the last row, labelled as such, rather than being passed off as a sport.
  const sportRows: RevenueBySportRow[] = bySport;

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
          { label: "Coaching", value: breakdown.coachingMinor },
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
    a.download = `revenue-${range.from}-to-${range.to}.csv`;
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
      exportDisabled={dirty}
    >
      <div className="space-y-5">
        {summary && (
          <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
            <MembershipStatCard
              icon={Banknote}
              iconBg="bg-success/15"
              iconColor="text-success"
              value={formatCurrency(summary.grossMinor, INR)}
              countTo={summary.grossMinor}
              format={(v) => formatCurrency(Math.round(v), INR)}
              label="Total Revenue"
              sub="Payments received"
              index={0}
            />
            <MembershipStatCard
              icon={TrendingUp}
              iconBg="bg-blue-500/15"
              iconColor="text-blue-600 dark:text-blue-400"
              value={formatCurrency(summary.netMinor, INR)}
              countTo={summary.netMinor}
              format={(v) => formatCurrency(Math.round(v), INR)}
              label="Net Revenue"
              sub="After refunds and expenses"
              index={1}
            />
            <MembershipStatCard
              icon={Undo2}
              iconBg="bg-destructive/15"
              iconColor="text-destructive"
              value={formatCurrency(summary.refundsMinor, INR)}
              countTo={summary.refundsMinor}
              format={(v) => formatCurrency(Math.round(v), INR)}
              label="Refunds"
              sub="Returned to customers"
              index={2}
            />
            <MembershipStatCard
              icon={Wallet}
              iconBg="bg-warning/15"
              iconColor="text-warning"
              value={formatCurrency(summary.expensesMinor, INR)}
              countTo={summary.expensesMinor}
              format={(v) => formatCurrency(Math.round(v), INR)}
              label="Expenses"
              sub="Recorded expenses (not split by sport)"
              index={3}
            />
          </div>
        )}

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
                />
              </div>
            </>
          )}
        </Card>
      </div>
    </ReportShell>
  );
}
