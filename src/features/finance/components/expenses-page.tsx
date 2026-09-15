"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { ChevronLeft, ChevronRight, Receipt, Search, SlidersHorizontal } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { cn } from "@/lib/utils";
import { formatCurrency, toMinorUnits } from "@/features/pricing/money";
import { useFacility } from "@/features/facility/hooks/use-facility";
import { getFinanceService } from "@/services/finance";
import { AddExpenseDialog } from "@/features/finance/components/add-expense-dialog";
import { MarkExpensePaidDialog } from "@/features/finance/components/mark-expense-paid-dialog";
import { DateRangePicker } from "@/features/finance/components/date-range-picker";
import { ServiceError } from "@/services/shared/service-error";
import type {
  ExpenseCategory,
  ExpensePaymentStatus,
  ExpenseRow,
  ExpenseSummary,
  FinanceDateRange,
} from "@/features/finance/types";

const PAGE_SIZE = 20;
const ALL = "ALL";

function paymentTone(status: ExpensePaymentStatus): "success" | "warning" | "secondary" {
  if (status === "PAID") return "success";
  if (status === "PARTIAL") return "warning";
  return "secondary";
}

function paymentLabel(status: ExpensePaymentStatus): string {
  return status === "PARTIAL" ? "Partial" : status === "PENDING" ? "Unpaid" : "Paid";
}

/**
 * What the facility has spent. The counterpart to Transactions — both read
 * the same ledger. An expense counts against Net Revenue the moment it is
 * recorded (accrual); its payment status only tracks what has been settled.
 */
