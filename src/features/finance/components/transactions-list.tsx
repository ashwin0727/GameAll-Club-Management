"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { ChevronLeft, ChevronRight, Search, SlidersHorizontal } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { cn } from "@/lib/utils";
import { formatCurrency } from "@/features/pricing/money";
import { getFacilityService } from "@/services/facility";
import { getFinanceService } from "@/services/finance";
import type { FinanceDateRange, LedgerEntry, LedgerTxnType } from "@/features/finance/types";
import { AddExpenseDialog } from "@/features/finance/components/add-expense-dialog";
import { DateRangePicker } from "@/features/finance/components/date-range-picker";
import Link from "next/link";
import { ServiceError } from "@/services/shared/service-error";

const PAGE_SIZE = 10;
const ALL = "ALL";
const DEFAULT_PRESET = "THIS_MONTH" as const;

/** Every category the ledger can produce, for the filter. */
const CATEGORIES = [
  "Guest Booking Revenue",
  "Membership Revenue",
  "Court Booking Revenue",
  "Other Revenue",
  "Booking Refund",
];

function statusTone(status: string): "success" | "warning" | "destructive" | "secondary" {
  switch (status) {
    case "paid":
    case "processed":
      return "success";
    case "failed":
      return "destructive";
    case "refunded":
      return "secondary";
    default:
      return "warning";
  }
}

/**
 * Category chips are colour-coded by what kind of money they are, so a
 * scan down the column separates income from spending without reading.
 */
function categoryClass(entry: LedgerEntry): string {
  if (entry.txnType === "EXPENSE") return "bg-[#8B5CF6]/15 text-[#8B5CF6]";
  if (entry.txnType === "REFUND") return "bg-[#FF4D67]/15 text-[#FF4D67]";
  if (entry.category === "Membership Revenue") return "bg-[#8B5CF6]/15 text-[#8B5CF6]";
  return "bg-[#00D084]/15 text-[#00D084]";
}

function typeClass(type: LedgerTxnType): string {
  if (type === "EXPENSE") return "bg-[#FFB020]/15 text-[#FFB020]";
  if (type === "REFUND") return "bg-[#FF4D67]/15 text-[#FF4D67]";
  return "bg-[#00D084]/15 text-[#00D084]";
}

/**
 * Transactions — payments, refunds and expenses in one list. Filtering,
 * searching and paging all happen server-side; the browser never holds more
 * than the page it is showing.
 */
