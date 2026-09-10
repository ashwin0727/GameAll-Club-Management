"use client";

import { useEffect, useState } from "react";
import { Plus } from "lucide-react";
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
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { toMinorUnits } from "@/features/pricing/money";
import { getFacilityService } from "@/services/facility";
import { getFinanceService } from "@/services/finance";
import { ServiceError } from "@/services/shared/service-error";
import type { ExpenseCategory, ExpensePaymentStatus } from "@/features/finance/types";

const METHODS = ["Cash", "UPI", "Card", "Bank Transfer"];

function today(): string {
  const now = new Date();
  return `${now.getFullYear()}-${`${now.getMonth() + 1}`.padStart(2, "0")}-${`${now.getDate()}`.padStart(2, "0")}`;
}

/**
 * Records an expense — the one kind of transaction an owner enters by hand.
 * Income arrives through a payment against a booking or membership and is
 * never typed in here, which is what keeps the ledger traceable.
 */
export function AddExpenseDialog({ onCreated }: { onCreated?: () => void }) {
  const [open, setOpen] = useState(false);
  const [facilityId, setFacilityId] = useState<string | null>(null);
  const [categories, setCategories] = useState<ExpenseCategory[]>([]);

  const [categoryId, setCategoryId] = useState("");
  const [amount, setAmount] = useState("");
  const [taxAmount, setTaxAmount] = useState("");
  const [method, setMethod] = useState("Cash");
  const [spentOn, setSpentOn] = useState(today);
  const [dueOn, setDueOn] = useState("");
  const [vendor, setVendor] = useState("");
  const [reference, setReference] = useState("");
  const [notes, setNotes] = useState("");
  const [paymentStatus, setPaymentStatus] = useState<ExpensePaymentStatus>("PAID");
  const [amountPaid, setAmountPaid] = useState("");

  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!open) return;
    let cancelled = false;
    getFacilityService()
      .getFacility()
      .then((facility) => {
        if (cancelled || !facility) return;
        setFacilityId(facility.id);
        return getFinanceService().listExpenseCategories(facility.id);
      })
      .then((list) => {
        if (cancelled || !list) return;
        setCategories(list);
        setCategoryId((current) => current || list[0]?.id || "");
      })
      .catch(() => !cancelled && setError("Unable to load expense categories."));
    return () => {
      cancelled = true;
    };
  }, [open]);

  function reset() {
    setAmount("");
    setTaxAmount("");
    setVendor("");
    setReference("");
    setNotes("");
    setSpentOn(today());
    setDueOn("");
    setPaymentStatus("PAID");
    setAmountPaid("");
    setError(null);
  }

  async function save() {
    if (!facilityId || busy) return;

    const rupees = Number(amount);
    if (!Number.isFinite(rupees) || rupees <= 0) {
      setError("Enter an amount greater than zero.");
      return;
    }
    if (!categoryId) {
      setError("Choose a category.");
      return;
    }
    const amountMinor = toMinorUnits(amount, "INR");
    let amountPaidMinor: number | null = null;
    if (paymentStatus === "PARTIAL") {
      amountPaidMinor = toMinorUnits(amountPaid || "0", "INR");
      if (amountPaidMinor <= 0 || amountPaidMinor >= amountMinor) {
        setError("A partial payment must be more than zero and less than the total.");
        return;
      }
    }

    setBusy(true);
    setError(null);
    try {
      await getFinanceService().createExpense({
        facilityId,
        categoryId,
        amountMinor,
        spentOn,
        paymentMethod: method,
        vendor: vendor.trim() || null,
        reference: reference.trim() || null,
        notes: notes.trim() || null,
        paymentStatus,
        amountPaidMinor,
        taxMinor: taxAmount ? toMinorUnits(taxAmount, "INR") : null,
        dueOn: paymentStatus !== "PAID" && dueOn ? dueOn : null,
      });
      setOpen(false);
      reset();
      onCreated?.();
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Unable to record this expense. Please try again.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <Button type="button" size="sm" className="min-h-9" onClick={() => setOpen(true)}>
        <Plus className="h-4 w-4" aria-hidden /> Add Expense
      </Button>

      <Dialog open={open} onOpenChange={(next) => (next ? setOpen(true) : (setOpen(false), reset()))}>
        <DialogContent className="max-h-[85vh] overflow-y-auto sm:max-w-md">
          <DialogHeader>
            <DialogTitle>Add expense</DialogTitle>
            <DialogDescription>
              Money the facility spent. Income is recorded against its booking or membership, not here.
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-3">
            <Field id="expense-category" label="Category">
              <Select value={categoryId} onValueChange={setCategoryId}>
                <SelectTrigger id="expense-category">
                  <SelectValue placeholder="Choose a category" />
                </SelectTrigger>
                <SelectContent>
                  {categories.map((category) => (
                    <SelectItem key={category.id} value={category.id}>
                      {category.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </Field>

            <div className="grid grid-cols-2 gap-3">
              <Field id="expense-amount" label="Amount (₹)">
                <Input
                  id="expense-amount"
                  inputMode="decimal"
                  value={amount}
                  onChange={(e) => setAmount(e.target.value)}
                  placeholder="0"
                />
              </Field>
              <Field id="expense-date" label="Expense date">
                <Input id="expense-date" type="date" value={spentOn} onChange={(e) => setSpentOn(e.target.value)} />
              </Field>
            </div>

            <Field id="expense-tax" label="Tax / GST (₹, optional)">
              <Input
                id="expense-tax"
                inputMode="decimal"
                value={taxAmount}
                onChange={(e) => setTaxAmount(e.target.value)}
                placeholder="0"
              />
            </Field>

            <Field id="expense-status" label="Payment status">
              <div className="flex flex-wrap gap-2">
                {(["PAID", "PARTIAL", "PENDING"] as ExpensePaymentStatus[]).map((s) => (
                  <Button
                    key={s}
                    type="button"
                    size="sm"
                    variant={s === paymentStatus ? "default" : "outline"}
                    onClick={() => setPaymentStatus(s)}
                  >
                    {s === "PARTIAL" ? "Partial" : s === "PENDING" ? "Unpaid" : "Paid"}
                  </Button>
                ))}
              </div>
            </Field>

            {paymentStatus === "PARTIAL" && (
              <Field id="expense-paid" label="Amount already paid (₹)">
                <Input
                  id="expense-paid"
                  inputMode="decimal"
                  value={amountPaid}
                  onChange={(e) => setAmountPaid(e.target.value)}
                  placeholder="0"
                />
              </Field>
            )}

            {paymentStatus !== "PAID" && (
              <Field id="expense-due" label="Due date (optional)">
                <Input id="expense-due" type="date" value={dueOn} onChange={(e) => setDueOn(e.target.value)} />
              </Field>
            )}

            <Field id="expense-method" label="Payment method">
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

            <div className="grid grid-cols-2 gap-3">
              <Field id="expense-vendor" label="Vendor / Payee (optional)">
                <Input id="expense-vendor" value={vendor} onChange={(e) => setVendor(e.target.value)} />
              </Field>
              <Field id="expense-reference" label="Reference (optional)">
                <Input
                  id="expense-reference"
                  value={reference}
                  onChange={(e) => setReference(e.target.value)}
                  placeholder="INV-1023"
                />
              </Field>
            </div>

            <Field id="expense-notes" label="Notes (optional)">
              <Textarea id="expense-notes" rows={2} value={notes} onChange={(e) => setNotes(e.target.value)} />
            </Field>

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
              {busy ? "Saving…" : "Save expense"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}

function Field({ id, label, children }: { id: string; label: string; children: React.ReactNode }) {
  return (
    <div className="space-y-1.5">
      <Label htmlFor={id} className="text-xs font-medium">
        {label}
      </Label>
      {children}
    </div>
  );
}
