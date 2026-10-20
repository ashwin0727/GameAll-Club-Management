"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { Card } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { ChartSkeleton } from "@/components/shared/chart-skeleton";
import { cn } from "@/lib/utils";
import { formatCurrency } from "@/features/pricing/money";
import { getFacilityService } from "@/services/facility";
import { getFinanceService } from "@/services/finance";
import { Banknote, Percent, TrendingUp, Wallet } from "lucide-react";
import { DayRangeFilter } from "@/features/finance/components/day-range-filter";
import { currentMonthRange, fillTrendBuckets, toFinanceDateRange, type DayRange } from "@/features/finance/day-range";
import { MembershipStatCard, MembershipStatCardSkeleton } from "@/features/memberships/components/membership-stat-card";
import { useSportIds } from "@/features/facility/hooks/use-sport-filter";
import { PnlTrendChart } from "@/features/finance/components/pnl-trend-chart";
import { ServiceError } from "@/services/shared/service-error";
import type { PnlTrendPoint, ProfitAndLoss, RevenueTrendGranularity } from "@/features/finance/types";

/** A day-by-day trend for a short span, weekly for a few months, monthly beyond that. */
function granularityFor(range: DayRange): RevenueTrendGranularity {
  const days = Math.round((new Date(range.to).getTime() - new Date(range.from).getTime()) / 86_400_000) + 1;
  if (days > 120) return "monthly";
  if (days > 45) return "weekly";
  return "daily";
}

/**
 * Owner-level Profit & Loss. Every figure is get_pnl / get_pnl_trend,
 * composed in the database from recognised payments, refunds and recorded
 * expenses — nothing is summed in the browser.
 */
