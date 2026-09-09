"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { Card } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { cn } from "@/lib/utils";
import { formatCurrency } from "@/features/pricing/money";
import { getFacilityService } from "@/services/facility";
import { getFinanceService } from "@/services/finance";
import { DateRangePicker } from "@/features/finance/components/date-range-picker";
import { PnlTrendChart } from "@/features/finance/components/pnl-trend-chart";
import { ServiceError } from "@/services/shared/service-error";
import type { FinanceDateRange, PnlTrendPoint, ProfitAndLoss, RevenueTrendGranularity } from "@/features/finance/types";

function granularityFor(preset: FinanceDateRange["preset"]): RevenueTrendGranularity {
  if (preset === "TODAY" || preset === "YESTERDAY" || preset === "THIS_WEEK" || preset === "LAST_WEEK") return "daily";
  if (preset === "THIS_YEAR") return "monthly";
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
  const [dateRange, setDateRange] = useState<FinanceDateRange>({ preset: "THIS_MONTH" });

  const [pnl, setPnl] = useState<ProfitAndLoss | null>(null);
  const [trend, setTrend] = useState<PnlTrendPoint[] | null>(null);
  const [error, setError] = useState<string | null>(null);

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
    if (!facilityId) return;
    setError(null);
    const finance = getFinanceService();
    const [p, t] = await Promise.all([
      finance.getProfitAndLoss(facilityId, dateRange),
      finance.getPnlTrend(facilityId, dateRange, granularityFor(dateRange.preset)),
    ]);
    setPnl(p);
    setTrend(t);
  }, [facilityId, dateRange]);

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
            { label: "Court booking revenue", value: pnl.bookingRevenueMinor },
            { label: "Membership revenue", value: pnl.membershipRevenueMinor },
            { label: "Guest booking revenue", value: pnl.guestBookingRevenueMinor },
            { label: "Other revenue", value: pnl.otherRevenueMinor },
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
        <DateRangePicker value={dateRange} onChange={setDateRange} />
      </div>

      {error && <p className="text-sm text-destructive">{error}</p>}

      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        {pnl === null
          ? Array.from({ length: 4 }).map((_, i) => <Skeleton key={i} className="h-20 rounded-xl" />)
          : [
              { label: "Total Revenue", value: formatCurrency(pnl.totalRevenueMinor, "INR"), accent: "text-foreground" },
              { label: "Total Expenses", value: formatCurrency(pnl.totalExpenseMinor, "INR"), accent: "text-foreground" },
              {
                label: "Net Profit",
                value: formatCurrency(pnl.netProfitMinor, "INR"),
                accent: pnl.netProfitMinor < 0 ? "text-destructive" : "text-primary",
              },
              { label: "Profit Margin", value: `${pnl.profitMarginPct}%`, accent: "text-foreground" },
            ].map((kpi) => (
              <Card key={kpi.label} className="p-3">
                <p className="text-[11px] text-muted-foreground">{kpi.label}</p>
                <p className={cn("mt-1 text-lg font-semibold tabular-nums", kpi.accent)}>{kpi.value}</p>
              </Card>
            ))}
      </div>

      {pnl === null ? (
        <Skeleton className="h-72 w-full rounded-xl" />
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
            <h2 className="mb-2 text-sm font-semibold">Revenue vs expenses</h2>
            {trend === null ? <Skeleton className="h-72 w-full" /> : <PnlTrendChart points={trend} />}
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
              <h2 className="text-sm font-semibold">Expenses by category</h2>
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
