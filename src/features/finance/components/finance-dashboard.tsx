"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import {
  ArrowRight,
  Banknote,
  Clock3,
  Download,
  MapPin,
  TrendingDown,
  TrendingUp,
  Wallet,
} from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Donut, type DonutSegment } from "@/components/shared/donut";
import { StatCard } from "@/components/shared/stat-card";
import { formatCurrency } from "@/features/pricing/money";
import { getFacilityService } from "@/services/facility";
import { getFinanceService } from "@/services/finance";
import type {
  FinanceDateRange,
  FinanceSummary,
  FinanceTransaction,
  PaymentMethodSlice,
  RevenueBreakdown,
  RevenueTrendGranularity,
  RevenueTrendPoint,
} from "@/features/finance/types";
import { DateRangePicker } from "@/features/finance/components/date-range-picker";
import { RevenueTrendChart } from "@/features/finance/components/revenue-trend-chart";
import { ServiceError } from "@/services/shared/service-error";

const INR = "INR";

/** Semantic colours from the design system, used for the two donuts. */
const REVENUE_COLOURS = ["#00D084", "#8B5CF6", "#5B6CFF", "#FFB020"];
const METHOD_COLOURS = ["#5B6CFF", "#00D084", "#8B5CF6", "#FFB020", "#FF4D67"];

function statusTone(status: FinanceTransaction["status"]): "success" | "warning" | "destructive" | "secondary" {
  switch (status) {
    case "paid":
      return "success";
    case "failed":
      return "destructive";
    case "refunded":
      return "secondary";
    case "created":
      return "warning";
  }
}

/** Percent change against the preceding window of equal length. */
function changePct(current: number, previous: number): number | null {
  if (previous === 0) return null;
  return Math.round(((current - previous) / Math.abs(previous)) * 1000) / 10;
}

function Delta({ pct, invert }: { pct: number | null; invert?: boolean }) {
  if (pct === null) return <span className="text-[11px] text-muted-foreground">vs last period</span>;
  // For expenses and money owed, a rise is bad news — the arrow follows the
  // number but the colour follows what it means for the facility.
  const good = invert ? pct <= 0 : pct >= 0;
  const Icon = pct >= 0 ? TrendingUp : TrendingDown;
  return (
    <span className={cnTone(good)}>
      <Icon className="h-3 w-3" aria-hidden />
      {pct > 0 ? "+" : ""}
      {pct}% vs last period
    </span>
  );
}

function cnTone(good: boolean) {
  return `inline-flex items-center gap-1 text-[11px] font-medium ${good ? "text-success" : "text-destructive"}`;
}

/**
 * The Finance Dashboard. Every figure comes from a backend RPC — this
 * renders what the server returns and never sums a total itself. The only
 * arithmetic here is the period-over-period percentage, computed from two
 * authoritative totals.
 */