export function ProfitLossPage() {
  const [facilityId, setFacilityId] = useState<string | null>(null);
  const [facilityName, setFacilityName] = useState("");
  const [loadState, setLoadState] = useState<"loading" | "ready" | "none" | "error">("loading");
  // The whole current month until the user picks other dates (and presses Apply).
  const [range, setRange] = useState<DayRange>(() => currentMonthRange());
  const dateRange = useMemo(() => toFinanceDateRange(range), [range]);

  const [pnl, setPnl] = useState<ProfitAndLoss | null>(null);
  const [trend, setTrend] = useState<PnlTrendPoint[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  // The top bar's sport selection (null = All Sports): every figure here follows it.
  const { sportIds, ready: sportsReady } = useSportIds(facilityId);

  useEffect(() => {
    let cancelled = false;
    getFacilityService()
      .getFacility()
      .then((facility) => {
        if (cancelled) return;
        if (!facility) return setLoadState("none");
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
    if (!facilityId || !sportsReady) return;
    setError(null);
    const finance = getFinanceService();
    const [p, t] = await Promise.all([
      finance.getProfitAndLoss(facilityId, dateRange, null, sportIds),
      finance.getPnlTrend(facilityId, dateRange, granularityFor(range), sportIds),
    ]);
    setPnl(p);
    // Quiet days are shown as zero, so the chart spans exactly the dates that were picked.
    setTrend(fillTrendBuckets(t, range, granularityFor(range), (date) => ({ date, revenueMinor: 0, expenseMinor: 0, netMinor: 0 })));
  }, [facilityId, sportsReady, sportIds, dateRange, range]);

  useEffect(() => {
    let cancelled = false;
    setPnl(null);
    setTrend(null);
    load().catch((err) => {
      if (cancelled) return;
      setError(err instanceof ServiceError ? err.message : "Unable to calculate the financial summary.");
    });
    return () => {
      cancelled = true;
    };
  }, [load]);

  const revenueRows = useMemo(
    () =>
      pnl
        ? [
            { label: "Court Booking Revenue", value: pnl.bookingRevenueMinor },
            { label: "Membership Revenue", value: pnl.membershipRevenueMinor },
            { label: "Guest Booking Revenue", value: pnl.guestBookingRevenueMinor },
            { label: "Other Revenue", value: pnl.otherRevenueMinor },
          ].filter((r) => r.value !== 0)
        : [],
    [pnl],
  );

  if (loadState === "loading") return <Skeleton className="h-96 w-full rounded-xl" />;
  if (loadState === "none") return <p className="text-sm text-muted-foreground">No facility found for this account yet.</p>;
  if (loadState === "error") return <p className="text-sm text-destructive">Unable to load the P&amp;L.</p>;

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-xl font-semibold">Profit &amp; Loss</h1>
          <p className="text-sm text-muted-foreground">
            Recognised revenue less recorded expenses{facilityName ? ` for ${facilityName}` : ""}.
          </p>
        </div>
        <DayRangeFilter value={range} onApply={setRange} />
      </div>

      {error && <p className="text-sm text-destructive">{error}</p>}

      {sportIds && (
        <p className="text-xs text-muted-foreground">
          Revenue is for the sports selected in the top bar. Expenses are not split by sport, so they cover the whole facility
          and the profit shown is revenue for these sports less all expenses.
        </p>
      )}

      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        {pnl === null ? (
          Array.from({ length: 4 }).map((_, i) => <MembershipStatCardSkeleton key={i} />)
        ) : (
          <>
            <MembershipStatCard
              icon={Banknote}
              iconBg="bg-success/15"
              iconColor="text-success"
              value={formatCurrency(pnl.totalRevenueMinor, "INR")}
              countTo={pnl.totalRevenueMinor}
              format={(v) => formatCurrency(Math.round(v), "INR")}
              label="Total Revenue"
              sub="Payments less refunds"
              index={0}
            />
            <MembershipStatCard
              icon={Wallet}
              iconBg="bg-destructive/15"
              iconColor="text-destructive"
              value={formatCurrency(pnl.totalExpenseMinor, "INR")}
              countTo={pnl.totalExpenseMinor}
              format={(v) => formatCurrency(Math.round(v), "INR")}
              label="Total Expenses"
              sub="Recorded expenses"
              index={1}
            />
            <MembershipStatCard
              icon={TrendingUp}
              iconBg="bg-blue-500/15"
              iconColor="text-blue-600 dark:text-blue-400"
              value={formatCurrency(pnl.netProfitMinor, "INR")}
              countTo={pnl.netProfitMinor}
              format={(v) => formatCurrency(Math.round(v), "INR")}
              label="Net Profit"
              sub={pnl.netProfitMinor < 0 ? "A loss in this period" : "Revenue less expenses"}
              subTone={pnl.netProfitMinor < 0 ? "text-destructive" : undefined}
              index={2}
            />
            <MembershipStatCard
              icon={Percent}
              iconBg="bg-purple-500/15"
              iconColor="text-purple-600 dark:text-purple-400"
              value={`${pnl.profitMarginPct}%`}
              countTo={Number(pnl.profitMarginPct)}
              format={(v) => `${Math.round(v * 10) / 10}%`}
              label="Profit Margin"
              sub="Net profit as a share of revenue"
              index={3}
            />
          </>
        )}
      </div>

      {pnl === null ? (
        <ChartSkeleton className="h-72" />
      ) : pnl.totalRevenueMinor === 0 && pnl.totalExpenseMinor === 0 ? (
        <Card className="p-10 text-center">
          <p className="text-sm font-semibold">Not enough financial data</p>
          <p className="mt-1 text-sm text-muted-foreground">
            There is no recognised revenue or recorded expense in this period.
          </p>
        </Card>
      ) : (
        <>
          <Card className="p-4">
            <h2 className="mb-2 text-sm font-semibold">Revenue vs Expenses</h2>
            {trend === null ? <ChartSkeleton className="h-72" /> : <PnlTrendChart points={trend} />}
          </Card>

          <div className="grid gap-4 lg:grid-cols-2">
            <Card className="space-y-2 p-4">
              <h2 className="text-sm font-semibold">Revenue</h2>
              <dl className="space-y-1.5 text-sm">
                {revenueRows.length === 0 ? (
                  <p className="text-muted-foreground">No revenue in this period.</p>
                ) : (
                  revenueRows.map((r) => <StatRow key={r.label} label={r.label} value={r.value} />)
                )}
                {pnl.refundsMinor > 0 && <StatRow label="Less: refunds" value={-pnl.refundsMinor} />}
                <div className="flex justify-between border-t border-border pt-1.5 font-semibold">
                  <dt>Total revenue</dt>
                  <dd className="tabular-nums">{formatCurrency(pnl.totalRevenueMinor, "INR")}</dd>
                </div>
              </dl>
            </Card>

            <Card className="space-y-2 p-4">
              <h2 className="text-sm font-semibold">Expenses by Category</h2>
              <dl className="space-y-1.5 text-sm">
                {pnl.expenseByCategory.length === 0 ? (
                  <p className="text-muted-foreground">No expenses recorded in this period.</p>
                ) : (
                  pnl.expenseByCategory.map((c) => <StatRow key={c.categoryId} label={c.category} value={c.amountMinor} />)
                )}
                <div className="flex justify-between border-t border-border pt-1.5 font-semibold">
                  <dt>Total expenses</dt>
                  <dd className="tabular-nums">{formatCurrency(pnl.totalExpenseMinor, "INR")}</dd>
                </div>
              </dl>
            </Card>
          </div>

          <Card className="flex items-center justify-between p-4">
            <span className="text-sm font-semibold">Net operating profit / loss</span>
            <span
              className={cn(
                "text-lg font-semibold tabular-nums",
                pnl.netProfitMinor < 0 ? "text-destructive" : "text-primary",
              )}
            >
              {formatCurrency(pnl.netProfitMinor, "INR")}
            </span>
          </Card>
        </>
      )}
    </div>
  );
}

function StatRow({ label, value }: { label: string; value: number }) {
  return (
    <div className="flex justify-between">
      <dt className="text-muted-foreground">{label}</dt>
      <dd className="tabular-nums">{formatCurrency(value, "INR")}</dd>
    </div>
  );
}
