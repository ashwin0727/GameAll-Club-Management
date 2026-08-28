"use client";

import { useEffect, useState, type ReactNode } from "react";
import { Badge } from "@/components/ui/badge";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Skeleton } from "@/components/ui/skeleton";
import { formatCurrency } from "@/features/pricing/money";
import { getFinanceService } from "@/services/finance";
import type { FinanceTransaction } from "@/features/finance/types";

function formatDateTime(iso: string): string {
  return new Date(iso).toLocaleString("en-IN", { day: "numeric", month: "short", year: "numeric", hour: "numeric", minute: "2-digit", hour12: true });
}

function Row({ label, value }: { label: string; value: ReactNode }) {
  return (
    <div className="flex items-center justify-between border-b border-border py-2 text-sm last:border-0">
      <span className="text-muted-foreground">{label}</span>
      <span className="font-medium">{value}</span>
    </div>
  );
}

/**
 * Full traceability (spec §"Payment Traceability" / §"Transaction
 * Details"): Transaction → Payment Order → Razorpay Order/Payment, and →
 * Booking/Membership, and → Refund if any. Every field here is what
 * get_finance_transaction returns — nothing computed in this component.
 */
export function TransactionDetailsDialog({ transactionId, onOpenChange }: { transactionId: string | null; onOpenChange: (open: boolean) => void }) {
  const [transaction, setTransaction] = useState<FinanceTransaction | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!transactionId) {
      setTransaction(null);
      return;
    }
    setError(null);
    getFinanceService()
      .getTransaction(transactionId)
      .then(setTransaction)
      .catch(() => setError("Unable to load this transaction."));
  }, [transactionId]);

  return (
    <Dialog open={transactionId !== null} onOpenChange={onOpenChange}>
      <DialogContent className="max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Transaction Details</DialogTitle>
        </DialogHeader>
        {error && <p className="text-sm text-destructive">{error}</p>}
        {!transaction && !error ? (
          <Skeleton className="h-64 w-full rounded-lg" />
        ) : transaction ? (
          <div>
            <Row label="Transaction ID" value={transaction.reference} />
            <Row label="Date" value={formatDateTime(transaction.effectiveAt)} />
            <Row label="Customer" value={transaction.customerName ?? "—"} />
            <Row label="Source" value={transaction.sourceType.replace("_", " ")} />
            {transaction.bookingId && <Row label="Booking" value={transaction.bookingId.slice(0, 8)} />}
            {transaction.membershipId && <Row label="Membership" value={transaction.membershipId.slice(0, 8)} />}
            <Row label="Total Paid" value={formatCurrency(transaction.amountMinor, transaction.currency)} />
            <Row label="Refunded Amount" value={formatCurrency(transaction.refundedMinor, transaction.currency)} />
            {transaction.pendingRefundMinor > 0 && <Row label="Pending Refund" value={formatCurrency(transaction.pendingRefundMinor, transaction.currency)} />}
            <Row label="Net Amount" value={formatCurrency(transaction.netMinor, transaction.currency)} />
            <Row label="Payment Method" value={transaction.paymentMethod ?? "—"} />
            <Row label="Payment Status" value={<Badge className="capitalize">{transaction.status}</Badge>} />
            <Row label="Razorpay Order ID" value={transaction.razorpayOrderId ?? "—"} />
            <Row label="Razorpay Payment ID" value={transaction.razorpayPaymentId ?? "—"} />
            <Row label="Created At" value={formatDateTime(transaction.createdAt)} />
            <Row label="Paid At" value={transaction.paidAt ? formatDateTime(transaction.paidAt) : "—"} />
          </div>
        ) : null}
      </DialogContent>
    </Dialog>
  );
}