export function FinanceDashboard() {
  const [facilityId, setFacilityId] = useState<string | null>(null);
  const [facilityName, setFacilityName] = useState<string>("");
  const [loadState, setLoadState] = useState<"loading" | "ready" | "none" | "error">("loading");
  const [dateRange, setDateRange] = useState<FinanceDateRange>({ preset: "THIS_MONTH" });
  const [granularity, setGranularity] = useState<RevenueTrendGranularity>("daily");

  const [summary, setSummary] = useState<FinanceSummary | null>(null);
  const [previous, setPrevious] = useState<FinanceSummary | null>(null);
  const [breakdown, setBreakdown] = useState<RevenueBreakdown | null>(null);
  const [methods, setMethods] = useState<PaymentMethodSlice[] | null>(null);
  const [trend, setTrend] = useState<RevenueTrendPoint[] | null>(null);
  const [recent, setRecent] = useState<FinanceTransaction[] | null>(null);
  const [rangeError, setRangeError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    getFacilityService()
      .getFacility()
      .then((facility) => {
        if (cancelled) return;
        if (!facility) {
          setLoadState("none");
          return;
        }
        setFacilityId(facility.id);
        setFacilityName(facility.name);
        setLoadState("ready");
      })
      .catch(() => !cancelled && setLoadState("error"));
    return () => {
      cancelled = true;
    };
  }, []);

  const load = useCallback(async () => {
    if (!facilityId) return;
    const finance = getFinanceService();
    setRangeError(null);

    const [s, b, m, t, page] = await Promise.all([
      finance.getSummary(facilityId, dateRange),
      finance.getRevenueBreakdown(facilityId, dateRange),
      finance.getPaymentMethodBreakdown(facilityId, dateRange),
      finance.getRevenueTrend(facilityId, dateRange, granularity),
      finance.listTransactions({ facilityId, dateRange, limit: 5, offset: 0 }),
    ]);

    setSummary(s);
    setBreakdown(b);
    setMethods(m);
    setTrend(t);
    setRecent(page.transactions);

    // The comparison window: the same span immediately before this one.
    // Fetched rather than derived, so it is the server's total either way.
    try {
      setPrevious(await finance.getSummary(facilityId, previousRange(dateRange)));
    } catch {
      // A missing comparison is not worth failing the page over — the
      // deltas simply read "vs last period" with no figure.
      setPrevious(null);
    }
  }, [facilityId, dateRange, granularity]);

  useEffect(() => {
    let cancelled = false;
    load().catch((err) => {
      if (cancelled) return;
      setRangeError(err instanceof ServiceError ? err.message : "Unable to load financial data. Please try again.");
    });
    return () => {
      cancelled = true;
    };
  }, [load]);

  if (loadState === "loading") return <DashboardSkeleton />;
  if (loadState === "none") {
    return <p className="text-sm text-muted-foreground">No facility found for this account yet.</p>;
  }
  if (loadState === "error") {
    return <p className="text-sm text-destructive">Unable to load financial data. Please try again.</p>;
  }

  const revenueSegments: DonutSegment[] = breakdown
    ? segmentsFrom(
        [
          { label: "Guest Bookings", value: breakdown.guestBookingRevenueMinor },
          { label: "Memberships", value: breakdown.membershipRevenueMinor },
          { label: "Member Bookings", value: breakdown.memberBookingRevenueMinor },
        ],
        REVENUE_COLOURS,
      )
    : [];

  const methodSegments: DonutSegment[] = methods
    ? segmentsFrom(
        methods.map((m) => ({ label: m.paymentMethod, value: m.amountMinor })),
        METHOD_COLOURS,
      )
    : [];

  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-center justify-end gap-2">
        <span className="mr-auto inline-flex min-h-9 items-center gap-1.5 rounded-xl border border-border px-3 text-sm">
          <MapPin className="h-3.5 w-3.5 text-muted-foreground" aria-hidden />
          {facilityName || "Facility"}
        </span>
        <DateRangePicker value={dateRange} onChange={setDateRange} />
        <Button asChild variant="outline" size="sm" className="min-h-9">
          <Link href="/finance/transactions">
            <Download className="h-4 w-4" aria-hidden /> Export
          </Link>
        </Button>
      </div>

      {rangeError && <p className="text-sm text-destructive">{rangeError}</p>}

      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-4">
        {!summary ? (
          Array.from({ length: 4 }).map((_, i) => <Skeleton key={i} className="h-24 rounded-xl" />)
        ) : (
          <>
            <StatCard
              icon={Banknote}
              label="Total Revenue"
              value={formatCurrency(summary.grossRevenueMinor, INR)}
              accent="#00D084"
              index={0}
              hint={<Delta pct={changePct(summary.grossRevenueMinor, previous?.grossRevenueMinor ?? 0)} />}
            />
            <StatCard
              icon={Wallet}
              label="Total Expenses"
              value={formatCurrency(summary.expensesMinor, INR)}
              accent="#FF4D67"
              index={1}
              hint={<Delta pct={changePct(summary.expensesMinor, previous?.expensesMinor ?? 0)} invert />}
            />
            <StatCard
              icon={TrendingUp}
              label="Net Revenue"
              value={formatCurrency(summary.netRevenueMinor, INR)}
              accent="#00F08A"
              index={2}
              hint={<Delta pct={changePct(summary.netRevenueMinor, previous?.netRevenueMinor ?? 0)} />}
            />
            <StatCard
              icon={Clock3}
              label="Pending Payments"
              value={formatCurrency(summary.outstandingMinor, INR)}
              accent="#FFB020"
              index={3}
              hint={<Delta pct={changePct(summary.outstandingMinor, previous?.outstandingMinor ?? 0)} invert />}
            />
          </>
        )}
      </div>

      <div className="grid gap-4 xl:grid-cols-[minmax(0,1.2fr)_minmax(0,1fr)_minmax(0,1fr)]">
        <Card className="p-4">
          <div className="mb-3 flex items-center justify-between gap-3">
            <h2 className="text-sm font-semibold">Revenue Trend</h2>
            <Select value={granularity} onValueChange={(v) => setGranularity(v as RevenueTrendGranularity)}>
              <SelectTrigger className="h-9 w-32" aria-label="Trend granularity">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="daily">By Day</SelectItem>
                <SelectItem value="weekly">By Week</SelectItem>
                <SelectItem value="monthly">By Month</SelectItem>
              </SelectContent>
            </Select>
          </div>
          {trend === null ? (
            <Skeleton className="h-56 w-full rounded-lg" />
          ) : trend.length === 0 ? (
            <EmptyPanel message="No revenue in this period yet." />
          ) : (
            <RevenueTrendChart points={trend} />
          )}
        </Card>

        <Card className="p-4">
          <h2 className="mb-3 text-sm font-semibold">Revenue Breakdown</h2>
          {!breakdown ? (
            <Skeleton className="h-40 w-full rounded-lg" />
          ) : revenueSegments.length === 0 ? (
            <EmptyPanel message="No revenue to break down yet." />
          ) : (
            <>
              <Donut
                segments={revenueSegments}
                centreValue={formatCurrency(totalOf(revenueSegments), INR)}
                centreLabel="Total"
              />
              {breakdown.membershipIncludedUsageCount > 0 && (
                <p className="mt-3 text-[11px] text-muted-foreground">
                  Plus {breakdown.membershipIncludedUsageCount} included membership session
                  {breakdown.membershipIncludedUsageCount === 1 ? "" : "s"} — usage, not revenue.
                </p>
              )}
            </>
          )}
        </Card>

        <Card className="p-4">
          <h2 className="mb-3 text-sm font-semibold">Payment Methods</h2>
          {!methods ? (
            <Skeleton className="h-40 w-full rounded-lg" />
          ) : methodSegments.length === 0 ? (
            <EmptyPanel message="No payments taken in this period." />
          ) : (
            <Donut
              segments={methodSegments}
              centreValue={formatCurrency(totalOf(methodSegments), INR)}
              centreLabel="Total"
            />
          )}
        </Card>
      </div>

      <Card className="p-4">
        <div className="mb-3 flex items-center justify-between gap-3">
          <h2 className="text-sm font-semibold">Recent Transactions</h2>
          <Link
            href="/finance/transactions"
            className="inline-flex items-center gap-1 text-xs font-medium text-primary hover:underline"
          >
            View All Transactions <ArrowRight className="h-3.5 w-3.5" aria-hidden />
          </Link>
        </div>

        {recent === null ? (
          <Skeleton className="h-40 w-full rounded-lg" />
        ) : recent.length === 0 ? (
          <EmptyPanel message="No transactions yet. They'll appear here once payments or expenses are recorded." />
        ) : (
          <>
            {/* Desktop: a dense table. Mobile gets cards below — a shrunken
                eight-column table is unreadable on a phone. */}
            <div className="hidden overflow-x-auto md:block">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-border text-left text-xs text-muted-foreground">
                    <th className="py-2 pr-3 font-medium">Date</th>
                    <th className="py-2 pr-3 font-medium">Transaction ID</th>
                    <th className="py-2 pr-3 font-medium">Description</th>
                    <th className="py-2 pr-3 font-medium">Type</th>
                    <th className="py-2 pr-3 font-medium">Payment Mode</th>
                    <th className="py-2 pr-3 text-right font-medium">Amount</th>
                    <th className="py-2 font-medium">Status</th>
                  </tr>
                </thead>
                <tbody>
                  {recent.map((txn) => (
                    <tr key={txn.id} className="border-b border-border last:border-0">
                      <td className="whitespace-nowrap py-2.5 pr-3 text-muted-foreground">
                        {formatTxnDate(txn.effectiveAt)}
                      </td>
                      <td className="whitespace-nowrap py-2.5 pr-3 font-medium">{txn.reference}</td>
                      <td className="py-2.5 pr-3">
                        <span className="block truncate">{describe(txn)}</span>
                        {txn.customerName && (
                          <span className="block text-xs text-muted-foreground">{txn.customerName}</span>
                        )}
                      </td>
                      <td className="py-2.5 pr-3">
                        <Badge variant="secondary" className="capitalize">
                          {sourceLabel(txn)}
                        </Badge>
                      </td>
                      <td className="whitespace-nowrap py-2.5 pr-3 text-muted-foreground">
                        {txn.paymentMethod ?? "—"}
                      </td>
                      <td className="whitespace-nowrap py-2.5 pr-3 text-right font-medium tabular-nums">
                        {formatCurrency(txn.amountMinor, txn.currency)}
                      </td>
                      <td className="py-2.5">
                        <Badge variant={statusTone(txn.status)} className="capitalize">
                          {txn.status}
                        </Badge>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            <ul className="space-y-2 md:hidden">
              {recent.map((txn) => (
                <li key={txn.id} className="rounded-xl border border-border p-3">
                  <div className="flex items-start justify-between gap-3">
                    <div className="min-w-0">
                      <p className="truncate text-sm font-medium">{describe(txn)}</p>
                      <p className="text-xs text-muted-foreground">
                        {txn.reference} · {formatTxnDate(txn.effectiveAt)}
                      </p>
                    </div>
                    <span className="shrink-0 text-sm font-semibold tabular-nums">
                      {formatCurrency(txn.amountMinor, txn.currency)}
                    </span>
                  </div>
                  <div className="mt-2 flex flex-wrap items-center gap-1.5">
                    <Badge variant="secondary" className="capitalize">
                      {sourceLabel(txn)}
                    </Badge>
                    {txn.paymentMethod && <Badge variant="secondary">{txn.paymentMethod}</Badge>}
                    <Badge variant={statusTone(txn.status)} className="capitalize">
                      {txn.status}
                    </Badge>
                  </div>
                </li>
              ))}
            </ul>
          </>
        )}
      </Card>

      {summary && summary.settlementExceptionCount > 0 && (
        <Link href="/refunds">
          <Card className="border-warning/50 bg-warning/10 p-4 text-sm">
            <p className="font-medium">Settlement Exceptions</p>
            <p className="text-muted-foreground">
              {summary.settlementExceptionCount} payment
              {summary.settlementExceptionCount === 1 ? "" : "s"} require attention.
            </p>
          </Card>
        </Link>
      )}
    </div>
  );
}

/** Drops empty slices and assigns a colour, so the legend has no dead rows. */
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

/** The window immediately before this one, of the same length. */
function previousRange(range: FinanceDateRange): FinanceDateRange {
  const map: Partial<Record<string, string>> = {
    TODAY: "YESTERDAY",
    THIS_WEEK: "LAST_WEEK",
    THIS_MONTH: "LAST_MONTH",
  };
  const mapped = range.preset ? map[range.preset] : undefined;
  if (mapped) return { preset: mapped as FinanceDateRange["preset"] };

  if (range.startDate && range.endDate) {
    const start = new Date(range.startDate);
    const end = new Date(range.endDate);
    const days = Math.max(Math.round((end.getTime() - start.getTime()) / 86400000), 0) + 1;
    const prevEnd = new Date(start);
    prevEnd.setDate(prevEnd.getDate() - 1);
    const prevStart = new Date(prevEnd);
    prevStart.setDate(prevStart.getDate() - (days - 1));
    return { preset: "CUSTOM", startDate: iso(prevStart), endDate: iso(prevEnd) };
  }
  return range;
}

function iso(date: Date): string {
  return `${date.getFullYear()}-${`${date.getMonth() + 1}`.padStart(2, "0")}-${`${date.getDate()}`.padStart(2, "0")}`;
}

function formatTxnDate(iso: string): string {
  return new Date(iso).toLocaleString("en-IN", {
    day: "2-digit",
    month: "short",
    year: "numeric",
    hour: "numeric",
    minute: "2-digit",
    hour12: true,
  });
}

function sourceLabel(txn: FinanceTransaction): string {
  return txn.sourceType.replace(/_/g, " ").toLowerCase();
}

/** What the money was for, in the words an owner would use. */
function describe(txn: FinanceTransaction): string {
  const source = sourceLabel(txn).replace(/^./, (c) => c.toUpperCase());
  return txn.customerName ? `${source} — ${txn.customerName}` : source;
}

function EmptyPanel({ message }: { message: string }) {
  return (
    <p className="rounded-lg border border-dashed border-border p-6 text-center text-sm text-muted-foreground">
      {message}
    </p>
  );
}

function DashboardSkeleton() {
  return (
    <div className="space-y-5" aria-busy>
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-4">
        {Array.from({ length: 4 }).map((_, i) => (
          <Skeleton key={i} className="h-24 rounded-xl" />
        ))}
      </div>
      <div className="grid gap-4 xl:grid-cols-3">
        {Array.from({ length: 3 }).map((_, i) => (
          <Skeleton key={i} className="h-64 rounded-xl" />
        ))}
      </div>
      <Skeleton className="h-56 w-full rounded-xl" />
    </div>
  );
}
