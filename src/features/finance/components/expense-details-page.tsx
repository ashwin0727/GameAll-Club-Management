"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { ChevronRight, Undo2 } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { Skeleton } from "@/components/ui/skeleton";
import { cn } from "@/lib/utils";
import { createClient } from "@/lib/supabase/client";
import { formatCurrency, fromMinorUnits, toMinorUnits } from "@/features/pricing/money";
import { getFinanceService } from "@/services/finance";
import { MarkExpensePaidDialog } from "@/features/finance/components/mark-expense-paid-dialog";
import { ServiceError } from "@/services/shared/service-error";
import type { ExpenseCategory, ExpenseDetail, ExpenseRow } from "@/features/finance/types";

function fmtDate(iso: string | null): string {
  if (!iso) return "—";
  return new Date(iso).toLocaleDateString("en-IN", { day: "2-digit", month: "short", year: "numeric" });
}

function paymentTone(status: ExpenseDetail["paymentStatus"]): "success" | "warning" | "secondary" {
  if (status === "PAID") return "success";
  if (status === "PARTIAL") return "warning";
  return "secondary";
}

export function ExpenseDetailsPage({ expenseId }: { expenseId: string }) {
  const [expense, setExpense] = useState<ExpenseDetail | null>(null);
  const [state, setState] = useState<"loading" | "ready" | "notfound" | "error">("loading");
  const [error, setError] = useState<string | null>(null);
  const [voiding, setVoiding] = useState(false);
  const [receiptUrl, setReceiptUrl] = useState<string | null>(null);

  const load = useCallback(async () => {
    setError(null);
    try {
      const detail = await getFinanceService().getExpense(expenseId);
      if (!detail) {
        setState("notfound");
        return;
      }
      setExpense(detail);
      setState("ready");
      if (detail.receiptPath) {
        const { data } = await createClient().storage.from("expense-receipts").createSignedUrl(detail.receiptPath, 300);
        setReceiptUrl(data?.signedUrl ?? null);
      }
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Unable to load this expense.");
      setState("error");
    }
  }, [expenseId]);

  useEffect(() => {
    void load();
  }, [load]);

  async function voidExpense() {
    if (!expense) return;
    setVoiding(true);
    try {
      await getFinanceService().voidExpense(expense.id);
      await load();
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Unable to void this expense.");
    } finally {
      setVoiding(false);
    }
  }

  if (state === "loading") return <Skeleton className="h-96 w-full rounded-xl" />;
  if (state === "notfound") return <p className="text-sm text-muted-foreground">This expense could not be found.</p>;
  if (state === "error" || !expense)
    return (
      <div className="space-y-3">
        <p className="text-sm text-destructive">{error ?? "Unable to load this expense."}</p>
        <Button variant="outline" onClick={() => void load()}>
          Try again
        </Button>
      </div>
    );

  const outstanding = expense.amountMinor - expense.amountPaidMinor;
  const asRow: ExpenseRow = {
    id: expense.id,
    categoryId: expense.categoryId,
    categoryName: expense.categoryName,
    amountMinor: expense.amountMinor,
    amountPaidMinor: expense.amountPaidMinor,
    currency: expense.currency,
    paymentMethod: expense.paymentMethod,
    paymentStatus: expense.paymentStatus,
    spentOn: expense.spentOn,
    dueOn: expense.dueOn,
    vendor: expense.vendor,
    reference: expense.reference,
    notes: expense.notes,
    receiptPath: expense.receiptPath,
    status: expense.status,
    createdByName: expense.createdByName,
  };

  return (
    <div className="space-y-4">
      <nav aria-label="Breadcrumb" className="flex items-center gap-1 text-xs text-muted-foreground">
        <Link href="/finance" className="hover:text-foreground">
          Finance
        </Link>
        <ChevronRight className="h-3 w-3" aria-hidden />
        <Link href="/finance/expenses" className="hover:text-foreground">
          Expenses
        </Link>
        <ChevronRight className="h-3 w-3" aria-hidden />
        <span className="text-foreground">EXP-{expense.id.slice(0, 8).toUpperCase()}</span>
      </nav>

      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <div className="flex items-center gap-2">
            <h1 className="text-xl font-semibold">{expense.vendor ?? expense.categoryName}</h1>
            {expense.status === "VOID" ? (
              <Badge variant="secondary">Void</Badge>
            ) : (
              <Badge variant={paymentTone(expense.paymentStatus)}>
                {expense.paymentStatus === "PARTIAL" ? "Partial" : expense.paymentStatus === "PENDING" ? "Unpaid" : "Paid"}
              </Badge>
            )}
          </div>
          <p className="text-sm text-muted-foreground">
            {expense.categoryName} · {fmtDate(expense.spentOn)}
          </p>
        </div>
        {expense.status !== "VOID" && (
          <div className="flex flex-wrap gap-2">
            {expense.paymentStatus !== "PAID" && <MarkExpensePaidDialog expense={asRow} onDone={() => void load()} />}
            <EditExpenseDialog expense={expense} onSaved={() => void load()} />
            <Button type="button" variant="outline" size="sm" disabled={voiding} onClick={voidExpense}>
              <Undo2 className="h-3.5 w-3.5" aria-hidden /> {voiding ? "Voiding…" : "Void"}
            </Button>
          </div>
        )}
      </div>

      {error && <p className="text-sm text-destructive">{error}</p>}

      <div className="grid gap-4 lg:grid-cols-3">
        <Card className="space-y-3 p-4 lg:col-span-2">
          <h2 className="text-sm font-semibold">Overview</h2>
          <dl className="grid grid-cols-2 gap-x-4 gap-y-3 text-sm">
            <Detail label="Amount" value={formatCurrency(expense.amountMinor, expense.currency)} />
            <Detail label="Paid" value={formatCurrency(expense.amountPaidMinor, expense.currency)} />
            <Detail
              label="Outstanding"
              value={outstanding > 0 ? formatCurrency(outstanding, expense.currency) : "—"}
              accent={outstanding > 0 ? "text-warning" : undefined}
            />
            <Detail label="Tax / GST" value={expense.taxMinor ? formatCurrency(expense.taxMinor, expense.currency) : "—"} />
            <Detail label="Payment method" value={expense.paymentMethod ?? "—"} />
            <Detail label="Due date" value={fmtDate(expense.dueOn)} />
            <Detail label="Vendor / Payee" value={expense.vendor ?? "—"} />
            <Detail label="Reference" value={expense.reference ?? "—"} />
            <Detail label="Recorded by" value={expense.createdByName ?? "—"} />
            <Detail label="Recorded at" value={fmtDate(expense.createdAt)} />
          </dl>
          {expense.notes && (
            <div>
              <dt className="text-xs text-muted-foreground">Notes</dt>
              <dd className="mt-0.5 whitespace-pre-wrap text-sm">{expense.notes}</dd>
            </div>
          )}
          {expense.voidReason && (
            <p className="text-xs text-muted-foreground">Void reason: {expense.voidReason}</p>
          )}
          {expense.sourceMaintenanceTicketId && (
            <p className="text-xs text-muted-foreground">
              Posted from{" "}
              <Link
                href={`/maintenance/tickets/${expense.sourceMaintenanceTicketId}`}
                className="font-medium text-foreground hover:underline"
              >
                maintenance ticket
              </Link>
              .
            </p>
          )}
          {expense.receiptPath && (
            <p className="text-xs">
              {receiptUrl ? (
                <a href={receiptUrl} target="_blank" rel="noreferrer" className="font-medium text-primary hover:underline">
                  View receipt
                </a>
              ) : (
                <span className="text-muted-foreground">Receipt attached</span>
              )}
            </p>
          )}
        </Card>

        <Card className="space-y-3 p-4">
          <h2 className="text-sm font-semibold">Payment history</h2>
          {expense.payments.length === 0 ? (
            <p className="text-sm text-muted-foreground">No payments recorded yet.</p>
          ) : (
            <ul className="space-y-2 text-sm">
              {expense.payments.map((p) => (
                <li key={p.id} className="flex items-center justify-between border-b border-border pb-2 last:border-0">
                  <div>
                    <span className="font-medium tabular-nums">{formatCurrency(p.amountMinor, expense.currency)}</span>
                    <span className="block text-xs text-muted-foreground">
                      {fmtDate(p.paidOn)}
                      {p.paymentMethod ? ` · ${p.paymentMethod}` : ""}
                    </span>
                  </div>
                </li>
              ))}
            </ul>
          )}
        </Card>
      </div>
    </div>
  );
}

