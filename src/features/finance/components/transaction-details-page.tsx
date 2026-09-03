"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { ChevronRight, Download } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { cn } from "@/lib/utils";
import { formatCurrency } from "@/features/pricing/money";
import { getFinanceService } from "@/services/finance";
import { ServiceError } from "@/services/shared/service-error";
import type { TransactionDetails } from "@/features/finance/types";

function when(iso: string | null): string {
  if (!iso) return "—";
  // Pinned to IST so this always matches the PDF receipt, which renders
  // server-side (in UTC) and can't infer the viewer's own timezone.
  return new Date(iso).toLocaleString("en-IN", {
    day: "2-digit",
    month: "short",
    year: "numeric",
    hour: "numeric",
    minute: "2-digit",
    hour12: true,
    timeZone: "Asia/Kolkata",
  });
}

function statusTone(status: string): "success" | "warning" | "destructive" | "secondary" {
  if (status === "paid") return "success";
  if (status === "failed") return "destructive";
  if (status === "refunded") return "secondary";
  return "warning";
}

/**
 * One transaction, in full — what it was for, what it relates to, and every
 * payment made against the same booking or membership.
 *
 * The receipt is built server-side by an edge function: pdf-lib is already a
 * project dependency there, and only this page would need it in the browser.
 */
