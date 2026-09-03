"use client";

import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { ChevronRight } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { Textarea } from "@/components/ui/textarea";
import { formatCurrency } from "@/features/pricing/money";
import { canRecordPayment } from "@/features/finance/money";
import { getFacilityService } from "@/services/facility";
import { getFinanceService } from "@/services/finance";
import { ServiceError } from "@/services/shared/service-error";
import type { PaymentObligation } from "@/features/finance/types";

const METHODS = ["Cash", "UPI", "Card", "Bank Transfer"];

const SOURCE_LABEL: Record<PaymentObligation["sourceType"], string> = {
  GUEST_BOOKING: "Guest Booking",
  BOOKING: "Court Booking",
  MEMBERSHIP: "Membership",
};

function today(): string {
  const now = new Date();
  return `${now.getFullYear()}-${`${now.getMonth() + 1}`.padStart(2, "0")}-${`${now.getDate()}`.padStart(2, "0")}`;
}

function statusTone(status: PaymentObligation["status"]): "success" | "warning" | "destructive" | "secondary" {
  if (status === "OVERDUE") return "destructive";
  if (status === "PARTIALLY_PAID") return "warning";
  if (status === "PAID") return "success";
  return "warning";
}

/**
 * Record Payment as its own page rather than a dialog.
 *
 * It loads the obligation from its id rather than taking it from the list
 * that linked here, so the page survives a reload, can be linked to, and
 * shows the balance as it stands now — not as it stood when the list was
 * last fetched.
 */
