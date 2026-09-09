"use client";

import { useState } from "react";
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
import { formatCurrency, fromMinorUnits, toMinorUnits } from "@/features/pricing/money";
import { getFinanceService } from "@/services/finance";
import { ServiceError } from "@/services/shared/service-error";
import type { ExpenseRow } from "@/features/finance/types";

const METHODS = ["Cash", "UPI", "Card", "Bank Transfer"];

function today(): string {
  const d = new Date();
  return `${d.getFullYear()}-${`${d.getMonth() + 1}`.padStart(2, "0")}-${`${d.getDate()}`.padStart(2, "0")}`;
}

/** Settle all or part of an unpaid expense. The server revalidates the balance. */
export function MarkExpensePaidDialog({ expense, onDone }: { expense: ExpenseRow; onDone: () => void }) {
  const outstanding = expense.amountMinor - expense.amountPaidMinor;
  const [open, setOpen] = useState(false);
  const [amount, setAmount] = useState(String(fromMinorUnits(outstanding, expense.currency)));
  const [method, setMethod] = useState(expense.paymentMethod ?? "Cash");
  const [paidOn, setPaidOn] = useState(today);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const newKey = () => (typeof crypto !== "undefined" && "randomUUID" in crypto ? crypto.randomUUID() : `${Date.now()}`);
  const [idempotencyKey, setIdempotencyKey] = useState(newKey);

  async function save() {
    const minor = toMinorUnits(amount, expense.currency);
    if (minor <= 0 || minor > outstanding) {
      setError(`Enter an amount between ₹1 and ${formatCurrency(outstanding, expense.currency)}.`);
      return;
    }
    setBusy(true);
    setError(null);
    try {
      await getFinanceService().recordExpensePayment({
        expenseId: expense.id,
        amountMinor: minor,
        paidOn,
        paymentMethod: method,
        idempotencyKey,
      });
      setOpen(false);
      onDone();
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Unable to record this payment.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <Button type="button" size="sm" onClick={() => setOpen(true)}>
        Mark paid
      </Button>
      <Dialog
        open={open}
        onOpenChange={(next) => {
          if (next) {
            setIdempotencyKey(newKey());
            setOpen(true);
          } else {
            setOpen(false);
            setError(null);
          }
        }}
      >
        <DialogContent className="sm:max-w-sm">
          <DialogHeader>
            <DialogTitle>Record expense payment</DialogTitle>
            <DialogDescription>
              {expense.vendor ?? expense.categoryName} · {formatCurrency(outstanding, expense.currency)} outstanding
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-3">
            <div className="space-y-1.5">
              <Label htmlFor="mep-amount" className="text-xs font-medium">
                Amount (₹)
              </Label>
              <Input id="mep-amount" inputMode="decimal" value={amount} onChange={(e) => setAmount(e.target.value)} />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="mep-date" className="text-xs font-medium">
                Paid on
              </Label>
              <Input id="mep-date" type="date" value={paidOn} onChange={(e) => setPaidOn(e.target.value)} />
            </div>
            <div className="space-y-1.5">
              <Label className="text-xs font-medium">Method</Label>
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
            </div>
            {error && (
              <p role="alert" className="text-sm text-destructive">
                {error}
              </p>
            )}
          </div>

          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => setOpen(false)} disabled={busy}>
              Cancel
            </Button>
            <Button type="button" onClick={save} disabled={busy}>
              {busy ? "Saving…" : "Record payment"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}
