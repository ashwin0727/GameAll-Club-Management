"use client";

import { useCallback, useEffect, useState } from "react";
import { ChevronLeft, ChevronRight, Receipt, Undo2 } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { cn } from "@/lib/utils";
import { formatCurrency } from "@/features/pricing/money";
import { getFacilityService } from "@/services/facility";
import { getFinanceService } from "@/services/finance";
import { AddExpenseDialog } from "@/features/finance/components/add-expense-dialog";
import { DateRangePicker } from "@/features/finance/components/date-range-picker";
import { ServiceError } from "@/services/shared/service-error";
import type { ExpenseRow, FinanceDateRange } from "@/features/finance/types";

const PAGE_SIZE = 20;

/**
 * What the facility has spent. The counterpart to Transactions, which is
 * mostly money coming in — both read the same ledger, and an expense
 * recorded here is what makes Net Revenue mean anything.
 */
export function ExpensesPage() {
  const [facilityId, setFacilityId] = useState<string | null>(null);
  const [loadState, setLoadState] = useState<"loading" | "ready" | "none" | "error">("loading");
  const [dateRange, setDateRange] = useState<FinanceDateRange>({ preset: "THIS_MONTH" });
  const [page, setPage] = useState(0);

  const [expenses, setExpenses] = useState<ExpenseRow[] | null>(null);
  const [totalCount, setTotalCount] = useState(0);
  const [error, setError] = useState<string | null>(null);
  const [voiding, setVoiding] = useState<string | null>(null);

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
        setLoadState("ready");
      })
      .catch(() => !cancelled && setLoadState("error"));
    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => setPage(0), [dateRange]);

  const load = useCallback(async () => {
    if (!facilityId) return;
    setError(null);
    const result = await getFinanceService().listExpenses({
      facilityId,
      dateRange,
      limit: PAGE_SIZE,
      offset: page * PAGE_SIZE,
    });
    setExpenses(result.expenses);
    setTotalCount(result.totalCount);
  }, [facilityId, dateRange, page]);

  useEffect(() => {
    let cancelled = false;
    setExpenses(null);
    load().catch((err) => {
      if (cancelled) return;
      setExpenses([]);
      setError(err instanceof ServiceError ? err.message : "Unable to load expenses.");
    });
    return () => {
      cancelled = true;
    };
  }, [load]);

  async function voidExpense(id: string) {
    setVoiding(id);
    setError(null);
    try {
      await getFinanceService().voidExpense(id);
      await load();
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Unable to void this expense.");
    } finally {
      setVoiding(null);
    }
  }

  const totalPages = Math.max(1, Math.ceil(totalCount / PAGE_SIZE));
  const recordedTotal = (expenses ?? [])
    .filter((e) => e.status === "RECORDED")
    .reduce((sum, e) => sum + e.amountMinor, 0);

  if (loadState === "loading") return <Skeleton className="h-96 w-full rounded-xl" />;
  if (loadState === "none") return <p className="text-sm text-muted-foreground">No facility found for this account yet.</p>;
  if (loadState === "error") return <p className="text-sm text-destructive">Unable to load expenses.</p>;

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-xl font-semibold">Expenses</h1>
          <p className="text-sm text-muted-foreground">What the facility has spent.</p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <DateRangePicker value={dateRange} onChange={setDateRange} />
          <AddExpenseDialog onCreated={() => void load()} />
        </div>
      </div>

      {expenses !== null && expenses.length > 0 && (
        <Card className="p-3">
          <p className="text-[11px] text-muted-foreground">Total on this page</p>
          <p className="mt-1 text-lg font-semibold tabular-nums">{formatCurrency(recordedTotal, "INR")}</p>
        </Card>
      )}

      <Card className="p-0">
        {error && <p className="p-4 text-sm text-destructive">{error}</p>}

        {expenses === null ? (
          <div className="space-y-2 p-4">
            {Array.from({ length: 5 }).map((_, i) => (
              <Skeleton key={i} className="h-12 w-full rounded-lg" />
            ))}
          </div>
        ) : expenses.length === 0 ? (
          <div className="p-10 text-center">
            <span className="mx-auto flex h-12 w-12 items-center justify-center rounded-full bg-muted">
              <Receipt className="h-6 w-6 text-muted-foreground" aria-hidden />
            </span>
            <p className="mt-3 text-sm font-semibold">No expenses recorded</p>
            <p className="mt-1 text-sm text-muted-foreground">
              Anything the facility spends in this period will appear here.
            </p>
          </div>
        ) : (
          <>
            <div className="hidden overflow-x-auto md:block">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-border text-left text-xs text-muted-foreground">
                    <th className="px-4 py-3 font-medium">Date</th>
                    <th className="px-4 py-3 font-medium">Category</th>
                    <th className="px-4 py-3 font-medium">Vendor</th>
                    <th className="px-4 py-3 font-medium">Reference</th>
                    <th className="px-4 py-3 font-medium">Mode</th>
                    <th className="px-4 py-3 text-right font-medium">Amount</th>
                    <th className="px-4 py-3" />
                  </tr>
                </thead>
                <tbody>
                  {expenses.map((e) => (
                    <tr key={e.id} className={cn("border-b border-border last:border-0", e.status === "VOID" && "opacity-50")}>
                      <td className="whitespace-nowrap px-4 py-3 text-muted-foreground">{formatDate(e.spentOn)}</td>
                      <td className="px-4 py-3">
                        <span className="inline-block rounded-md bg-[#8B5CF6]/15 px-2 py-0.5 text-xs font-medium text-[#8B5CF6]">
                          {e.categoryName}
                        </span>
                      </td>
                      <td className="px-4 py-3">{e.vendor ?? "—"}</td>
                      <td className="px-4 py-3 text-muted-foreground">{e.reference ?? "—"}</td>
                      <td className="whitespace-nowrap px-4 py-3 text-muted-foreground">{e.paymentMethod ?? "—"}</td>
                      <td className="whitespace-nowrap px-4 py-3 text-right font-medium tabular-nums">
                        {formatCurrency(e.amountMinor, e.currency)}
                      </td>
                      <td className="px-4 py-3 text-right">
                        {e.status === "VOID" ? (
                          <Badge variant="secondary">Void</Badge>
                        ) : (
                          <Button
                            type="button"
                            size="sm"
                            variant="outline"
                            disabled={voiding === e.id}
                            onClick={() => voidExpense(e.id)}
                          >
                            <Undo2 className="h-3.5 w-3.5" aria-hidden />
                            {voiding === e.id ? "Voiding…" : "Void"}
                          </Button>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            <ul className="divide-y divide-border md:hidden">
              {expenses.map((e) => (
                <li key={e.id} className={cn("p-3", e.status === "VOID" && "opacity-50")}>
                  <div className="flex items-start justify-between gap-3">
                    <div className="min-w-0">
                      <p className="truncate font-medium">{e.vendor ?? e.categoryName}</p>
                      <p className="text-xs text-muted-foreground">
                        {e.categoryName} · {formatDate(e.spentOn)}
                      </p>
                    </div>
                    <span className="shrink-0 font-semibold tabular-nums">
                      {formatCurrency(e.amountMinor, e.currency)}
                    </span>
                  </div>
                  {e.status === "VOID" ? (
                    <Badge variant="secondary" className="mt-2">
                      Void
                    </Badge>
                  ) : (
                    <Button
                      type="button"
                      size="sm"
                      variant="outline"
                      className="mt-2"
                      disabled={voiding === e.id}
                      onClick={() => voidExpense(e.id)}
                    >
                      <Undo2 className="h-3.5 w-3.5" aria-hidden /> Void
                    </Button>
                  )}
                </li>
              ))}
            </ul>
          </>
        )}

        {totalCount > 0 && (
          <div className="flex items-center justify-between gap-3 border-t border-border p-3">
            <p className="text-xs text-muted-foreground">
              {totalCount} expense{totalCount === 1 ? "" : "s"}
            </p>
            <div className="flex items-center gap-1">
              <Button
                type="button"
                variant="outline"
                size="sm"
                aria-label="Previous page"
                disabled={page === 0}
                onClick={() => setPage((p) => Math.max(0, p - 1))}
              >
                <ChevronLeft className="h-4 w-4" aria-hidden />
              </Button>
              <span className="px-2 text-xs text-muted-foreground">
                {page + 1} / {totalPages}
              </span>
              <Button
                type="button"
                variant="outline"
                size="sm"
                aria-label="Next page"
                disabled={page + 1 >= totalPages}
                onClick={() => setPage((p) => p + 1)}
              >
                <ChevronRight className="h-4 w-4" aria-hidden />
              </Button>
            </div>
          </div>
        )}
      </Card>
    </div>
  );
}

function formatDate(iso: string): string {
  return new Date(iso).toLocaleDateString("en-IN", { day: "2-digit", month: "short", year: "numeric" });
}