export function TransactionDetailsPage({ transactionId }: { transactionId: string }) {
  const [details, setDetails] = useState<TransactionDetails | null>(null);
  const [state, setState] = useState<"loading" | "ready" | "error">("loading");
  const [downloading, setDownloading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    getFinanceService()
      .getTransactionDetails(transactionId)
      .then((found) => {
        if (cancelled) return;
        setDetails(found);
        setState("ready");
      })
      .catch(() => !cancelled && setState("error"));
    return () => {
      cancelled = true;
    };
  }, [transactionId]);

  async function downloadReceipt() {
    if (!details || downloading) return;
    setDownloading(true);
    setError(null);
    try {
      const blob = await getFinanceService().downloadTransactionReceipt(details.id);
      const url = URL.createObjectURL(blob);
      const link = document.createElement("a");
      link.href = url;
      link.download = `receipt-${details.reference}.pdf`;
      document.body.appendChild(link);
      link.click();
      link.remove();
      // Released on the next tick so the click has taken the URL.
      setTimeout(() => URL.revokeObjectURL(url), 0);
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Could not download the receipt. Please try again.");
    } finally {
      setDownloading(false);
    }
  }

  if (state === "loading") {
    return (
      <div className="space-y-4">
        <Skeleton className="h-8 w-64" />
        <Skeleton className="h-64 w-full rounded-xl" />
        <Skeleton className="h-40 w-full rounded-xl" />
      </div>
    );
  }

  if (state === "error" || !details) {
    return (
      <Card className="p-8 text-center">
        <p className="text-sm font-semibold">We couldn&apos;t find that transaction</p>
        <p className="mt-1 text-sm text-muted-foreground">
          It may have been removed, or belong to another facility.
        </p>
        <Button asChild variant="outline" className="mt-4">
          <Link href="/finance/transactions">Back to Transactions</Link>
        </Button>
      </Card>
    );
  }

  return (
    <div className="space-y-4">
      <nav aria-label="Breadcrumb" className="flex items-center gap-1 text-xs text-muted-foreground">
        <Link href="/finance" className="hover:text-foreground">
          Finance
        </Link>
        <ChevronRight className="h-3 w-3" aria-hidden />
        <Link href="/finance/transactions" className="hover:text-foreground">
          Transactions
        </Link>
        <ChevronRight className="h-3 w-3" aria-hidden />
        <span className="text-foreground">{details.reference}</span>
      </nav>

      <div className="flex flex-wrap items-center justify-between gap-3">
        <h1 className="text-xl font-semibold">Transaction Details</h1>
        <Button type="button" onClick={downloadReceipt} disabled={downloading} className="min-h-9">
          <Download className="h-4 w-4" aria-hidden />
          {downloading ? "Preparing…" : "Download Receipt"}
        </Button>
      </div>

      {error && (
        <p role="alert" className="text-sm text-destructive">
          {error}
        </p>
      )}

      <Card className="p-4">
        <h2 className="mb-4 text-sm font-semibold">Transaction Information</h2>
        <dl className="grid gap-x-8 gap-y-3 sm:grid-cols-2">
          <Row label="Transaction ID" value={details.reference} />
          <Row
            label="Type"
            value={<Badge variant="success">Income</Badge>}
          />
          <Row label="Category" value={details.category} />
          <Row label="Amount" value={formatCurrency(details.amountMinor, details.currency)} />
          <Row label="Payment Mode" value={details.paymentMethod ?? "—"} />
          <Row
            label="Status"
            value={
              <Badge variant={statusTone(details.status)} className="capitalize">
                {details.status}
              </Badge>
            }
          />
          <Row label="Transaction Date" value={when(details.occurredAt)} />
          <Row label="Reference" value={details.sourceReference ?? "—"} />
          <Row label="Description" value={details.description} className="sm:col-span-2" />
          <Row label="Recorded By" value={details.recordedBy ?? "—"} />
          <Row label="Created At" value={when(details.createdAt)} />
          {details.refundedMinor > 0 && (
            <>
              <Row label="Refunded" value={formatCurrency(details.refundedMinor, details.currency)} />
              <Row label="Net" value={formatCurrency(details.netMinor, details.currency)} />
            </>
          )}
        </dl>
      </Card>

      <Card className="p-4">
        <h2 className="mb-4 text-sm font-semibold">Related Information</h2>
        <dl className="space-y-3">
          {details.bookingId && (
            <RelatedRow
              label="Booking"
              value={details.sourceReference ?? "Booking"}
              href={`/guest-bookings/${details.bookingId}/edit`}
            />
          )}
          {details.membershipId && (
            <RelatedRow
              label="Membership"
              value={details.sourceReference ?? "Membership"}
              href={`/memberships/${details.membershipId}`}
            />
          )}
          <RelatedRow
            label="Customer"
            value={details.customerName ?? "—"}
            href={details.bookingId ? "/guests" : undefined}
          />
          <RelatedRow label="Facility" value={details.facilityName ?? "—"} />
        </dl>
      </Card>

      <Card className="p-0">
        <h2 className="border-b border-border p-4 text-sm font-semibold">Payment History</h2>

        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-border text-left text-xs text-muted-foreground">
                <th className="px-4 py-3 font-medium">Date</th>
                <th className="px-4 py-3 text-right font-medium">Amount</th>
                <th className="px-4 py-3 font-medium">Mode</th>
                <th className="px-4 py-3 font-medium">Reference</th>
                <th className="px-4 py-3 font-medium">Status</th>
              </tr>
            </thead>
            <tbody>
              {details.history.map((h) => (
                <tr
                  key={h.id}
                  className={cn(
                    "border-b border-border last:border-0",
                    // The payment this page is about, among its siblings.
                    h.isThisOne && "bg-primary/5",
                  )}
                >
                  <td className="whitespace-nowrap px-4 py-3 text-muted-foreground">{when(h.paidAt)}</td>
                  <td className="whitespace-nowrap px-4 py-3 text-right font-medium tabular-nums">
                    {formatCurrency(h.amountMinor, details.currency)}
                  </td>
                  <td className="whitespace-nowrap px-4 py-3">{h.paymentMethod ?? "—"}</td>
                  <td className="px-4 py-3 text-muted-foreground">{h.reference ?? "—"}</td>
                  <td className="px-4 py-3">
                    <Badge variant={statusTone(h.status)} className="capitalize">
                      {h.status}
                    </Badge>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        {details.history.length > 1 && (
          <div className="flex items-center justify-between border-t border-border p-4 text-sm">
            <span className="text-muted-foreground">Total collected</span>
            <span className="font-semibold tabular-nums">
              {formatCurrency(
                details.history.reduce((sum, h) => sum + h.amountMinor, 0),
                details.currency,
              )}
            </span>
          </div>
        )}
      </Card>
    </div>
  );
}

function Row({
  label,
  value,
  className,
}: {
  label: string;
  value: React.ReactNode;
  className?: string;
}) {
  return (
    <div className={cn("flex items-baseline justify-between gap-4 sm:justify-start", className)}>
      <dt className="w-36 shrink-0 text-sm text-muted-foreground">{label}</dt>
      <dd className="min-w-0 text-sm font-medium">{value}</dd>
    </div>
  );
}

function RelatedRow({ label, value, href }: { label: string; value: string; href?: string }) {
  return (
    <div className="flex items-center justify-between gap-4">
      <dt className="w-36 shrink-0 text-sm text-muted-foreground">{label}</dt>
      <dd className="min-w-0 flex-1 truncate text-sm font-medium">{value}</dd>
      {href && (
        <Link href={href} className="shrink-0 text-sm font-medium text-primary hover:underline">
          View
        </Link>
      )}
    </div>
  );
}
