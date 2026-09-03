"use client";

import { useEffect, useMemo, useState } from "react";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { formatCurrency } from "@/features/pricing/money";
import { canRecordPayment } from "@/features/finance/money";
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

/**
 * Collects against any obligation — a guest booking, a court booking or a
 * membership. Nothing here is source-specific beyond the summary it shows,
 * which is why "Record Payment" is no longer a guest booking feature.
 */
export function RecordPaymentDialog({
  obligation,
  onClose,
  onRecorded,
}: {
  obligation: PaymentObligation | null;
  onClose: () => void;
  onRecorded: () => void;
}) {
  const [amount, setAmount] = useState("");
  const [method, setMethod] = useState("Cash");
  const [paidOn, setPaidOn] = useState(today);
  const [reference, setReference] = useState("");
  const [notes, setNotes] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  /**
   * One key per opening of the form. A double-click, a retry or a dropped
   * connection re-sends the same key, and the server returns the original
   * payment rather than taking the money twice.
   */
  const idempotencyKey = useMemo(
    () => (obligation ? `${obligation.sourceType}:${obligation.sourceId}:${crypto.randomUUID()}` : ""),
    [obligation],
  );

  useEffect(() => {
    if (!obligation) return;
    // Defaults to the whole balance, which is what is usually collected.
    setAmount(String(obligation.outstandingMinor / 100));
    setMethod("Cash");
    setPaidOn(today());
    setReference("");
    setNotes("");
    setError(null);
  }, [obligation]);

  if (!obligation) return null;

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
      onRecorded();
      onClose();
    } catch (e) {
      setError(
        e instanceof ServiceError
          ? e.message
          : "Unable to record this payment. The balance may have changed — please reopen and check.",
      );
    } finally {
      setBusy(false);
    }
  }

  return (
    <Dialog open onOpenChange={(open) => !open && onClose()}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Record Payment</DialogTitle>
          <DialogDescription>Record payment for this outstanding balance.</DialogDescription>
        </DialogHeader>

        <div className="space-y-4">
          <section className="rounded-xl border border-border p-3">
            <dl className="space-y-1 text-sm">
              <Row label="Source" value={SOURCE_LABEL[obligation.sourceType]} />
              <Row label="Customer" value={obligation.customerName} />
              <Row label="Reference" value={obligation.reference} />
              <Row label="Details" value={obligation.description} />
            </dl>
          </section>

          <section className="rounded-xl border border-border p-3">
            <dl className="space-y-1 text-sm">
              <Row label="Total amount" value={formatCurrency(obligation.totalMinor, "INR")} />
              <Row label="Already paid" value={formatCurrency(obligation.paidMinor, "INR")} />
              <div className="flex items-baseline justify-between gap-3 border-t border-border pt-1.5">
                <dt className="font-semibold">Outstanding</dt>
                <dd className="text-base font-semibold text-primary">
                  {formatCurrency(obligation.outstandingMinor, "INR")}
                </dd>
              </div>
            </dl>
          </section>

          <div className="grid grid-cols-2 gap-3">
            <Field id="collect-amount" label="Amount to collect" required>
              <Input
                id="collect-amount"
                inputMode="decimal"
                value={amount}
                onChange={(e) => setAmount(e.target.value)}
                aria-invalid={!check.ok || undefined}
              />
            </Field>
            <Field id="collect-date" label="Payment date" required>
              <Input id="collect-date" type="date" value={paidOn} onChange={(e) => setPaidOn(e.target.value)} />
            </Field>
          </div>

          <Field id="collect-method" label="Payment mode" required>
            <div className="flex flex-wrap gap-2">
              {METHODS.map((m) => (
                <Button
                  key={m}
                  type="button"
                  size="sm"
                  variant={m === method ? "default" : "outline"}
                  onClick={() => setMethod(m)}
                >
                  {m}
                </Button>
              ))}
            </div>
          </Field>

          <Field id="collect-reference" label={`Reference${method === "Cash" ? " (optional)" : ""}`}>
            <Input
              id="collect-reference"
              value={reference}
              onChange={(e) => setReference(e.target.value)}
              placeholder={method === "Cash" ? "Receipt number" : "Transaction ID"}
            />
          </Field>

          <Field id="collect-notes" label="Notes (optional)">
            <Textarea id="collect-notes" rows={2} value={notes} onChange={(e) => setNotes(e.target.value)} />
          </Field>

          {/* Shown before committing, so nobody has to work out what a part
              payment leaves behind. */}
          {check.ok && (
            <div className="rounded-xl bg-muted/50 p-3 text-sm">
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
            <p role="alert" className="text-sm text-destructive">
              {check.reason}
            </p>
          )}
          {error && (
            <p role="alert" className="text-sm text-destructive">
              {error}
            </p>
          )}
        </div>

        <DialogFooter>
          <Button type="button" variant="outline" onClick={onClose} disabled={busy}>
            Cancel
          </Button>
          <Button type="button" onClick={submit} disabled={busy || !check.ok}>
            {busy ? "Recording…" : `Record Payment ${formatCurrency(amountMinor, "INR")}`}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-baseline justify-between gap-3">
      <dt className="text-muted-foreground">{label}</dt>
      <dd className="truncate text-right font-medium">{value}</dd>
    </div>
  );
}

function Field({
  id,
  label,
  required,
  children,
}: {
  id: string;
  label: string;
  required?: boolean;
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
      </Label>
      {children}
    </div>
  );
}
