"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
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
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { ServiceError } from "@/services/shared/service-error";
import { getInventoryService } from "@/services/inventory";
import { toMinorUnits } from "@/features/pricing/money";
import { usePermissionContext } from "@/features/auth/context/permission-provider";
import type { PurchaseOrderDetail } from "@/features/inventory/types";
import {
  ErrorState,
  PageHeader,
  TableSkeleton,
  Tabs,
  fmtDate,
  fmtDateTime,
  money,
  poPaymentBadge,
  poStatusBadge,
} from "@/features/inventory/components/shared";

const TABS = ["Overview", "Items Received"] as const;

export function PurchaseOrderDetailsPage({ poId }: { poId: string }) {
  const perms = usePermissionContext();
  const [tab, setTab] = useState<(typeof TABS)[number]>("Overview");
  const [po, setPo] = useState<PurchaseOrderDetail | null>(null);
  const [state, setState] = useState<"loading" | "ready" | "error">("loading");
  const [error, setError] = useState<string | null>(null);
  const [dialog, setDialog] = useState<"receive" | "pay" | "cancel" | null>(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    setState("loading");
    setError(null);
    try {
      setPo(await getInventoryService().getPurchaseOrder(poId));
      setState("ready");
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Unable to load this purchase order.");
      setState("error");
    }
  }, [poId]);

  useEffect(() => {
    void load();
  }, [load]);

  async function place() {
    setBusy(true);
    try {
      await getInventoryService().placePurchaseOrder(poId);
      await load();
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Could not place the order.");
    } finally {
      setBusy(false);
    }
  }

  if (state === "error") {
    return (
      <div className="space-y-4">
        <Back />
        <Card className="p-0">
          <ErrorState message={error ?? ""} onRetry={() => void load()} />
        </Card>
      </div>
    );
  }
  if (state === "loading" || !po) {
    return (
      <div className="space-y-4">
        <Back />
        <Card className="p-0">
          <TableSkeleton rows={6} />
        </Card>
      </div>
    );
  }

  const canPlace = (perms?.can("PURCHASE_CREATE") ?? false) && po.status === "DRAFT";
  const canReceive = (perms?.can("PURCHASE_RECEIVE") ?? false) && (po.status === "ORDERED" || po.status === "PARTIALLY_RECEIVED");
  const canPay =
    (perms?.can("FINANCE_RECORD_PAYMENT") ?? false) &&
    po.financials.expenseId != null &&
    po.financials.outstandingMinor > 0;
  const canCancel =
    (perms?.can("PURCHASE_CANCEL") ?? false) && po.status !== "RECEIVED" && po.status !== "CANCELLED";

  return (
    <div className="space-y-4">
      <Back />
      <PageHeader
        title={po.poNumber}
        subtitle={`${po.vendor.name} · ordered ${fmtDate(po.orderDate)}`}
        action={
          <div className="flex flex-wrap gap-2">
            {canPlace && (
              <Button size="sm" disabled={busy} onClick={() => void place()}>
                Place Order
              </Button>
            )}
            {canReceive && (
              <Button size="sm" onClick={() => setDialog("receive")}>
                Receive Goods
              </Button>
            )}
            {canPay && (
              <Button size="sm" variant="outline" onClick={() => setDialog("pay")}>
                Record Payment
              </Button>
            )}
            {canCancel && (
              <Button size="sm" variant="outline" onClick={() => setDialog("cancel")}>
                Cancel
              </Button>
            )}
          </div>
        }
      />

      <div className="flex flex-wrap items-center gap-2">
        {poStatusBadge(po.status)}
        {poPaymentBadge(po.financials.paymentStatus)}
        {po.status === "CANCELLED" && po.cancelReason && (
          <span className="text-sm text-muted-foreground">Cancelled: {po.cancelReason}</span>
        )}
      </div>

      <Tabs tabs={TABS} active={tab} onChange={setTab} />

      {tab === "Overview" && (
        <div className="grid gap-4 lg:grid-cols-3">
          <Card className="p-4 lg:col-span-2">
            <h2 className="text-sm font-semibold">Line Items</h2>
            <div className="mt-3 overflow-x-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Item</TableHead>
                    <TableHead className="text-right">Ordered</TableHead>
                    <TableHead className="text-right">Received</TableHead>
                    <TableHead className="text-right">Unit Cost</TableHead>
                    <TableHead className="text-right">Line Total</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {po.lines.map((l) => (
                    <TableRow key={l.id}>
                      <TableCell>
                        <Link href={`/inventory/items/${l.itemId}`} className="hover:underline">
                          {l.itemName}
                        </Link>
                        <span className="block text-xs text-muted-foreground">{l.sku}</span>
                      </TableCell>
                      <TableCell className="text-right tabular-nums">
                        {l.quantityOrdered} {l.unit}
                      </TableCell>
                      <TableCell className="text-right tabular-nums">{l.quantityReceived}</TableCell>
                      <TableCell className="text-right tabular-nums">{money(l.unitCostMinor)}</TableCell>
                      <TableCell className="text-right tabular-nums">{money(l.lineTotalMinor)}</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          </Card>

          <div className="space-y-4">
            <Card className="p-4">
              <h2 className="text-sm font-semibold">Financials</h2>
              <dl className="mt-3 space-y-1 text-sm">
                <Fin label="Subtotal" value={money(po.financials.subtotalMinor)} />
                <Fin label="Tax" value={money(po.financials.taxMinor)} />
                <Fin label="Discount" value={`− ${money(po.financials.discountMinor)}`} />
                <div className="flex justify-between border-t border-border pt-1 font-semibold">
                  <dt>Total</dt>
                  <dd className="tabular-nums">{money(po.financials.totalMinor)}</dd>
                </div>
                <Fin label="Paid" value={money(po.financials.paidMinor)} />
                <Fin label="Outstanding" value={money(po.financials.outstandingMinor)} />
              </dl>
              {po.financials.expenseId && (
                <Button asChild variant="link" size="sm" className="mt-2 px-0">
                  <Link href={`/finance/expenses/${po.financials.expenseId}`}>View linked expense</Link>
                </Button>
              )}
            </Card>

            <Card className="p-4">
              <h2 className="text-sm font-semibold">Details</h2>
              <dl className="mt-3 space-y-1 text-sm">
                <Fin label="Expected delivery" value={fmtDate(po.expectedDelivery)} />
                <Fin label="Reference" value={po.reference ?? "—"} />
              </dl>
              {po.invoicePath && (
                <InvoiceLink path={po.invoicePath} />
              )}
              {po.notes && <p className="mt-2 text-sm text-muted-foreground">{po.notes}</p>}
            </Card>
          </div>
        </div>
      )}

      {tab === "Items Received" && (
        <Card className="p-4">
          <h2 className="text-sm font-semibold">Receiving Progress</h2>
          <ul className="mt-3 space-y-3">
            {po.lines.map((l) => {
              const pct = l.quantityOrdered > 0 ? Math.round((l.quantityReceived / l.quantityOrdered) * 100) : 0;
              return (
                <li key={l.id} className="text-sm">
                  <div className="flex justify-between">
                    <span>{l.itemName}</span>
                    <span className="text-muted-foreground">
                      {l.quantityReceived} / {l.quantityOrdered} received · {l.quantityPending} pending
                    </span>
                  </div>
                  <div className="mt-1 h-2 rounded-full bg-muted">
                    <div className="h-2 rounded-full bg-primary" style={{ width: `${pct}%` }} />
                  </div>
                </li>
              );
            })}
          </ul>
          <h3 className="mt-6 text-sm font-semibold">Activity</h3>
          {po.events.length === 0 ? (
            <p className="mt-2 text-sm text-muted-foreground">Nothing recorded yet.</p>
          ) : (
            <ul className="mt-2 divide-y divide-border text-sm">
              {po.events.map((e) => (
                <li key={e.id} className="flex justify-between py-2">
                  <span>{e.summary}</span>
                  <span className="text-muted-foreground">
                    {e.actorName ? `${e.actorName} · ` : ""}
                    {fmtDateTime(e.createdAt)}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </Card>
      )}

      {dialog === "receive" && (
        <ReceiveDialog po={po} onClose={() => setDialog(null)} onDone={() => { setDialog(null); void load(); }} />
      )}
      {dialog === "pay" && (
        <PayDialog po={po} onClose={() => setDialog(null)} onDone={() => { setDialog(null); void load(); }} />
      )}
      {dialog === "cancel" && (
        <CancelDialog poId={po.id} onClose={() => setDialog(null)} onDone={() => { setDialog(null); void load(); }} />
      )}
    </div>
  );
}

function InvoiceLink({ path }: { path: string }) {
  const [url, setUrl] = useState<string | null>(null);
  useEffect(() => {
    getInventoryService().signedUrl(path).then(setUrl).catch(() => setUrl(null));
  }, [path]);
  if (!url) return null;
  return (
    <a href={url} target="_blank" rel="noreferrer" className="mt-2 block text-sm text-primary hover:underline">
      View invoice
    </a>
  );
}

function ReceiveDialog({
  po,
  onClose,
  onDone,
}: {
  po: PurchaseOrderDetail;
  onClose: () => void;
  onDone: () => void;
}) {
  const pending = po.lines.filter((l) => l.quantityPending > 0);
  const [qty, setQty] = useState<Record<string, string>>(
    Object.fromEntries(pending.map((l) => [l.id, String(l.quantityPending)])),
  );
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit() {
    const receipts = pending
      .map((l) => ({ lineId: l.id, quantity: Number(qty[l.id]) || 0 }))
      .filter((r) => r.quantity > 0);
    if (receipts.length === 0) {
      setError("Enter a quantity for at least one line.");
      return;
    }
    for (const r of receipts) {
      const line = pending.find((l) => l.id === r.lineId)!;
      if (r.quantity > line.quantityPending) {
        setError(`Cannot receive more than the ${line.quantityPending} pending for ${line.itemName}.`);
        return;
      }
    }
    setBusy(true);
    setError(null);
    try {
      await getInventoryService().receivePurchaseOrder(po.id, receipts);
      onDone();
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Could not record the receipt.");
      setBusy(false);
    }
  }

  return (
    <Dialog open onOpenChange={(v) => !v && !busy && onClose()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Receive goods</DialogTitle>
          <DialogDescription>Enter what arrived. This moves stock and updates the average cost.</DialogDescription>
        </DialogHeader>
        <div className="space-y-3">
          {pending.map((l) => (
            <div key={l.id} className="flex items-center justify-between gap-3">
              <span className="text-sm">
                {l.itemName}
                <span className="block text-xs text-muted-foreground">{l.quantityPending} pending</span>
              </span>
              <Input
                type="number"
                min="0"
                step="1"
                className="w-24"
                value={qty[l.id] ?? ""}
                onChange={(e) => setQty((q) => ({ ...q, [l.id]: e.target.value }))}
              />
            </div>
          ))}
          {error && <p className="text-sm text-destructive">{error}</p>}
        </div>
        <DialogFooter>
          <Button variant="outline" disabled={busy} onClick={onClose}>
            Cancel
          </Button>
          <Button disabled={busy} onClick={() => void submit()}>
            {busy ? "Saving…" : "Confirm Receipt"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function PayDialog({ po, onClose, onDone }: { po: PurchaseOrderDetail; onClose: () => void; onDone: () => void }) {
  const [amount, setAmount] = useState(String(po.financials.outstandingMinor / 100));
  const [method, setMethod] = useState("");
  const [reference, setReference] = useState("");
  const [paidOn, setPaidOn] = useState(() => new Date().toISOString().slice(0, 10));
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit() {
    const minor = amount.trim() ? toMinorUnits(amount, "INR") : 0;
    if (minor <= 0) {
      setError("Enter an amount greater than zero.");
      return;
    }
    if (minor > po.financials.outstandingMinor) {
      setError("That's more than the amount outstanding.");
      return;
    }
    setBusy(true);
    setError(null);
    try {
      await getInventoryService().recordPurchasePayment({
        poId: po.id,
        amountMinor: minor,
        paidOn,
        paymentMethod: method.trim() || null,
        reference: reference.trim() || null,
      });
      onDone();
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Could not record the payment.");
      setBusy(false);
    }
  }

  return (
    <Dialog open onOpenChange={(v) => !v && !busy && onClose()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Record payment</DialogTitle>
          <DialogDescription>
            {po.poNumber} · {money(po.financials.outstandingMinor)} outstanding
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-3">
          <div className="space-y-1.5">
            <Label htmlFor="pay-amt">Amount (₹)</Label>
            <Input id="pay-amt" type="number" min="0" step="0.01" value={amount} onChange={(e) => setAmount(e.target.value)} />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="pay-date">Paid on</Label>
            <Input id="pay-date" type="date" value={paidOn} onChange={(e) => setPaidOn(e.target.value)} />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="pay-method">Method (optional)</Label>
            <Input id="pay-method" value={method} onChange={(e) => setMethod(e.target.value)} placeholder="Bank transfer, UPI, cash…" />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="pay-ref">Reference (optional)</Label>
            <Input id="pay-ref" value={reference} onChange={(e) => setReference(e.target.value)} />
          </div>
          {error && <p className="text-sm text-destructive">{error}</p>}
        </div>
        <DialogFooter>
          <Button variant="outline" disabled={busy} onClick={onClose}>
            Cancel
          </Button>
          <Button disabled={busy} onClick={() => void submit()}>
            {busy ? "Saving…" : "Record Payment"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function CancelDialog({ poId, onClose, onDone }: { poId: string; onClose: () => void; onDone: () => void }) {
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit() {
    if (!reason.trim()) {
      setError("A reason is required.");
      return;
    }
    setBusy(true);
    setError(null);
    try {
      await getInventoryService().cancelPurchaseOrder(poId, reason.trim());
      onDone();
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Could not cancel the order.");
      setBusy(false);
    }
  }

  return (
    <Dialog open onOpenChange={(v) => !v && !busy && onClose()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Cancel purchase order</DialogTitle>
          <DialogDescription>
            This cannot be undone. If nothing has been received, the linked expense is voided.
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-3">
          <div className="space-y-1.5">
            <Label htmlFor="cancel-reason">Reason</Label>
            <Textarea id="cancel-reason" rows={3} value={reason} onChange={(e) => setReason(e.target.value)} />
          </div>
          {error && <p className="text-sm text-destructive">{error}</p>}
        </div>
        <DialogFooter>
          <Button variant="outline" disabled={busy} onClick={onClose}>
            Keep order
          </Button>
          <Button variant="destructive" disabled={busy} onClick={() => void submit()}>
            {busy ? "Cancelling…" : "Cancel Order"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function Back() {
  return (
    <Link href="/inventory/purchase-orders" className="text-sm text-muted-foreground hover:underline">
      ← Back to purchase orders
    </Link>
  );
}

function Fin({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex justify-between">
      <dt className="text-muted-foreground">{label}</dt>
      <dd className="tabular-nums">{value}</dd>
    </div>
  );
}
