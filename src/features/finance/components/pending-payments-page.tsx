"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { ChevronLeft, ChevronRight, CircleCheck, Search, SlidersHorizontal } from "lucide-react";
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
import Link from "next/link";
import { ServiceError } from "@/services/shared/service-error";
import type {
  ObligationSort,
  ObligationSource,
  PaymentObligation,
  PendingPaymentsSummary,
} from "@/features/finance/types";

const PAGE_SIZE = 20;
const ALL = "ALL";
const DEFAULT_STATUS = "ALL_OUTSTANDING";

const SOURCE_LABEL: Record<ObligationSource, string> = {
  GUEST_BOOKING: "Guest Booking",
  BOOKING: "Court Booking",
  MEMBERSHIP: "Membership",
};

function statusTone(status: PaymentObligation["status"]): "success" | "warning" | "destructive" | "secondary" {
  if (status === "OVERDUE") return "destructive";
  if (status === "PARTIALLY_PAID") return "warning";
  if (status === "PAID") return "success";
  return "secondary";
}

function statusLabel(status: PaymentObligation["status"]): string {
  return status.replace(/_/g, " ").toLowerCase().replace(/^./, (c) => c.toUpperCase());
}

/**
 * Everything still owed, from every source, in one workspace — so collecting
 * a membership balance and collecting a guest booking are the same job.
 *
 * Nothing here computes what is owed: the database derives it from what each
 * booking or membership costs and what has been paid against it.
 */