function Detail({ label, value, accent }: { label: string; value: string; accent?: string }) {
  return (
    <div>
      <dt className="text-xs text-muted-foreground">{label}</dt>
      <dd className={cn("mt-0.5 font-medium tabular-nums", accent)}>{value}</dd>
    </div>
  );
}

function EditExpenseDialog({ expense, onSaved }: { expense: ExpenseDetail; onSaved: () => void }) {
  const [open, setOpen] = useState(false);
  const [categories, setCategories] = useState<ExpenseCategory[]>([]);
  const [categoryId, setCategoryId] = useState(expense.categoryId);
  const [amount, setAmount] = useState(String(fromMinorUnits(expense.amountMinor, expense.currency)));
  const [spentOn, setSpentOn] = useState(expense.spentOn.slice(0, 10));
  const [vendor, setVendor] = useState(expense.vendor ?? "");
  const [reference, setReference] = useState(expense.reference ?? "");
  const [notes, setNotes] = useState(expense.notes ?? "");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!open) return;
    getFinanceService()
      .listExpenseCategories(expense.facilityId)
      .then(setCategories)
      .catch(() => setError("Unable to load categories."));
  }, [open, expense.facilityId]);

  async function save() {
    const minor = toMinorUnits(amount, expense.currency);
    if (minor <= 0) {
      setError("Enter an amount greater than zero.");
      return;
    }
    if (minor < expense.amountPaidMinor) {
      setError("The total cannot be less than what has already been paid.");
      return;
    }
    setBusy(true);
    setError(null);
    try {
      await getFinanceService().updateExpense({
        expenseId: expense.id,
        categoryId,
        amountMinor: minor,
        spentOn,
        vendor: vendor.trim() || null,
        reference: reference.trim() || null,
        notes: notes.trim() || null,
      });
      setOpen(false);
      onSaved();
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Unable to save changes.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <Button type="button" variant="outline" size="sm" onClick={() => setOpen(true)}>
        Edit
      </Button>
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>Edit expense</DialogTitle>
          </DialogHeader>
          <div className="space-y-3">
            <div className="space-y-1.5">
              <Label className="text-xs font-medium">Category</Label>
              <Select value={categoryId} onValueChange={setCategoryId}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {categories.map((c) => (
                    <SelectItem key={c.id} value={c.id}>
                      {c.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-1.5">
                <Label htmlFor="ee-amount" className="text-xs font-medium">
                  Amount (₹)
                </Label>
                <Input id="ee-amount" inputMode="decimal" value={amount} onChange={(e) => setAmount(e.target.value)} />
              </div>
              <div className="space-y-1.5">
                <Label htmlFor="ee-date" className="text-xs font-medium">
                  Expense date
                </Label>
                <Input id="ee-date" type="date" value={spentOn} onChange={(e) => setSpentOn(e.target.value)} />
              </div>
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-1.5">
                <Label htmlFor="ee-vendor" className="text-xs font-medium">
                  Vendor / Payee
                </Label>
                <Input id="ee-vendor" value={vendor} onChange={(e) => setVendor(e.target.value)} />
              </div>
              <div className="space-y-1.5">
                <Label htmlFor="ee-ref" className="text-xs font-medium">
                  Reference
                </Label>
                <Input id="ee-ref" value={reference} onChange={(e) => setReference(e.target.value)} />
              </div>
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="ee-notes" className="text-xs font-medium">
                Notes
              </Label>
              <Textarea id="ee-notes" rows={2} value={notes} onChange={(e) => setNotes(e.target.value)} />
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
              {busy ? "Saving…" : "Save changes"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}
