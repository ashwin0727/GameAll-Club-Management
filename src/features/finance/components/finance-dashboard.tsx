"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { Badge } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { formatCurrency } from "@/features/pricing/money";
import { getFacilityService } from "@/services/facility";
import { getFinanceService } from "@/services/finance";
import type { FinanceDateRange, FinanceSummary, RevenueBreakdown, RevenueTrendPoint, FinanceTransaction } from "@/features/finance/types";
import { DateRangePicker } from "@/features/finance/components/date-range-picker";
import { RevenueTrendChart } from "@/features/finance/components/revenue-trend-chart";
import { ServiceError } from "@/services/shared/service-error";

function SummaryCard({ label, value }: { label: string; value: string }) {
  return (
    <Card className="space-y-1.5 p-4 sm:p-5">
      <p className="text-xs font-medium text-muted-foreground">{label}</p>
      <p className="text-2xl font-semibold text-foreground">{value}</p>
    </Card>
  );
}

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

/**
 * The Finance Dashboard (spec §"Finance Dashboard — Web"). Every number on
 * this page comes from a backend RPC call (0024_finance.sql) — this
 * component only ever renders what the server returns, it never sums or
 * recomputes a total itself (spec §"Core Finance Principle").
 */
export function FinanceDashboard() {
  const [facilityId, setFacilityId] = useState<string | null>(null);
  const [loadState, setLoadState] = useState<"loading" | "ready" | "none" | "error">("loading");
  const [dateRange, setDateRange] = useState<FinanceDateRange>({ preset: "THIS_MONTH" });

  const [summary, setSummary] = useState<FinanceSummary | null>(null);
  const [todaySummary, setTodaySummary] = useState<FinanceSummary | null>(null);
  const [weekSummary, setWeekSummary] = useState<FinanceSummary | null>(null);
  const [monthSummary, setMonthSummary] = useState<FinanceSummary | null>(null);
  const [breakdown, setBreakdown] = useState<RevenueBreakdown | null>(null);
  const [trend, setTrend] = useState<RevenueTrendPoint[] | null>(null);
  const [recentTransactions, setRecentTransactions] = useState<FinanceTransaction[]>([]);
  const [rangeError, setRangeError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const facility = await getFacilityService().getFacility();
      if (cancelled) return;
      if (!facility) {
        setLoadState("none");
        return;
      }
      setFacilityId(facility.id);
      const finance = getFinanceService();
      const [today, week, month] = await Promise.all([
        finance.getSummary(facility.id, { preset: "TODAY" }),
        finance.getSummary(facility.id, { preset: "THIS_WEEK" }),
        finance.getSummary(facility.id, { preset: "THIS_MONTH" }),
      ]);
      if (cancelled) return;
      setTodaySummary(today);
      setWeekSummary(week);
      setMonthSummary(month);
      setLoadState("ready");
    })().catch(() => setLoadState("error"));
    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    if (!facilityId) return;
    if (dateRange.preset === "CUSTOM" && (!dateRange.startDate || !dateRange.endDate)) return;
    let cancelled = false;
    setRangeError(null);
    const finance = getFinanceService();
    (async () => {
      const [s, b, t, page] = await Promise.all([
        finance.getSummary(facilityId, dateRange),
        finance.getRevenueBreakdown(facilityId, dateRange),
        finance.getRevenueTrend(facilityId, dateRange, "daily"),
        finance.listTransactions({ facilityId, dateRange, limit: 5, offset: 0 }),
      ]);
      if (cancelled) return;
      setSummary(s);
      setBreakdown(b);
      setTrend(t);
      setRecentTransactions(page.transactions);
    })().catch((err) => {
      if (cancelled) return;
      setRangeError(err instanceof ServiceError ? err.message : "Unable to load financial data. Please try again.");
    });
    return () => {
      cancelled = true;
    };
  }, [facilityId, dateRange]);

  if (loadState === "loading") {
    return (
      <div className="space-y-4">
        <Skeleton className="h-24 w-full rounded-lg" />
        <Skeleton className="h-64 w-full rounded-lg" />
      </div>
    );
  }
  if (loadState === "none") return <p className="text-sm text-muted-foreground">No facility found for this account yet.</p>;
  if (loadState === "error") return <p className="text-sm text-destructive">Unable to load financial data. Please try again.</p>;

  return (
    <div className="space-y-6">
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
        <SummaryCard label="Today" value={todaySummary ? formatCurrency(todaySummary.netRevenueMinor, "INR") : "—"} />
        <SummaryCard label="This Week" value={weekSummary ? formatCurrency(weekSummary.netRevenueMinor, "INR") : "—"} />
        <SummaryCard label="This Month" value={monthSummary ? formatCurrency(monthSummary.netRevenueMinor, "INR") : "—"} />
      </div>

      <div className="flex flex-wrap items-center justify-between gap-3">
        <h2 className="text-sm font-medium">Revenue Summary</h2>
        <DateRangePicker value={dateRange} onChange={setDateRange} />
      </div>

      {rangeError && <p className="text-sm text-destructive">{rangeError}</p>}

      {!summary ? (
        <Skeleton className="h-24 w-full rounded-lg" />
      ) : (
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
          <SummaryCard label="Gross Revenue" value={formatCurrency(summary.grossRevenueMinor, "INR")} />
          <SummaryCard label="Refunds" value={formatCurrency(summary.refundsMinor, "INR")} />
          <SummaryCard label="Net Revenue" value={formatCurrency(summary.netRevenueMinor, "INR")} />
        </div>
      )}

      {summary && (
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
          <SummaryCard label="Transactions" value={String(summary.transactionCount)} />
          <SummaryCard label="Successful" value={String(summary.successfulPaymentCount)} />
          <SummaryCard label="Failed" value={String(summary.failedPaymentCount)} />
          <SummaryCard label="Pending" value={String(summary.pendingPaymentCount)} />
        </div>
      )}

      <Card className="p-4 sm:p-5">
        <h2 className="mb-3 text-sm font-medium">Revenue Trend</h2>
        {trend === null ? <Skeleton className="h-64 w-full rounded-lg" /> : <RevenueTrendChart points={trend} />}
      </Card>

      <Card className="p-4 sm:p-5">
        <h2 className="mb-3 text-sm font-medium">Revenue Breakdown</h2>
        {!breakdown ? (
          <Skeleton className="h-32 w-full rounded-lg" />
        ) : (
          <div className="space-y-2 text-sm">
            {[
              { label: "Membership", value: breakdown.membershipRevenueMinor },
              { label: "Member Booking", value: breakdown.memberBookingRevenueMinor },
              { label: "Guest Booking", value: breakdown.guestBookingRevenueMinor },
              { label: "Refunds", value: breakdown.refundsMinor },
            ].map((row) => (
              <div key={row.label} className="flex items-center justify-between border-b border-border py-1.5 last:border-0">
                <span className="text-muted-foreground">{row.label}</span>
                <span className="font-medium">{formatCurrency(row.value, "INR")}</span>
              </div>
            ))}
            {breakdown.membershipIncludedUsageCount > 0 && (
              <p className="pt-1 text-xs text-muted-foreground">
                Plus {breakdown.membershipIncludedUsageCount} included membership session{breakdown.membershipIncludedUsageCount === 1 ? "" : "s"} (not counted as revenue).
              </p>
            )}
          </div>
        )}
      </Card>

      <Card className="p-4 sm:p-5">
        <div className="mb-3 flex items-center justify-between">
          <h2 className="text-sm font-medium">Recent Transactions</h2>
          <Link href="/finance/transactions" className="text-xs font-medium text-primary hover:underline">
            View all
          </Link>
        </div>
        {recentTransactions.length === 0 ? (
          <p className="text-sm text-muted-foreground">No transactions found for this period.</p>
        ) : (
          <div className="space-y-2">
            {recentTransactions.map((txn) => (
              <div key={txn.id} className="flex items-center justify-between rounded-md border border-border p-2.5 text-sm">
                <div>
                  <p className="font-medium">
                    {txn.reference} · {txn.sourceType.replace("_", " ")}
                  </p>
                  <p className="text-xs text-muted-foreground">{txn.customerName ?? "—"}</p>
                </div>
                <div className="flex items-center gap-2">
                  <span className="font-medium">{formatCurrency(txn.amountMinor, txn.currency)}</span>
                  <Badge variant={statusTone(txn.status)} className="capitalize">
                    {txn.status}
                  </Badge>
                </div>
              </div>
            ))}
          </div>
        )}
      </Card>

      {summary && summary.settlementExceptionCount > 0 && (
        <Link href="/refunds">
          <Card className="border-warning/50 bg-warning/10 p-4 text-sm sm:p-5">
            <p className="font-medium">Settlement Exceptions</p>
            <p className="text-muted-foreground">
              {summary.settlementExceptionCount} payment{summary.settlementExceptionCount === 1 ? "" : "s"} require attention.
            </p>
          </Card>
        </Link>
      )}
    </div>
  );
}