export function PendingPaymentsPage() {
  const [facilityId, setFacilityId] = useState<string | null>(null);
  const [facilityName, setFacilityName] = useState("");
  const [loadState, setLoadState] = useState<"loading" | "ready" | "none" | "error">("loading");

  const [search, setSearch] = useState("");
  const [debounced, setDebounced] = useState("");
  const [sourceType, setSourceType] = useState<string>(ALL);
  const [status, setStatus] = useState<string>(DEFAULT_STATUS);
  const [sort, setSort] = useState<ObligationSort>("DUE_DATE");
  const [page, setPage] = useState(0);
  const [showFilters, setShowFilters] = useState(false);

  const [summary, setSummary] = useState<PendingPaymentsSummary | null>(null);
  const [obligations, setObligations] = useState<PaymentObligation[] | null>(null);
  const [totalCount, setTotalCount] = useState(0);
  const [error, setError] = useState<string | null>(null);

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
        setFacilityName(facility.name);
        setLoadState("ready");
      })
      .catch(() => !cancelled && setLoadState("error"));
    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    setPage(0);
  }, [debounced, sourceType, status, sort]);

  const load = useCallback(async () => {
    if (!facilityId) return;
    setError(null);
    const finance = getFinanceService();
    const [list, totals] = await Promise.all([
      finance.listPendingPayments({
        facilityId,
        filters: {
          search: debounced,
          sourceType: sourceType === ALL ? null : (sourceType as ObligationSource),
          status: status as PaymentObligation["status"] | "ALL_OUTSTANDING",
          sort,
        },
        limit: PAGE_SIZE,
        offset: page * PAGE_SIZE,
      }),
      finance.getPendingPaymentsSummary(facilityId),
    ]);
    setObligations(list.obligations);
    setTotalCount(list.totalCount);
    setSummary(totals);
  }, [facilityId, debounced, sourceType, status, sort, page]);

  useEffect(() => {
    let cancelled = false;
    setObligations(null);
    load().catch((err) => {
      if (cancelled) return;
      // Deliberately NOT an empty list: an empty list renders "You're all
      // caught up", and telling someone nothing is owed when the query
      // failed is the worst way this page can be wrong.
      setError(err instanceof ServiceError ? err.message : "Unable to load pending payments.");
    });
    return () => {
      cancelled = true;
    };
  }, [load]);

  const totalPages = Math.max(1, Math.ceil(totalCount / PAGE_SIZE));
  const firstRow = totalCount === 0 ? 0 : page * PAGE_SIZE + 1;
  const lastRow = Math.min((page + 1) * PAGE_SIZE, totalCount);
  const hasFilters = debounced.trim() !== "" || sourceType !== ALL || status !== DEFAULT_STATUS;

  const kpis = useMemo(
    () =>
      summary
        ? [
            { label: "Outstanding Total", value: summary.outstandingMinor, accent: "text-primary" },
            { label: "Pending", value: summary.pendingMinor, accent: "text-foreground" },
            { label: "Partially Paid", value: summary.partiallyPaidMinor, accent: "text-foreground" },
            { label: "Overdue", value: summary.overdueMinor, accent: "text-destructive" },
          ]
        : [],
    [summary],
  );

  if (loadState === "loading") return <Skeleton className="h-96 w-full rounded-xl" />;
  if (loadState === "none") return <p className="text-sm text-muted-foreground">No facility found for this account yet.</p>;
  if (loadState === "error") return <p className="text-sm text-destructive">Unable to load pending payments.</p>;

  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-xl font-semibold">Pending Payments</h1>
        <p className="text-sm text-muted-foreground">
          Track and collect outstanding payments{facilityName ? ` at ${facilityName}` : ""}.
        </p>
      </div>

      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        {summary === null
          ? Array.from({ length: 4 }).map((_, i) => <Skeleton key={i} className="h-20 rounded-xl" />)
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
          <FilterField label="Status" className="w-[11rem]">
            <FilterSelect
              value={status}
              onChange={setStatus}
              options={[
                { value: DEFAULT_STATUS, label: "All Outstanding" },
                { value: "PENDING", label: "Pending" },
                { value: "PARTIALLY_PAID", label: "Partially Paid" },
                { value: "OVERDUE", label: "Overdue" },
                { value: "PAID", label: "Paid" },
              ]}
            />
          </FilterField>

          <FilterField label="Source" className="w-[11rem]">
            <FilterSelect
              value={sourceType}
              onChange={setSourceType}
              options={[
                { value: ALL, label: "All Sources" },
                { value: "GUEST_BOOKING", label: "Guest Booking" },
                { value: "BOOKING", label: "Court Booking" },
                { value: "MEMBERSHIP", label: "Membership" },
              ]}
            />
          </FilterField>

          <FilterField label="Sort by" className="w-[10rem]">
            <FilterSelect
              value={sort}
              onChange={(v) => setSort(v as ObligationSort)}
              options={[
                { value: "DUE_DATE", label: "Oldest first" },
                { value: "AMOUNT", label: "Largest" },
                { value: "CUSTOMER", label: "Customer" },
                { value: "NEWEST", label: "Newest" },
              ]}
            />
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
                setSourceType(ALL);
                setStatus(DEFAULT_STATUS);
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
            placeholder="Search customer, phone, booking or membership ID…"
            aria-label="Search pending payments"
            className="h-11 pl-9"
          />
        </div>
      </Card>

      <Card className="p-0">
        {error ? (
          <div className="p-10 text-center">
            <p className="text-sm font-semibold text-destructive">Unable to load pending payments</p>
            <p className="mt-1 text-sm text-muted-foreground">{error}</p>
            <Button type="button" variant="outline" className="mt-4" onClick={() => void load()}>
              Try again
            </Button>
          </div>
        ) : obligations === null ? (
          <div className="space-y-2 p-4">
            {Array.from({ length: 6 }).map((_, i) => (
              <Skeleton key={i} className="h-14 w-full rounded-lg" />
            ))}
          </div>
        ) : obligations.length === 0 ? (
          <div className="p-10 text-center">
            <span className="mx-auto flex h-12 w-12 items-center justify-center rounded-full bg-primary/12">
              <CircleCheck className="h-6 w-6 text-primary" aria-hidden />
            </span>
            <p className="mt-3 text-sm font-semibold">You&apos;re all caught up</p>
            <p className="mt-1 text-sm text-muted-foreground">
              There are no pending payments for the selected filters.
            </p>
          </div>
        ) : (
          <>
            <div className="hidden overflow-x-auto lg:block">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-border text-left text-xs text-muted-foreground">
                    <th className="px-4 py-3 font-medium">Customer</th>
                    <th className="px-4 py-3 font-medium">Source</th>
                    <th className="px-4 py-3 font-medium">Reference</th>
                    <th className="px-4 py-3 font-medium">Description</th>
                    <th className="px-4 py-3 text-right font-medium">Total</th>
                    <th className="px-4 py-3 text-right font-medium">Paid</th>
                    <th className="px-4 py-3 text-right font-medium">Outstanding</th>
                    <th className="px-4 py-3 font-medium">Status</th>
                    <th className="px-4 py-3 font-medium">Due</th>
                    <th className="px-4 py-3" />
                  </tr>
                </thead>
                <tbody>
                  {obligations.map((o) => (
                    <tr key={`${o.sourceType}-${o.sourceId}`} className="border-b border-border last:border-0">
                      <td className="px-4 py-3">
                        <span className="block font-medium">{o.customerName}</span>
                        {o.customerPhone && (
                          <span className="block text-xs text-muted-foreground">{o.customerPhone}</span>
                        )}
                      </td>
                      <td className="whitespace-nowrap px-4 py-3 text-muted-foreground">
                        {SOURCE_LABEL[o.sourceType]}
                      </td>
                      <td className="whitespace-nowrap px-4 py-3 font-medium">{o.reference}</td>
                      <td className="px-4 py-3">
                        <span className="block max-w-[16rem] truncate text-muted-foreground">{o.description}</span>
                      </td>
                      <td className="whitespace-nowrap px-4 py-3 text-right tabular-nums">
                        {formatCurrency(o.totalMinor, "INR")}
                      </td>
                      <td className="whitespace-nowrap px-4 py-3 text-right tabular-nums text-muted-foreground">
                        {formatCurrency(o.paidMinor, "INR")}
                      </td>
                      <td className="whitespace-nowrap px-4 py-3 text-right font-semibold tabular-nums">
                        {formatCurrency(o.outstandingMinor, "INR")}
                      </td>
                      <td className="px-4 py-3">
                        <Badge variant={statusTone(o.status)}>{statusLabel(o.status)}</Badge>
                      </td>
                      <td className="whitespace-nowrap px-4 py-3 text-muted-foreground">{formatDate(o.dueOn)}</td>
                      <td className="px-4 py-3 text-right">
                        <Button asChild size="sm">
                          <Link href={`/finance/pending-payments/${o.sourceId}/record`}>Record</Link>
                        </Button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            <ul className="divide-y divide-border lg:hidden">
              {obligations.map((o) => (
                <li key={`${o.sourceType}-${o.sourceId}`} className="p-3">
                  <div className="flex items-start justify-between gap-3">
                    <div className="min-w-0">
                      <p className="truncate font-medium">{o.customerName}</p>
                      <p className="text-xs text-muted-foreground">
                        {SOURCE_LABEL[o.sourceType]} · {o.reference}
                      </p>
                      <p className="mt-0.5 truncate text-xs text-muted-foreground">{o.description}</p>
                    </div>
                    <Badge variant={statusTone(o.status)}>{statusLabel(o.status)}</Badge>
                  </div>

                  <dl className="mt-2 space-y-0.5 text-sm">
                    <AmountRow label="Total" value={o.totalMinor} />
                    <AmountRow label="Paid" value={o.paidMinor} muted />
                    <div className="flex justify-between border-t border-border pt-1">
                      <dt className="font-medium">Outstanding</dt>
                      <dd className="font-semibold tabular-nums">{formatCurrency(o.outstandingMinor, "INR")}</dd>
                    </div>
                  </dl>

                  <Button asChild className="mt-3 min-h-11 w-full">
                    <Link href={`/finance/pending-payments/${o.sourceId}/record`}>
                      Record {formatCurrency(o.outstandingMinor, "INR")}
                    </Link>
                  </Button>
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

function AmountRow({ label, value, muted }: { label: string; value: number; muted?: boolean }) {
  return (
    <div className="flex justify-between">
      <dt className="text-muted-foreground">{label}</dt>
      <dd className={cn("tabular-nums", muted && "text-muted-foreground")}>{formatCurrency(value, "INR")}</dd>
    </div>
  );
}

function FilterField({
  label,
  className,
  children,
}: {
  label: string;
  className?: string;
  children: React.ReactNode;
}) {
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
        {options.map((option) => (
          <SelectItem key={option.value} value={option.value}>
            {option.label}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  );
}

function formatDate(iso: string): string {
  return new Date(iso).toLocaleDateString("en-IN", { day: "2-digit", month: "short", year: "numeric" });
}