export function RecordPaymentPage({ sourceId }: { sourceId: string }) {
  const router = useRouter();

  const [obligation, setObligation] = useState<PaymentObligation | null>(null);
  const [loadState, setLoadState] = useState<"loading" | "ready" | "missing" | "error">("loading");

  const [amount, setAmount] = useState("");
  const [method, setMethod] = useState("Cash");
  const [paidOn, setPaidOn] = useState(today);
  const [reference, setReference] = useState("");
  const [notes, setNotes] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // One key per visit. A double-click or a retried request re-sends it, and
  // the server returns the original payment rather than taking money twice.
  const idempotencyKey = useMemo(() => `${sourceId}:${crypto.randomUUID()}`, [sourceId]);

  useEffect(() => {
    let cancelled = false;
    getFacilityService()
      .getFacility()
      .then((facility) => {
        if (!facility) throw new Error("no facility");
        return getFinanceService().getPaymentObligation(facility.id, sourceId);
      })
      .then((found) => {
        if (cancelled) return;
        if (!found) {
          setLoadState("missing");
          return;
        }
        setObligation(found);
        setAmount(String(found.outstandingMinor / 100));
        setLoadState("ready");
      })
      .catch(() => !cancelled && setLoadState("error"));
    return () => {
      cancelled = true;
    };
  }, [sourceId]);

  if (loadState === "loading") {
    return (
      <div className="space-y-4">
        <Skeleton className="h-40 w-full rounded-xl" />
        <Skeleton className="h-64 w-full rounded-xl" />
      </div>
    );
  }

  if (loadState === "missing" || !obligation) {
    return (
      <Card className="p-8 text-center">
        <p className="text-sm font-semibold">We couldn&apos;t find that record</p>
        <p className="mt-1 text-sm text-muted-foreground">
          It may have been cancelled or already settled.
        </p>
        <Button asChild variant="outline" className="mt-4">
          <Link href="/finance/pending-payments">Back to Pending Payments</Link>
        </Button>
      </Card>
    );
  }

  if (loadState === "error") {
    return <p className="text-sm text-destructive">Unable to load this record. Please try again.</p>;
  }

  const settled = obligation.outstandingMinor <= 0;
  const amountMinor = Math.round((Number(amount) || 0) * 100);
  const check = canRecordPayment({ amountMinor, outstandingMinor: obligation.outstandingMinor });
  const remaining = obligation.outstandingMinor - amountMinor;

  async function submit() {
    if (!obligation || busy || !check.ok) return;
    setBusy(true);
    setError(null);
    try {
      await getFinanceService().recordObligationPayment({
        sourceType: obligation.sourceType,
        sourceId: obligation.sourceId,
        amountMinor,
        method,
        paidOn,
        reference: reference.trim() || null,
        notes: notes.trim() || null,
        idempotencyKey,
      });
      router.push("/finance/pending-payments");
      router.refresh();
    } catch (e) {
      setError(
        e instanceof ServiceError
          ? e.message
          : "Unable to record this payment. The balance may have changed — reload and check.",
      );
      setBusy(false);
    }
  }

  const isBooking = obligation.sourceType !== "MEMBERSHIP";

  return (
    <div className="space-y-4">
      <nav aria-label="Breadcrumb" className="flex items-center gap-1 text-xs text-muted-foreground">
        <Link href="/finance" className="hover:text-foreground">
          Finance
        </Link>
        <ChevronRight className="h-3 w-3" aria-hidden />
        <Link href="/finance/pending-payments" className="hover:text-foreground">
          Payments
        </Link>
        <ChevronRight className="h-3 w-3" aria-hidden />
        <span className="text-foreground">Record Payment</span>
      </nav>

      <h1 className="text-xl font-semibold">Record Payment</h1>

      <Card className="p-4">
        <h2 className="mb-3 text-sm font-semibold">
          {isBooking ? "Booking Details" : "Membership Details"}
        </h2>
        <dl className="space-y-2.5 text-sm">
          <DetailRow label={isBooking ? "Booking ID" : "Membership ID"} value={obligation.reference} />
          <DetailRow label="Customer" value={obligation.customerName} />
          {obligation.customerPhone && <DetailRow label="Phone" value={obligation.customerPhone} />}
          {obligation.facilityName && <DetailRow label="Facility" value={obligation.facilityName} />}
          <DetailRow
            label={isBooking ? "Court & Time" : "Membership"}
            value={obligation.description}
          />
          <DetailRow label="Source" value={SOURCE_LABEL[obligation.sourceType]} />
          <DetailRow label="Total amount" value={formatCurrency(obligation.totalMinor, "INR")} />
          {obligation.paidMinor > 0 && (
            <DetailRow label="Already paid" value={formatCurrency(obligation.paidMinor, "INR")} />
          )}
          <div className="flex items-baseline justify-between gap-4 border-t border-border pt-2.5">
            <dt className="font-semibold">Amount Due</dt>
            <dd className="text-base font-semibold text-primary">
              {formatCurrency(obligation.outstandingMinor, "INR")}
            </dd>
          </div>
          <div className="flex items-center justify-between gap-4">
            <dt className="text-muted-foreground">Payment Status</dt>
            <dd>
              <Badge variant={statusTone(obligation.status)}>
                {obligation.status.replace(/_/g, " ").toLowerCase().replace(/^./, (c) => c.toUpperCase())}
              </Badge>
            </dd>
          </div>
        </dl>
      </Card>

      {settled ? (
        <Card className="p-6 text-center">
          <p className="text-sm font-semibold">This is already paid in full</p>
          <p className="mt-1 text-sm text-muted-foreground">
            There is nothing left to collect against this record.
          </p>
          <Button asChild variant="outline" className="mt-4">
            <Link href="/finance/pending-payments">Back to Pending Payments</Link>
          </Button>
        </Card>
      ) : (
        <Card className="p-4">
          <h2 className="mb-3 text-sm font-semibold">Payment Information</h2>

          <div className="grid gap-4 sm:grid-cols-2">
            <Field id="pay-amount" label="Amount" required>
              <Input
                id="pay-amount"
                inputMode="decimal"
                value={amount}
                onChange={(e) => setAmount(e.target.value)}
                aria-invalid={!check.ok || undefined}
                className="h-11"
              />
            </Field>

            <Field id="pay-mode" label="Payment Mode" required>
              <Select value={method} onValueChange={setMethod}>
                <SelectTrigger id="pay-mode" className="h-11">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {METHODS.map((m) => (
                    <SelectItem key={m} value={m}>
                      {m}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </Field>

            <Field id="pay-date" label="Payment Date" required>
              <Input
                id="pay-date"
                type="date"
                value={paidOn}
                onChange={(e) => setPaidOn(e.target.value)}
                className="h-11"
              />
            </Field>

            <Field
              id="pay-reference"
              label="Reference"
              hint={method === "Cash" ? "Optional" : "Recommended"}
            >
              <Input
                id="pay-reference"
                value={reference}
                onChange={(e) => setReference(e.target.value)}
                placeholder={method === "Cash" ? "Receipt number" : "UPI123456"}
                className="h-11"
              />
            </Field>

            <div className="sm:col-span-2">
              <Field id="pay-notes" label="Notes" hint="Optional">
                <Textarea
                  id="pay-notes"
                  rows={3}
                  value={notes}
                  onChange={(e) => setNotes(e.target.value)}
                  placeholder="Paid at venue"
                />
              </Field>
            </div>
          </div>

          {/* Shown before committing, so a part payment's remainder is never
              something anyone has to work out. */}
          {check.ok && amountMinor < obligation.outstandingMinor && (
            <div className="mt-4 rounded-xl bg-muted/50 p-3 text-sm">
              <div className="flex justify-between">
                <span className="text-muted-foreground">This payment</span>
                <span className="font-medium">{formatCurrency(amountMinor, "INR")}</span>
              </div>
              <div className="mt-1 flex justify-between">
                <span className="text-muted-foreground">Remaining after payment</span>
                <span className="font-semibold">{formatCurrency(remaining, "INR")}</span>
              </div>
            </div>
          )}

          {!check.ok && amount.trim() !== "" && (
            <p role="alert" className="mt-3 text-sm text-destructive">
              {check.reason}
            </p>
          )}
          {error && (
            <p role="alert" className="mt-3 text-sm text-destructive">
              {error}
            </p>
          )}

          <div className="mt-5 flex flex-wrap items-center justify-end gap-2 border-t border-border pt-4">
            <Button asChild variant="outline" className="min-h-11">
              <Link href="/finance/pending-payments">Cancel</Link>
            </Button>
            <Button type="button" onClick={submit} disabled={busy || !check.ok} className="min-h-11">
              {busy ? "Recording…" : `Record Payment ${check.ok ? formatCurrency(amountMinor, "INR") : ""}`}
            </Button>
          </div>
        </Card>
      )}
    </div>
  );
}

function DetailRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-baseline justify-between gap-4">
      <dt className="shrink-0 text-muted-foreground">{label}</dt>
      <dd className="truncate text-right font-medium">{value}</dd>
    </div>
  );
}

function Field({
  id,
  label,
  required,
  hint,
  children,
}: {
  id: string;
  label: string;
  required?: boolean;
  hint?: string;
  children: React.ReactNode;
}) {
  return (
    <div className="space-y-1.5">
      <Label htmlFor={id} className="text-xs font-medium">
        {label}
        {required && (
          <span className="ml-0.5 text-destructive" aria-hidden>
            *
          </span>
        )}
        {hint && <span className="ml-1 font-normal text-muted-foreground">({hint})</span>}
      </Label>
      {children}
    </div>
  );
}