export function TransactionsList() {
  const [facilityId, setFacilityId] = useState<string | null>(null);
  const [loadState, setLoadState] = useState<"loading" | "ready" | "none" | "error">("loading");

  const [dateRange, setDateRange] = useState<FinanceDateRange>({ preset: DEFAULT_PRESET });
  const [txnType, setTxnType] = useState<string>(ALL);
  const [category, setCategory] = useState<string>(ALL);
  const [paymentMethod, setPaymentMethod] = useState<string>(ALL);
  const [search, setSearch] = useState("");
  const [debounced, setDebounced] = useState("");
  const [page, setPage] = useState(0);
  const [showFilters, setShowFilters] = useState(false);

  const [methods, setMethods] = useState<string[]>([]);
  const [entries, setEntries] = useState<LedgerEntry[] | null>(null);
  const [totalCount, setTotalCount] = useState(0);
  const [listError, setListError] = useState<string | null>(null);

  useEffect(() => {
    const timer = setTimeout(() => setDebounced(search), 300);
    return () => clearTimeout(timer);
  }, [search]);

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
        getFinanceService()
          .listPaymentMethods(facility.id)
          .then((m) => !cancelled && setMethods(m))
          .catch(() => undefined);
      })
      .catch(() => !cancelled && setLoadState("error"));
    return () => {
      cancelled = true;
    };
  }, []);

  // Any filter change returns to the first page — page 4 of the old result
  // is meaningless against a new one.
  useEffect(() => {
    setPage(0);
  }, [dateRange, txnType, category, paymentMethod, debounced]);

  const load = useCallback(async () => {
    if (!facilityId) return;
    setListError(null);
    const result = await getFinanceService().listLedger({
      facilityId,
      dateRange,
      filters: {
        txnType: txnType === ALL ? null : (txnType as LedgerTxnType),
        category: category === ALL ? null : category,
        paymentMethod: paymentMethod === ALL ? null : paymentMethod,
        search: debounced,
      },
      limit: PAGE_SIZE,
      offset: page * PAGE_SIZE,
    });
    setEntries(result.entries);
    setTotalCount(result.totalCount);
  }, [facilityId, dateRange, txnType, category, paymentMethod, debounced, page]);

  useEffect(() => {
    let cancelled = false;
    setEntries(null);
    load().catch((err) => {
      if (cancelled) return;
      setEntries([]);
      setListError(err instanceof ServiceError ? err.message : "Unable to load transactions right now.");
    });
    return () => {
      cancelled = true;
    };
  }, [load]);

  // Reset only means something once something has been changed — an always-on
  // Reset invites a click that does nothing.
  const hasActiveFilters =
    txnType !== ALL ||
    category !== ALL ||
    paymentMethod !== ALL ||
    search.trim() !== '' ||
    dateRange.preset !== DEFAULT_PRESET;

  function resetFilters() {
    setTxnType(ALL);
    setCategory(ALL);
    setPaymentMethod(ALL);
    setSearch('');
    setDateRange({ preset: DEFAULT_PRESET });
  }

  const totalPages = Math.max(1, Math.ceil(totalCount / PAGE_SIZE));
  const firstRow = totalCount === 0 ? 0 : page * PAGE_SIZE + 1;
  const lastRow = Math.min((page + 1) * PAGE_SIZE, totalCount);
  const pageNumbers = useMemo(() => pageWindow(page, totalPages), [page, totalPages]);

  if (loadState === "loading") return <Skeleton className="h-96 w-full rounded-xl" />;
  if (loadState === "none") return <p className="text-sm text-muted-foreground">No facility found for this account yet.</p>;
  if (loadState === "error") return <p className="text-sm text-destructive">Unable to load transactions right now.</p>;

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h1 className="text-xl font-semibold">Transactions</h1>
        <AddExpenseDialog onCreated={() => void load()} />
      </div>

      <Card className="p-4">
        {/* Top-aligned, not a grid: choosing a custom range grows that one
            field by two date inputs, and in a grid every cell in the row
            grew with it, dragging Reset down the card. Collapsed behind a
            button on phones, where four fields would push the table off
            screen. */}
        <div className={cn("flex flex-wrap items-start gap-3", !showFilters && "hidden lg:flex")}>
          <Filter label="Date Range" className="min-w-[13rem]">
            <DateRangePicker value={dateRange} onChange={setDateRange} />
          </Filter>

          <Filter label="Type" className="w-[8.5rem]">
            <FilterSelect
              value={txnType}
              onChange={setTxnType}
              options={[
                { value: ALL, label: "All" },
                { value: "INCOME", label: "Income" },
                { value: "EXPENSE", label: "Expense" },
                { value: "REFUND", label: "Refund" },
              ]}
            />
          </Filter>

          <Filter label="Category" className="w-[12rem]">
            <FilterSelect
              value={category}
              onChange={setCategory}
              options={[{ value: ALL, label: "All" }, ...CATEGORIES.map((c) => ({ value: c, label: c }))]}
            />
          </Filter>

          <Filter label="Payment Mode" className="w-[10rem]">
            <FilterSelect
              value={paymentMethod}
              onChange={setPaymentMethod}
              options={[{ value: ALL, label: "All" }, ...methods.map((m) => ({ value: m, label: m }))]}
            />
          </Filter>

          {/* A spacer standing in for the label keeps Reset on the same line
              as the inputs, whatever height the date field takes. */}
          <div className="ml-auto space-y-1.5">
            <span className="block select-none text-xs text-transparent" aria-hidden>
              Reset
            </span>
            <Button
              type="button"
              variant="outline"
              size="sm"
              disabled={!hasActiveFilters}
              onClick={resetFilters}
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
            placeholder="Search transaction ID, description…"
            aria-label="Search transactions"
            className="h-11 pl-9"
          />
        </div>
      </Card>

      <Card className="p-0">
        {listError && <p className="p-4 text-sm text-destructive">{listError}</p>}

        {entries === null ? (
          <div className="space-y-2 p-4">
            {Array.from({ length: 6 }).map((_, i) => (
              <Skeleton key={i} className="h-12 w-full rounded-lg" />
            ))}
          </div>
        ) : entries.length === 0 ? (
          <p className="p-10 text-center text-sm text-muted-foreground">
            No transactions match these filters.
          </p>
        ) : (
          <>
            <div className="hidden overflow-x-auto md:block">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-border text-left text-xs text-muted-foreground">
                    <th className="px-4 py-3 font-medium">Date</th>
                    <th className="px-4 py-3 font-medium">Transaction ID</th>
                    <th className="px-4 py-3 font-medium">Description</th>
                    <th className="px-4 py-3 font-medium">Category</th>
                    <th className="px-4 py-3 font-medium">Type</th>
                    <th className="px-4 py-3 font-medium">Payment Mode</th>
                    <th className="px-4 py-3 text-right font-medium">Amount</th>
                    <th className="px-4 py-3 font-medium">Status</th>
                  </tr>
                </thead>
                <tbody>
                  {entries.map((entry) => (
                    <tr
                      key={entry.id}

                      className="border-b border-border last:border-0 hover:bg-accent/30"
                    >
                      <td className="whitespace-nowrap px-4 py-3 text-muted-foreground">
                        {formatDate(entry.occurredAt)}
                      </td>
                      <td className="whitespace-nowrap px-4 py-3 font-medium">
                        {/* Only payments have a detail page — an expense and
                            a refund are the row you can already see. */}
                        {entry.txnType === "INCOME" ? (
                          <Link
                            href={`/finance/transactions/${entry.id}`}
                            className="text-primary hover:underline"
                          >
                            {entry.reference}
                          </Link>
                        ) : (
                          entry.reference
                        )}
                      </td>
                      <td className="px-4 py-3">
                        <span className="block max-w-xs truncate">{entry.description}</span>
                      </td>
                      <td className="px-4 py-3">
                        <span className={cn("inline-block rounded-md px-2 py-0.5 text-xs font-medium", categoryClass(entry))}>
                          {entry.category}
                        </span>
                      </td>
                      <td className="px-4 py-3">
                        <span className={cn("inline-block rounded-md px-2 py-0.5 text-xs font-medium capitalize", typeClass(entry.txnType))}>
                          {entry.txnType.toLowerCase()}
                        </span>
                      </td>
                      <td className="whitespace-nowrap px-4 py-3 text-muted-foreground">
                        {entry.paymentMethod ?? "—"}
                      </td>
                      <td className="whitespace-nowrap px-4 py-3 text-right font-medium tabular-nums">
                        {entry.txnType === "INCOME" ? "" : "−"}
                        {formatCurrency(entry.amountMinor, entry.currency)}
                      </td>
                      <td className="px-4 py-3">
                        <Badge variant={statusTone(entry.status)} className="capitalize">
                          {entry.status}
                        </Badge>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            <ul className="divide-y divide-border md:hidden">
              {entries.map((entry) => (
                <li key={entry.id} className="p-3">
                  <div className="flex items-start justify-between gap-3">
                    <div className="min-w-0">
                      <p className="truncate text-sm font-medium">{entry.description}</p>
                      <p className="text-xs text-muted-foreground">
                        {entry.txnType === "INCOME" ? (
                          <Link
                            href={`/finance/transactions/${entry.id}`}
                            className="text-primary hover:underline"
                          >
                            {entry.reference}
                          </Link>
                        ) : (
                          entry.reference
                        )}{" · "}
                        {formatDate(entry.occurredAt)}
                      </p>
                    </div>
                    <span className="shrink-0 text-sm font-semibold tabular-nums">
                      {entry.txnType === "INCOME" ? "" : "−"}
                      {formatCurrency(entry.amountMinor, entry.currency)}
                    </span>
                  </div>
                  <div className="mt-2 flex flex-wrap items-center gap-1.5">
                    <span className={cn("rounded-md px-2 py-0.5 text-xs font-medium", categoryClass(entry))}>
                      {entry.category}
                    </span>
                    {entry.paymentMethod && <Badge variant="secondary">{entry.paymentMethod}</Badge>}
                    <Badge variant={statusTone(entry.status)} className="capitalize">
                      {entry.status}
                    </Badge>
                  </div>
                </li>
              ))}
            </ul>
          </>
        )}

        {totalCount > 0 && (
          <div className="flex flex-wrap items-center justify-between gap-3 border-t border-border p-3">
            <p className="text-xs text-muted-foreground">
              Showing {firstRow} to {lastRow} of {totalCount} transaction{totalCount === 1 ? "" : "s"}
            </p>
            <div className="flex items-center gap-1">
              <PageButton
                label="Previous page"
                disabled={page === 0}
                onClick={() => setPage((p) => Math.max(0, p - 1))}
              >
                <ChevronLeft className="h-4 w-4" aria-hidden />
              </PageButton>

              {pageNumbers.map((n, i) =>
                n === "…" ? (
                  <span key={`gap-${i}`} className="px-1.5 text-xs text-muted-foreground">
                    …
                  </span>
                ) : (
                  <button
                    key={n}
                    type="button"
                    onClick={() => setPage(n - 1)}
                    aria-current={n - 1 === page ? "page" : undefined}
                    className={cn(
                      "min-h-8 min-w-8 rounded-md px-2 text-xs font-medium transition-colors",
                      n - 1 === page
                        ? "bg-primary text-primary-foreground"
                        : "border border-border hover:bg-accent",
                    )}
                  >
                    {n}
                  </button>
                ),
              )}

              <PageButton
                label="Next page"
                disabled={page + 1 >= totalPages}
                onClick={() => setPage((p) => p + 1)}
              >
                <ChevronRight className="h-4 w-4" aria-hidden />
              </PageButton>
            </div>
          </div>
        )}
      </Card>

    </div>
  );
}

function Filter({
  label,
  className,
  children,
}: {
  label: string;
  className?: string;
  children: React.ReactNode;
}) {
  return (
    <div className={cn('space-y-1.5', className)}>
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
        {options.map((option) => (
          <SelectItem key={option.value} value={option.value}>
            {option.label}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  );
}

function PageButton({
  label,
  disabled,
  onClick,
  children,
}: {
  label: string;
  disabled: boolean;
  onClick: () => void;
  children: React.ReactNode;
}) {
  return (
    <button
      type="button"
      aria-label={label}
      disabled={disabled}
      onClick={onClick}
      className="flex min-h-8 min-w-8 items-center justify-center rounded-md border border-border transition-colors hover:bg-accent disabled:cursor-not-allowed disabled:opacity-40"
    >
      {children}
    </button>
  );
}

/**
 * First page, last page, and a window around the current one — so a facility
 * with sixty pages doesn't render sixty buttons.
 */
function pageWindow(current: number, total: number): (number | "…")[] {
  const page = current + 1;
  if (total <= 7) return Array.from({ length: total }, (_, i) => i + 1);

  const out: (number | "…")[] = [1];
  const start = Math.max(2, page - 1);
  const end = Math.min(total - 1, page + 1);

  if (start > 2) out.push("…");
  for (let i = start; i <= end; i++) out.push(i);
  if (end < total - 1) out.push("…");
  out.push(total);
  return out;
}

function formatDate(iso: string): string {
  return new Date(iso).toLocaleDateString("en-IN", { day: "2-digit", month: "short", year: "numeric" });
}
