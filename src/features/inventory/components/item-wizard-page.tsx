"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
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
import type { CategoryRow, VendorRow } from "@/features/inventory/types";

const STEPS = ["Item Details", "Stock & Pricing", "Additional Information", "Review & Create"] as const;
const NONE = "NONE";

export function ItemWizardPage() {
  const perms = usePermissionContext();
  const router = useRouter();
  const facilityId = perms?.facilityId ?? null;

  const [step, setStep] = useState(0);
  const [categories, setCategories] = useState<CategoryRow[]>([]);
  const [vendors, setVendors] = useState<VendorRow[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const [name, setName] = useState("");
  const [sku, setSku] = useState("");
  const [categoryId, setCategoryId] = useState(NONE);
  const [unit, setUnit] = useState("piece");
  const [brand, setBrand] = useState("");
  const [reorderLevel, setReorderLevel] = useState("0");
  const [openingStock, setOpeningStock] = useState("0");
  const [defaultCost, setDefaultCost] = useState("");
  const [preferredVendorId, setPreferredVendorId] = useState(NONE);
  const [description, setDescription] = useState("");

  useEffect(() => {
    if (!facilityId) return;
    getInventoryService().listCategories(facilityId).then((c) => setCategories(c.filter((x) => x.isActive))).catch(() => setCategories([]));
    getInventoryService().listVendors({ facilityId, filters: { status: "ACTIVE" }, limit: 200 }).then((v) => setVendors(v.vendors)).catch(() => setVendors([]));
  }, [facilityId]);

  if (!perms?.can("INVENTORY_CREATE_ITEM")) {
    return <PermissionDenied message="You don't have permission to add items." />;
  }

  function next() {
    setError(null);
    if (step === 0) {
      if (!name.trim()) return setError("Enter an item name.");
      if (!sku.trim()) return setError("Enter a SKU.");
    }
    if (step === 1) {
      if (Number(reorderLevel) < 0 || !Number.isFinite(Number(reorderLevel))) return setError("Reorder level must be zero or more.");
      if (Number(openingStock) < 0 || !Number.isFinite(Number(openingStock))) return setError("Opening stock must be zero or more.");
    }
    setStep((s) => Math.min(s + 1, STEPS.length - 1));
  }

  async function submit() {
    if (!facilityId) return;
    setBusy(true);
    setError(null);
    try {
      const id = await getInventoryService().createItem({
        facilityId,
        name: name.trim(),
        sku: sku.trim(),
        categoryId: categoryId === NONE ? null : categoryId,
        unit: unit.trim() || "piece",
        reorderLevel: Number(reorderLevel) || 0,
        brand: brand.trim() || null,
        description: description.trim() || null,
        defaultUnitCostMinor: defaultCost.trim() ? toMinorUnits(defaultCost, "INR") : null,
        preferredVendorId: preferredVendorId === NONE ? null : preferredVendorId,
        openingStock: Number(openingStock) || 0,
      });
      router.push(`/inventory/items/${id}`);
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Could not create the item.");
      setBusy(false);
    }
  }

  const categoryName = categories.find((c) => c.id === categoryId)?.name ?? "None";
  const vendorName = vendors.find((v) => v.id === preferredVendorId)?.name ?? "None";

  return (
    <div className="mx-auto max-w-2xl space-y-4">
      <PageHeader title="Add Item" subtitle="Create a new inventory item." />

      <ol className="flex flex-wrap gap-2 text-xs">
        {STEPS.map((s, i) => (
          <li
            key={s}
            className={cn(
              "rounded-full border px-3 py-1 font-medium",
              i === step ? "border-primary bg-primary/10 text-primary" : i < step ? "border-border text-foreground" : "border-border text-muted-foreground",
            )}
          >
            {i + 1}. {s}
          </li>
        ))}
      </ol>

      <Card className="space-y-4 p-5">
        {step === 0 && (
          <>
            <Field label="Item name" htmlFor="it-name">
              <Input id="it-name" value={name} onChange={(e) => setName(e.target.value)} />
            </Field>
            <Field label="SKU / Code" htmlFor="it-sku">
              <Input id="it-sku" value={sku} onChange={(e) => setSku(e.target.value)} />
            </Field>
            <Field label="Brand (optional)" htmlFor="it-brand">
              <Input id="it-brand" value={brand} onChange={(e) => setBrand(e.target.value)} />
            </Field>
            <Field label="Category (optional)" htmlFor="it-cat">
              <Select value={categoryId} onValueChange={setCategoryId}>
                <SelectTrigger id="it-cat">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value={NONE}>None</SelectItem>
                  {categories.map((c) => (
                    <SelectItem key={c.id} value={c.id}>
                      {c.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </Field>
          </>
        )}

        {step === 1 && (
          <>
            <Field label="Unit of measure" htmlFor="it-unit">
              <Input id="it-unit" value={unit} onChange={(e) => setUnit(e.target.value)} placeholder="piece, box, litre…" />
            </Field>
            <Field label="Reorder level" htmlFor="it-reorder">
              <Input id="it-reorder" type="number" min="0" step="1" value={reorderLevel} onChange={(e) => setReorderLevel(e.target.value)} />
            </Field>
            <Field label="Opening stock" htmlFor="it-open">
              <Input id="it-open" type="number" min="0" step="1" value={openingStock} onChange={(e) => setOpeningStock(e.target.value)} />
            </Field>
            <Field label="Default unit cost (₹, optional)" htmlFor="it-cost">
              <Input id="it-cost" type="number" min="0" step="0.01" value={defaultCost} onChange={(e) => setDefaultCost(e.target.value)} />
            </Field>
            <p className="text-xs text-muted-foreground">
              Opening stock is valued at the default unit cost. Stock only moves afterwards through movements and receipts.
            </p>
          </>
        )}

        {step === 2 && (
          <>
            <Field label="Preferred vendor (optional)" htmlFor="it-vendor">
              <Select value={preferredVendorId} onValueChange={setPreferredVendorId}>
                <SelectTrigger id="it-vendor">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value={NONE}>None</SelectItem>
                  {vendors.map((v) => (
                    <SelectItem key={v.id} value={v.id}>
                      {v.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </Field>
            <Field label="Description (optional)" htmlFor="it-desc">
              <Textarea id="it-desc" rows={3} value={description} onChange={(e) => setDescription(e.target.value)} />
            </Field>
          </>
        )}

        {step === 3 && (
          <dl className="grid grid-cols-2 gap-x-4 gap-y-2 text-sm">
            <Review label="Name" value={name} />
            <Review label="SKU" value={sku} />
            <Review label="Brand" value={brand || "—"} />
            <Review label="Category" value={categoryName} />
            <Review label="Unit" value={unit} />
            <Review label="Reorder level" value={reorderLevel} />
            <Review label="Opening stock" value={openingStock} />
            <Review label="Default cost" value={defaultCost ? money(toMinorUnits(defaultCost, "INR")) : "—"} />
            <Review label="Preferred vendor" value={vendorName} />
            <Review label="Description" value={description || "—"} />
          </dl>
        )}

        {error && <p className="text-sm text-destructive">{error}</p>}

        <div className="flex items-center justify-between border-t border-border pt-4">
          {step === 0 ? (
            <Button asChild variant="outline">
              <Link href="/inventory/items">Cancel</Link>
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
              {busy ? "Creating…" : "Create Item"}
            </Button>
          )}
        </div>
      </Card>
    </div>
  );
}

function Field({ label, htmlFor, children }: { label: string; htmlFor: string; children: React.ReactNode }) {
  return (
    <div className="space-y-1.5">
      <Label htmlFor={htmlFor}>{label}</Label>
      {children}
    </div>
  );
}

function Review({ label, value }: { label: string; value: string }) {
  return (
    <>
      <dt className="text-muted-foreground">{label}</dt>
      <dd className="font-medium">{value}</dd>
    </>
  );
}