export function ExpensesPage() {
  const { data: facility, isLoading: facilityLoading, isError: facilityQueryError } = useFacility();
  const facilityId = facility?.id ?? null;
  const [loadState, setLoadState] = useState<"loading" | "ready" | "none" | "error">("loading");
  const [dateRange, setDateRange] = useState<FinanceDateRange>({ preset: "THIS_MONTH" });
  const [page, setPage] = useState(0);

  const [categories, setCategories] = useState<ExpenseCategory[]>([]);
  const [methods, setMethods] = useState<string[]>([]);

  const [search, setSearch] = useState("");
  const [debounced, setDebounced] = useState("");
  const [categoryId, setCategoryId] = useState(ALL);
  const [paymentStatus, setPaymentStatus] = useState(ALL);
  const [paymentMethod, setPaymentMethod] = useState(ALL);
  const [minAmount, setMinAmount] = useState("");
  const [maxAmount, setMaxAmount] = useState("");
  const [showFilters, setShowFilters] = useState(false);

  const [summary, setSummary] = useState<ExpenseSummary | null>(null);
  const [expenses, setExpenses] = useState<ExpenseRow[] | null>(null);
  const [totalCount, setTotalCount] = useState(0);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const t = setTimeout(() => setDebounced(search), 300);
    return () => clearTimeout(t);
  }, [search]);

  useEffect(() => {
    if (facilityLoading) return;
    if (facilityQueryError) {
      setLoadState("error");
      return;
    }
    if (!facility) {
      setLoadState("none");
      return;
    }
    let cancelled = false;
    (async () => {
      try {
        setLoadState("ready");
        const [cats, mths] = await Promise.all([
          getFinanceService().listExpenseCategories(facility.id),
          getFinanceService().listPaymentMethods(facility.id),
        ]);
        if (cancelled) return;
        setCategories(cats);
        setMethods(mths);
      } catch {
        if (!cancelled) setLoadState("error");
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [facility, facilityLoading, facilityQueryError]);

  useEffect(() => setPage(0), [dateRange, debounced, categoryId, paymentStatus, paymentMethod, minAmount, maxAmount]);

  const load = useCallback(async () => {
    if (!facilityId) return;
    setError(null);
    const finance = getFinanceService();
    const [list, totals] = await Promise.all([
      finance.listExpenses({
        facilityId,
        dateRange,
        filters: {
          search: debounced,
          categoryId: categoryId === ALL ? null : categoryId,
          paymentStatus: paymentStatus === ALL ? null : (paymentStatus as ExpensePaymentStatus),
          paymentMethod: paymentMethod === ALL ? null : paymentMethod,
          minMinor: minAmount ? toMinorUnits(minAmount, "INR") : null,
          maxMinor: maxAmount ? toMinorUnits(maxAmount, "INR") : null,
        },
        limit: PAGE_SIZE,
        offset: page * PAGE_SIZE,
      }),
      finance.getExpenseSummary(facilityId, dateRange),
    ]);
    setExpenses(list.expenses);
    setTotalCount(list.totalCount);
    setSummary(totals);
  }, [facilityId, dateRange, debounced, categoryId, paymentStatus, paymentMethod, minAmount, maxAmount, page]);

  useEffect(() => {
    let cancelled = false;
    setExpenses(null);
    load().catch((err) => {
      if (cancelled) return;
      setError(err instanceof ServiceError ? err.message : "Unable to load expenses.");
    });
    return () => {
      cancelled = true;
    };
  }, [load]);

  const totalPages = Math.max(1, Math.ceil(totalCount / PAGE_SIZE));
  const firstRow = totalCount === 0 ? 0 : page * PAGE_SIZE + 1;
  const lastRow = Math.min((page + 1) * PAGE_SIZE, totalCount);
  const hasFilters =
    debounced.trim() !== "" ||
    categoryId !== ALL ||
    paymentStatus !== ALL ||
    paymentMethod !== ALL ||
    minAmount !== "" ||
    maxAmount !== "";

  const kpis = useMemo(
    () =>
      summary
        ? [
            { label: "Total (period)", value: summary.totalMinor, accent: "text-foreground" },
            { label: "This Month", value: summary.thisMonthMinor, accent: "text-foreground" },
            { label: "This Week", value: summary.thisWeekMinor, accent: "text-foreground" },
            {
              label: `Unpaid${summary.pendingCount ? ` (${summary.pendingCount})` : ""}`,
              value: summary.pendingMinor,
              accent: "text-warning",
            },
            { label: "Maintenance", value: summary.maintenanceMinor, accent: "text-foreground" },
            { label: "Other Operating", value: summary.otherMinor, accent: "text-foreground" },
          ]
        : [],
    [summary],
  );

  if (loadState === "loading") return <Skeleton className="h-96 w-full rounded-xl" />;
  if (loadState === "none") return <p className="text-sm text-muted-foreground">No facility found for this account yet.</p>;
  if (loadState === "error") return <p className="text-sm text-destructive">Unable to load expenses.</p>;

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-xl font-semibold">Expenses</h1>
          <p className="text-sm text-muted-foreground">Track facility expenses and operating costs.</p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <DateRangePicker value={dateRange} onChange={setDateRange} />
          <AddExpenseDialog onCreated={() => void load()} />
        </div>
      </div>

      <div className="grid grid-cols-2 gap-3 md:grid-cols-3 lg:grid-cols-6">
        {summary === null
          ? Array.from({ length: 6 }).map((_, i) => <Skeleton key={i} className="h-20 rounded-xl" />)
          : kpis.map((kpi) => (
              <Card key={kpi.label} className="p-3">
                <p className="text-[11px] text-muted-foreground">{kpi.label}</p>
                <p className={cn("mt-1 text-lg font-semibold tabular-nums", kpi.accent)}>
                  {formatCurrency(kpi.value, "INR")}
                </p>
              </Card>
            ))}
      </div>

      <Card className="p-4">
        <div className={cn("flex flex-wrap items-start gap-3", !showFilters && "hidden lg:flex")}>
          <FilterField label="Category" className="w-[11rem]">
            <FilterSelect
              value={categoryId}
              onChange={setCategoryId}
              options={[{ value: ALL, label: "All categories" }, ...categories.map((c) => ({ value: c.id, label: c.name }))]}
            />
          </FilterField>
          <FilterField label="Payment status" className="w-[10rem]">
            <FilterSelect
              value={paymentStatus}
              onChange={setPaymentStatus}
              options={[
                { value: ALL, label: "Any status" },
                { value: "PAID", label: "Paid" },
                { value: "PARTIAL", label: "Partial" },
                { value: "PENDING", label: "Unpaid" },
              ]}
            />
          </FilterField>
          <FilterField label="Method" className="w-[10rem]">
            <FilterSelect
              value={paymentMethod}
              onChange={setPaymentMethod}
              options={[{ value: ALL, label: "Any method" }, ...methods.map((m) => ({ value: m, label: m }))]}
            />
          </FilterField>
          <FilterField label="Min ₹" className="w-[7rem]">
            <Input inputMode="decimal" value={minAmount} onChange={(e) => setMinAmount(e.target.value)} placeholder="0" />
          </FilterField>
          <FilterField label="Max ₹" className="w-[7rem]">
            <Input inputMode="decimal" value={maxAmount} onChange={(e) => setMaxAmount(e.target.value)} placeholder="—" />
          </FilterField>
          <div className="ml-auto space-y-1.5">
            <span className="block select-none text-xs text-transparent" aria-hidden>
              Reset
            </span>
            <Button
              type="button"
              variant="outline"
              size="sm"
              disabled={!hasFilters}
              onClick={() => {
                setSearch("");
                setCategoryId(ALL);
                setPaymentStatus(ALL);
                setPaymentMethod(ALL);
                setMinAmount("");
                setMaxAmount("");
              }}
            >
              <SlidersHorizontal className="h-3.5 w-3.5" aria-hidden /> Reset
            </Button>
          </div>
        </div>

        <Button
          type="button"
          variant="outline"
          className="min-h-11 w-full lg:hidden"
          onClick={() => setShowFilters((v) => !v)}
          aria-expanded={showFilters}
        >
          <SlidersHorizontal className="h-4 w-4" aria-hidden /> {showFilters ? "Hide filters" : "Filters"}
        </Button>

        <div className="relative mt-3">
          <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" aria-hidden />
          <Input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search vendor, reference or notes…"
            aria-label="Search expenses"
            className="h-11 pl-9"
          />
        </div>
      </Card>

      <Card className="p-0">
        {error ? (
          <div className="p-10 text-center">
            <p className="text-sm font-semibold text-destructive">Unable to load expenses</p>
            <p className="mt-1 text-sm text-muted-foreground">{error}</p>
            <Button type="button" variant="outline" className="mt-4" onClick={() => void load()}>
              Try again
            </Button>
          </div>
        ) : expenses === null ? (
          <div className="space-y-2 p-4">
            {Array.from({ length: 6 }).map((_, i) => (
              <Skeleton key={i} className="h-12 w-full rounded-lg" />
            ))}
          </div>
        ) : expenses.length === 0 ? (
          <div className="p-10 text-center">
            <span className="mx-auto flex h-12 w-12 items-center justify-center rounded-full bg-muted">
              <Receipt className="h-6 w-6 text-muted-foreground" aria-hidden />
            </span>
            <p className="mt-3 text-sm font-semibold">No expenses recorded for this period</p>
            <p className="mt-1 text-sm text-muted-foreground">
              Anything the facility spends in the selected range will appear here.
            </p>
          </div>
        ) : (
          <>
            <div className="hidden overflow-x-auto lg:block">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-border text-left text-xs text-muted-foreground">
                    <th className="px-4 py-3 font-medium">Date</th>
                    <th className="px-4 py-3 font-medium">Category</th>
                    <th className="px-4 py-3 font-medium">Vendor / Payee</th>
                    <th className="px-4 py-3 font-medium">Method</th>
                    <th className="px-4 py-3 font-medium">Payment</th>
                    <th className="px-4 py-3 text-right font-medium">Amount</th>
                    <th className="px-4 py-3" />
                  </tr>
                </thead>
                <tbody>
                  {expenses.map((e) => (
                    <tr
                      key={e.id}
                      className={cn("border-b border-border last:border-0", e.status === "VOID" && "opacity-50")}
                    >
                      <td className="whitespace-nowrap px-4 py-3 text-muted-foreground">{formatDate(e.spentOn)}</td>
                      <td className="px-4 py-3">
                        <span className="inline-block rounded-md bg-[#8B5CF6]/15 px-2 py-0.5 text-xs font-medium text-[#8B5CF6]">
                          {e.categoryName}
                        </span>
                      </td>
                      <td className="px-4 py-3">
                        <Link href={`/finance/expenses/${e.id}`} className="font-medium hover:underline">
                          {e.vendor ?? e.categoryName}
                        </Link>
                        {e.reference && <span className="block text-xs text-muted-foreground">{e.reference}</span>}
                      </td>
                      <td className="whitespace-nowrap px-4 py-3 text-muted-foreground">{e.paymentMethod ?? "—"}</td>
                      <td className="px-4 py-3">
                        {e.status === "VOID" ? (
                          <Badge variant="secondary">Void</Badge>
                        ) : (
                          <Badge variant={paymentTone(e.paymentStatus)}>{paymentLabel(e.paymentStatus)}</Badge>
                        )}
                      </td>
                      <td className="whitespace-nowrap px-4 py-3 text-right font-medium tabular-nums">
                        {formatCurrency(e.amountMinor, e.currency)}
                        {e.paymentStatus === "PARTIAL" && (
                          <span className="block text-xs font-normal text-muted-foreground">
                            {formatCurrency(e.amountMinor - e.amountPaidMinor, e.currency)} due
                          </span>
                        )}
                      </td>
                      <td className="px-4 py-3 text-right">
                        <div className="flex justify-end gap-1.5">
                          {e.status !== "VOID" && e.paymentStatus !== "PAID" && (
                            <MarkExpensePaidDialog expense={e} onDone={() => void load()} />
                          )}
                          <Button asChild size="sm" variant="outline">
                            <Link href={`/finance/expenses/${e.id}`}>View</Link>
                          </Button>
                        </div>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            <ul className="divide-y divide-border lg:hidden">
              {expenses.map((e) => (
                <li key={e.id} className={cn("p-3", e.status === "VOID" && "opacity-50")}>
                  <div className="flex items-start justify-between gap-3">
                    <div className="min-w-0">
                      <Link href={`/finance/expenses/${e.id}`} className="truncate font-medium hover:underline">
                        {e.vendor ?? e.categoryName}
                      </Link>
                      <p className="text-xs text-muted-foreground">
                        {e.categoryName} · {formatDate(e.spentOn)}
                      </p>
                    </div>
                    <span className="shrink-0 font-semibold tabular-nums">
                      {formatCurrency(e.amountMinor, e.currency)}
                    </span>
                  </div>
                  <div className="mt-2 flex items-center gap-2">
                    {e.status === "VOID" ? (
                      <Badge variant="secondary">Void</Badge>
                    ) : (
                      <Badge variant={paymentTone(e.paymentStatus)}>{paymentLabel(e.paymentStatus)}</Badge>
                    )}
                    {e.status !== "VOID" && e.paymentStatus !== "PAID" && (
                      <MarkExpensePaidDialog expense={e} onDone={() => void load()} />
                    )}
                  </div>
                </li>
              ))}
            </ul>
          </>
        )}

        {totalCount > 0 && (
          <div className="flex flex-wrap items-center justify-between gap-3 border-t border-border p-3">
            <p className="text-xs text-muted-foreground">
              Showing {firstRow} to {lastRow} of {totalCount}
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

function FilterField({ label, className, children }: { label: string; className?: string; children: React.ReactNode }) {
  return (
    <div className={cn("space-y-1.5", className)}>
      <Label className="text-xs text-muted-foreground">{label}</Label>
      {children}
    </div>
  );
}

function FilterSelect({
  value,
  onChange,
  options,
}: {
  value: string;
  onChange: (v: string) => void;
  options: { value: string; label: string }[];
}) {
  return (
    <Select value={value} onValueChange={onChange}>
      <SelectTrigger className="w-full">
        <SelectValue />
      </SelectTrigger>
      <SelectContent>
        {options.map((o) => (
          <SelectItem key={o.value} value={o.value}>
            {o.label}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  );
}

function formatDate(iso: string): string {
  return new Date(iso).toLocaleDateString("en-IN", { day: "2-digit", month: "short", year: "numeric" });
}
