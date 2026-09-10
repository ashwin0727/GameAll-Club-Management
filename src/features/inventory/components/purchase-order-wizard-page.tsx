"use client";

import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { cn } from "@/lib/utils";
import { ServiceError } from "@/services/shared/service-error";
import { getInventoryService } from "@/services/inventory";
import { toMinorUnits } from "@/features/pricing/money";
import { usePermissionContext } from "@/features/auth/context/permission-provider";
import { PermissionDenied } from "@/features/staff/components/permission-denied";
import { PageHeader, money } from "@/features/inventory/components/shared";
import type { ItemRow, VendorRow } from "@/features/inventory/types";

const STEPS = ["Vendor & Dates", "Line Items", "Review"] as const;

interface Line {
  key: string;
  itemId: string;
  qty: string;
  unitCost: string;
  tax: string;
  discount: string;
}

function blankLine(): Line {
  return { key: crypto.randomUUID(), itemId: "", qty: "1", unitCost: "", tax: "0", discount: "0" };
}

export function PurchaseOrderWizardPage() {
  const perms = usePermissionContext();
  const router = useRouter();
  const facilityId = perms?.facilityId ?? null;

  const [step, setStep] = useState(0);
  const [vendors, setVendors] = useState<VendorRow[]>([]);
  const [items, setItems] = useState<ItemRow[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const [vendorId, setVendorId] = useState("");
  const [orderDate, setOrderDate] = useState(() => new Date().toISOString().slice(0, 10));
  const [expectedDelivery, setExpectedDelivery] = useState("");
  const [reference, setReference] = useState("");
  const [notes, setNotes] = useState("");
  const [lines, setLines] = useState<Line[]>([blankLine()]);

  useEffect(() => {
    if (!facilityId) return;
    getInventoryService()
      .listVendors({ facilityId, filters: { status: "ACTIVE" }, limit: 200 })
      .then((v) => setVendors(v.vendors))
      .catch(() => setVendors([]));
    getInventoryService()
      .listItems({ facilityId, filters: { status: "ACTIVE" }, limit: 500 })
      .then((r) => setItems(r.items))
      .catch(() => setItems([]));
  }, [facilityId]);

  const totals = useMemo(() => {
    let subtotal = 0;
    let tax = 0;
    let discount = 0;
    for (const l of lines) {
      if (!l.itemId) continue;
      const q = Number(l.qty) || 0;
      const c = l.unitCost.trim() ? toMinorUnits(l.unitCost, "INR") : 0;
      const t = l.tax.trim() ? toMinorUnits(l.tax, "INR") : 0;
      const d = l.discount.trim() ? toMinorUnits(l.discount, "INR") : 0;
      subtotal += q * c;
      tax += t;
      discount += d;
    }
    return { subtotal, tax, discount, total: subtotal + tax - discount };
  }, [lines]);

  if (!perms?.can("PURCHASE_CREATE")) {
    return <PermissionDenied message="You don't have permission to create purchase orders." />;
  }

  function setLine(key: string, patch: Partial<Line>) {
    setLines((ls) => ls.map((l) => (l.key === key ? { ...l, ...patch } : l)));
  }

  function next() {
    setError(null);
    if (step === 0 && !vendorId) return setError("Choose a vendor.");
    if (step === 1) {
      const filled = lines.filter((l) => l.itemId);
      if (filled.length === 0) return setError("Add at least one line item.");
      for (const l of filled) {
        if ((Number(l.qty) || 0) <= 0) return setError("Every line needs a quantity greater than zero.");
        if (!l.unitCost.trim() || toMinorUnits(l.unitCost, "INR") < 0) return setError("Every line needs a unit cost.");
      }
      if (totals.total <= 0) return setError("The purchase order total must be greater than zero.");
    }
    setStep((s) => Math.min(s + 1, STEPS.length - 1));
  }

  async function submit() {
    if (!facilityId) return;
    setBusy(true);
    setError(null);
    try {
      const id = await getInventoryService().createPurchaseOrder({
        facilityId,
        vendorId,
        orderDate,
        expectedDelivery: expectedDelivery || null,
        reference: reference.trim() || null,
        notes: notes.trim() || null,
        lines: lines
          .filter((l) => l.itemId)
          .map((l) => ({
            itemId: l.itemId,
            quantity: Number(l.qty) || 0,
            unitCostMinor: toMinorUnits(l.unitCost, "INR"),
            taxMinor: l.tax.trim() ? toMinorUnits(l.tax, "INR") : 0,
            discountMinor: l.discount.trim() ? toMinorUnits(l.discount, "INR") : 0,
          })),
      });
      router.push(`/inventory/purchase-orders/${id}`);
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Could not create the purchase order.");
      setBusy(false);
    }
  }

  const vendorName = vendors.find((v) => v.id === vendorId)?.name ?? "—";

  return (
    <div className="mx-auto max-w-3xl space-y-4">
      <PageHeader title="New Purchase Order" subtitle="Created as a draft — place it to record the expense." />

      <ol className="flex flex-wrap gap-2 text-xs">
        {STEPS.map((s, i) => (
          <li
            key={s}
            className={cn(
              "rounded-full border px-3 py-1 font-medium",
              i === step ? "border-primary bg-primary/10 text-primary" : "border-border text-muted-foreground",
            )}
          >
            {i + 1}. {s}
          </li>
        ))}
      </ol>

      <Card className="space-y-4 p-5">
        {step === 0 && (
          <>
            <div className="space-y-1.5">
              <Label htmlFor="po-vendor">Vendor</Label>
              <Select value={vendorId} onValueChange={setVendorId}>
                <SelectTrigger id="po-vendor">
                  <SelectValue placeholder="Select a vendor" />
                </SelectTrigger>
                <SelectContent>
                  {vendors.map((v) => (
                    <SelectItem key={v.id} value={v.id}>
                      {v.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-1.5">
                <Label htmlFor="po-date">Order date</Label>
                <Input id="po-date" type="date" value={orderDate} onChange={(e) => setOrderDate(e.target.value)} />
              </div>
              <div className="space-y-1.5">
                <Label htmlFor="po-eta">Expected delivery (optional)</Label>
                <Input id="po-eta" type="date" value={expectedDelivery} onChange={(e) => setExpectedDelivery(e.target.value)} />
              </div>
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="po-ref">Reference / invoice no. (optional)</Label>
              <Input id="po-ref" value={reference} onChange={(e) => setReference(e.target.value)} />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="po-notes">Notes (optional)</Label>
              <Textarea id="po-notes" rows={2} value={notes} onChange={(e) => setNotes(e.target.value)} />
            </div>
          </>
        )}

        {step === 1 && (
          <div className="space-y-3">
            {lines.map((l) => (
              <div key={l.key} className="grid grid-cols-12 gap-2">
                <div className="col-span-12 sm:col-span-4">
                  <Select value={l.itemId} onValueChange={(v) => setLine(l.key, { itemId: v })}>
                    <SelectTrigger>
                      <SelectValue placeholder="Item" />
                    </SelectTrigger>
                    <SelectContent>
                      {items.map((it) => (
                        <SelectItem key={it.id} value={it.id}>
                          {it.name} ({it.sku})
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
                <Input className="col-span-3 sm:col-span-2" type="number" min="0" step="1" placeholder="Qty" value={l.qty} onChange={(e) => setLine(l.key, { qty: e.target.value })} />
                <Input className="col-span-3 sm:col-span-2" type="number" min="0" step="0.01" placeholder="Unit ₹" value={l.unitCost} onChange={(e) => setLine(l.key, { unitCost: e.target.value })} />
                <Input className="col-span-2 sm:col-span-1" type="number" min="0" step="0.01" placeholder="Tax" value={l.tax} onChange={(e) => setLine(l.key, { tax: e.target.value })} />
                <Input className="col-span-2 sm:col-span-2" type="number" min="0" step="0.01" placeholder="Disc" value={l.discount} onChange={(e) => setLine(l.key, { discount: e.target.value })} />
                <button
                  type="button"
                  className="col-span-2 sm:col-span-1 flex items-center justify-center text-muted-foreground hover:text-destructive"
                  onClick={() => setLines((ls) => (ls.length > 1 ? ls.filter((x) => x.key !== l.key) : ls))}
                  aria-label="Remove line"
                >
                  <Trash2 className="h-4 w-4" />
                </button>
              </div>
            ))}
            <Button type="button" variant="outline" size="sm" onClick={() => setLines((ls) => [...ls, blankLine()])}>
              Add line
            </Button>
            <TotalsBlock {...totals} />
          </div>
        )}

        {step === 2 && (
          <div className="space-y-3 text-sm">
            <dl className="grid grid-cols-2 gap-x-4 gap-y-2">
              <dt className="text-muted-foreground">Vendor</dt>
              <dd className="font-medium">{vendorName}</dd>
              <dt className="text-muted-foreground">Order date</dt>
              <dd className="font-medium">{orderDate}</dd>
              <dt className="text-muted-foreground">Expected delivery</dt>
              <dd className="font-medium">{expectedDelivery || "—"}</dd>
              <dt className="text-muted-foreground">Reference</dt>
              <dd className="font-medium">{reference || "—"}</dd>
            </dl>
            <div className="rounded-lg border border-border">
              {lines
                .filter((l) => l.itemId)
                .map((l) => {
                  const it = items.find((x) => x.id === l.itemId);
                  const lineTotal =
                    (Number(l.qty) || 0) * (l.unitCost.trim() ? toMinorUnits(l.unitCost, "INR") : 0) +
                    (l.tax.trim() ? toMinorUnits(l.tax, "INR") : 0) -
                    (l.discount.trim() ? toMinorUnits(l.discount, "INR") : 0);
                  return (
                    <div key={l.key} className="flex justify-between border-b border-border p-2 last:border-0">
                      <span>
                        {it?.name} × {l.qty}
                      </span>
                      <span className="tabular-nums">{money(lineTotal)}</span>
                    </div>
                  );
                })}
            </div>
            <TotalsBlock {...totals} />
          </div>
        )}

        {error && <p className="text-sm text-destructive">{error}</p>}

        <div className="flex items-center justify-between border-t border-border pt-4">
          {step === 0 ? (
            <Button asChild variant="outline">
              <Link href="/inventory/purchase-orders">Cancel</Link>
            </Button>
          ) : (
            <Button variant="outline" onClick={() => setStep((s) => s - 1)} disabled={busy}>
              Back
            </Button>
          )}
          {step < STEPS.length - 1 ? (
            <Button onClick={next}>Continue</Button>
          ) : (
            <Button onClick={() => void submit()} disabled={busy}>
              {busy ? "Creating…" : "Create Draft"}
            </Button>
          )}
        </div>
      </Card>
    </div>
  );
}

function TotalsBlock({ subtotal, tax, discount, total }: { subtotal: number; tax: number; discount: number; total: number }) {
  return (
    <dl className="ml-auto w-56 space-y-1 text-sm">
      <Line2 label="Subtotal" value={money(subtotal)} />
      <Line2 label="Tax" value={money(tax)} />
      <Line2 label="Discount" value={`− ${money(discount)}`} />
      <div className="flex justify-between border-t border-border pt-1 font-semibold">
        <dt>Total</dt>
        <dd className="tabular-nums">{money(total)}</dd>
      </div>
    </dl>
  );
}

function Line2({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex justify-between">
      <dt className="text-muted-foreground">{label}</dt>
      <dd className="tabular-nums">{value}</dd>
    </div>
  );
}
