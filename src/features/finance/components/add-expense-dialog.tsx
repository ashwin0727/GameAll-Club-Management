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
import { getFacilityService } from "@/services/facility";
import { getFinanceService } from "@/services/finance";
import { ServiceError } from "@/services/shared/service-error";
import type { ExpenseCategory } from "@/features/finance/types";

const METHODS = ["Cash", "UPI", "Card", "Bank Transfer"];

function today(): string {
  const now = new Date();
  return `${now.getFullYear()}-${`${now.getMonth() + 1}`.padStart(2, "0")}-${`${now.getDate()}`.padStart(2, "0")}`;
}

/**
 * Records an expense — the one kind of transaction an owner enters by hand.
 * Income arrives through a payment against a booking or membership, and is
 * never typed in here, which is what keeps the ledger traceable.
 */
export function AddExpenseDialog({ onCreated }: { onCreated?: () => void }) {
  const [open, setOpen] = useState(false);
  const [facilityId, setFacilityId] = useState<string | null>(null);
  const [categories, setCategories] = useState<ExpenseCategory[]>([]);

  const [categoryId, setCategoryId] = useState("");
  const [amount, setAmount] = useState("");
  const [method, setMethod] = useState("Cash");
  const [spentOn, setSpentOn] = useState(today);
  const [vendor, setVendor] = useState("");
  const [reference, setReference] = useState("");
  const [notes, setNotes] = useState("");

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
    setVendor("");
    setReference("");
    setNotes("");
    setSpentOn(today());
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

    setBusy(true);
    setError(null);
    try {
      await getFinanceService().createExpense({
        facilityId,
        categoryId,
        // Stored in minor units, like every other amount in the ledger.
        amountMinor: Math.round(rupees * 100),
        spentOn,
        paymentMethod: method,
        vendor: vendor.trim() || null,
        reference: reference.trim() || null,
        notes: notes.trim() || null,
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
        <Plus className="h-4 w-4" aria-hidden /> Add Transaction
      </Button>

      <Dialog open={open} onOpenChange={(next) => (next ? setOpen(true) : (setOpen(false), reset()))}>
        <DialogContent className="sm:max-w-md">
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
              <Field id="expense-date" label="Date">
                <Input
                  id="expense-date"
                  type="date"
                  value={spentOn}
                  onChange={(e) => setSpentOn(e.target.value)}
                />
              </Field>
            </div>

            <Field id="expense-method" label="Payment mode">
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
              <Field id="expense-vendor" label="Vendor (optional)">
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
