"use client";

import { useEffect, useState } from "react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { formatCurrency } from "@/features/pricing/money";
import { getFacilityService } from "@/services/facility";
import { getFinanceService } from "@/services/finance";
import type { FinanceDateRange, FinanceTransaction, TransactionStatus } from "@/features/finance/types";
import type { PaymentSourceType } from "@/features/payments/types";
import { DateRangePicker } from "@/features/finance/components/date-range-picker";
import { TransactionDetailsDialog } from "@/features/finance/components/transaction-details-dialog";
import { ServiceError } from "@/services/shared/service-error";

const PAGE_SIZE = 20;

function statusTone(status: TransactionStatus): "success" | "warning" | "destructive" | "secondary" {
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
 * Finance → Transactions (spec §"Transaction Management" / §"Transaction
 * Pagination"). Filtering, searching, and paging all happen server-side —
 * this component never downloads a full transaction list and slices it
 * client-side.
 */
export function TransactionsList() {
  const [facilityId, setFacilityId] = useState<string | null>(null);
  const [loadState, setLoadState] = useState<"loading" | "ready" | "none" | "error">("loading");

  const [dateRange, setDateRange] = useState<FinanceDateRange>({ preset: "THIS_MONTH" });
  const [sourceType, setSourceType] = useState<PaymentSourceType | "ALL">("ALL");
  const [status, setStatus] = useState<TransactionStatus | "ALL">("ALL");
  const [search, setSearch] = useState("");
  const [page, setPage] = useState(0);

  const [transactions, setTransactions] = useState<FinanceTransaction[]>([]);
  const [totalCount, setTotalCount] = useState(0);
  const [listLoading, setListLoading] = useState(false);
  const [listError, setListError] = useState<string | null>(null);
  const [selectedTransactionId, setSelectedTransactionId] = useState<string | null>(null);

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
      setLoadState("ready");
    })().catch(() => setLoadState("error"));
    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    setPage(0);
  }, [dateRange, sourceType, status, search]);

  useEffect(() => {
    if (!facilityId) return;
    if (dateRange.preset === "CUSTOM" && (!dateRange.startDate || !dateRange.endDate)) return;
    let cancelled = false;
    setListLoading(true);
    setListError(null);
    getFinanceService()
      .listTransactions({
        facilityId,
        dateRange,
        sourceType: sourceType === "ALL" ? undefined : sourceType,
        status: status === "ALL" ? undefined : status,
        search: search.trim() || undefined,
        limit: PAGE_SIZE,
        offset: page * PAGE_SIZE,
      })
      .then((result) => {
        if (cancelled) return;
        setTransactions(result.transactions);
        setTotalCount(result.totalCount);
      })
      .catch((err) => {
        if (cancelled) return;
        setListError(err instanceof ServiceError ? err.message : "Unable to load transactions.");
      })
      .finally(() => {
        if (!cancelled) setListLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [facilityId, dateRange, sourceType, status, search, page]);

  if (loadState === "loading") return <Skeleton className="h-64 w-full rounded-lg" />;
  if (loadState === "none") return <p className="text-sm text-muted-foreground">No facility found for this account yet.</p>;
  if (loadState === "error") return <p className="text-sm text-destructive">Unable to load transactions right now.</p>;

  const totalPages = Math.max(1, Math.ceil(totalCount / PAGE_SIZE));

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-2">
        <Input placeholder="Search by ID, name, booking, or Razorpay ID…" value={search} onChange={(e) => setSearch(e.target.value)} className="w-full sm:w-64" />
        <Select value={sourceType} onValueChange={(v) => setSourceType(v as PaymentSourceType | "ALL")}>
          <SelectTrigger className="w-[160px]">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="ALL">All Sources</SelectItem>
            <SelectItem value="MEMBERSHIP">Membership</SelectItem>
            <SelectItem value="MEMBER_BOOKING">Member Booking</SelectItem>
            <SelectItem value="GUEST_BOOKING">Guest Booking</SelectItem>
          </SelectContent>
        </Select>
        <Select value={status} onValueChange={(v) => setStatus(v as TransactionStatus | "ALL")}>
          <SelectTrigger className="w-[140px]">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="ALL">All Status</SelectItem>
            <SelectItem value="paid">Paid</SelectItem>
            <SelectItem value="created">Pending</SelectItem>
            <SelectItem value="failed">Failed</SelectItem>
            <SelectItem value="refunded">Refunded</SelectItem>
          </SelectContent>
        </Select>
        <DateRangePicker value={dateRange} onChange={setDateRange} />
      </div>

      {listError && <p className="text-sm text-destructive">{listError}</p>}

      {listLoading ? (
        <Skeleton className="h-64 w-full rounded-lg" />
      ) : transactions.length === 0 ? (
        <p className="text-sm text-muted-foreground">No transactions found for this period.</p>
      ) : (
        <div className="space-y-2">
          {transactions.map((txn) => (
            <button
              type="button"
              key={txn.id}
              onClick={() => setSelectedTransactionId(txn.id)}
              className="flex w-full items-center justify-between rounded-md border border-border p-3 text-left text-sm hover:bg-accent"
            >
              <div>
                <p className="font-medium">{txn.reference}</p>
                <p className="text-xs text-muted-foreground">
                  {new Date(txn.effectiveAt).toLocaleDateString("en-IN", { day: "numeric", month: "short", year: "numeric" })} · {txn.sourceType.replace("_", " ")} · {txn.customerName ?? "—"}
                </p>
              </div>
              <div className="flex items-center gap-3">
                <div className="text-right">
                  <p className="font-medium">{formatCurrency(txn.amountMinor, txn.currency)}</p>
                  {txn.refundedMinor > 0 && <p className="text-xs text-muted-foreground">Net {formatCurrency(txn.netMinor, txn.currency)}</p>}
                </div>
                <Badge variant={statusTone(txn.status)} className="capitalize">
                  {txn.status}
                </Badge>
              </div>
            </button>
          ))}
        </div>
      )}

      {totalCount > 0 && (
        <div className="flex items-center justify-between text-sm">
          <p className="text-muted-foreground">
            Page {page + 1} of {totalPages} · {totalCount} transaction{totalCount === 1 ? "" : "s"}
          </p>
          <div className="flex gap-2">
            <Button type="button" variant="outline" size="sm" disabled={page === 0} onClick={() => setPage((p) => Math.max(0, p - 1))}>
              Previous
            </Button>
            <Button type="button" variant="outline" size="sm" disabled={page + 1 >= totalPages} onClick={() => setPage((p) => p + 1)}>
              Next
            </Button>
          </div>
        </div>
      )}

      <TransactionDetailsDialog transactionId={selectedTransactionId} onOpenChange={(open) => !open && setSelectedTransactionId(null)} />
    </div>
  );
}