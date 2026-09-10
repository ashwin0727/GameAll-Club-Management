"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
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
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { ServiceError } from "@/services/shared/service-error";
import { getInventoryService } from "@/services/inventory";
import { toMinorUnits } from "@/features/pricing/money";
import { usePermissionContext } from "@/features/auth/context/permission-provider";
import type { CategoryRow, ItemDetail, PoStatus } from "@/features/inventory/types";
import {
  ErrorState,
  MOVEMENT_LABEL,
  PO_STATUS_LABEL,
  PageHeader,
  TableSkeleton,
  Tabs,
  fmtDate,
  fmtDateTime,
  itemStatusBadge,
  money,
  movementQty,
  stockStatusBadge,
} from "@/features/inventory/components/shared";
import { RecordMovementDialog } from "@/features/inventory/components/record-movement-dialog";

const TABS = ["Overview", "Movements", "Purchases"] as const;

export function ItemDetailsPage({ itemId }: { itemId: string }) {
  const perms = usePermissionContext();
  const facilityId = perms?.facilityId ?? null;

  const [tab, setTab] = useState<(typeof TABS)[number]>("Overview");
  const [detail, setDetail] = useState<ItemDetail | null>(null);
  const [state, setState] = useState<"loading" | "ready" | "error">("loading");
  const [error, setError] = useState<string | null>(null);
  const [move, setMove] = useState<"STOCK_IN" | "STOCK_OUT" | "ADJUSTMENT" | null>(null);
  const [editing, setEditing] = useState(false);

  const load = useCallback(async () => {
    setState("loading");
    setError(null);
    try {
      setDetail(await getInventoryService().getItem(itemId));
      setState("ready");
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Unable to load this item.");
      setState("error");
    }
  }, [itemId]);

  useEffect(() => {
    void load();
  }, [load]);

  const canEdit = perms?.can("INVENTORY_EDIT_ITEM") ?? false;
  const canStockIn = perms?.can("INVENTORY_STOCK_IN") ?? false;
  const canStockOut = perms?.can("INVENTORY_STOCK_OUT") ?? false;
  const canAdjust = perms?.can("INVENTORY_ADJUST") ?? false;

  if (state === "error") {
    return (
      <div className="space-y-4">
        <BackLink />
        <Card className="p-0">
          <ErrorState message={error ?? ""} onRetry={() => void load()} />
        </Card>
      </div>
    );
  }

  if (state === "loading" || !detail) {
    return (
      <div className="space-y-4">
        <BackLink />
        <Card className="p-0">
          <TableSkeleton rows={6} />
        </Card>
      </div>
    );
  }

  const d = detail;

  return (
    <div className="space-y-4">
      <BackLink />
      <PageHeader
        title={d.name}
        subtitle={`${d.sku}${d.brand ? ` · ${d.brand}` : ""}`}
        action={
          <div className="flex flex-wrap gap-2">
            {canStockIn && d.status === "ACTIVE" && (
              <Button size="sm" variant="outline" onClick={() => setMove("STOCK_IN")}>
                Stock In
              </Button>
            )}
            {canStockOut && d.status === "ACTIVE" && (
              <Button size="sm" variant="outline" onClick={() => setMove("STOCK_OUT")}>
                Stock Out
              </Button>
            )}
            {canAdjust && d.status === "ACTIVE" && (
              <Button size="sm" variant="outline" onClick={() => setMove("ADJUSTMENT")}>
                Adjust
              </Button>
            )}
            {canEdit && (
              <Button size="sm" onClick={() => setEditing(true)}>
                Edit
              </Button>
            )}
          </div>
        }
      />

      <div className="flex flex-wrap items-center gap-2">
        {stockStatusBadge(d.stockStatus)}
        {itemStatusBadge(d.status)}
        {d.categoryName && <Badge variant="outline">{d.categoryName}</Badge>}
      </div>

      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <Stat label="Current Stock" value={`${d.currentStock} ${d.unit}`} />
        <Stat label="Reorder Level" value={String(d.reorderLevel)} />
        <Stat label="Unit Cost (avg)" value={money(d.unitCostMinor)} />
        <Stat label="Stock Value" value={money(d.inventoryValueMinor)} />
      </div>

      <Tabs tabs={TABS} active={tab} onChange={setTab} />

      {tab === "Overview" && (
        <div className="grid gap-4 lg:grid-cols-2">
          <Card className="p-4">
            <h2 className="text-sm font-semibold">Details</h2>
            <dl className="mt-3 grid grid-cols-2 gap-x-4 gap-y-2 text-sm">
              <Row label="Preferred vendor" value={d.preferredVendorName ?? "—"} />
              <Row label="Default cost" value={d.defaultUnitCostMinor != null ? money(d.defaultUnitCostMinor) : "—"} />
              <Row label="Created" value={fmtDate(d.createdAt)} />
              <Row label="Updated" value={fmtDate(d.updatedAt)} />
            </dl>
            {d.description && <p className="mt-3 text-sm text-muted-foreground">{d.description}</p>}
          </Card>
          <Card className="p-4">
            <h2 className="text-sm font-semibold">Movement Stats</h2>
            <dl className="mt-3 grid grid-cols-2 gap-x-4 gap-y-2 text-sm">
              <Row label="Total in" value={String(d.stats.totalInQty)} />
              <Row label="Total out" value={String(d.stats.totalOutQty)} />
              <Row label="Last stock in" value={fmtDate(d.stats.lastStockInAt)} />
              <Row label="Last stock out" value={fmtDate(d.stats.lastStockOutAt)} />
            </dl>
          </Card>
        </div>
      )}

      {tab === "Movements" && (
        <Card className="p-0">
          {d.recentMovements.length === 0 ? (
            <div className="p-10 text-center text-sm text-muted-foreground">No movements recorded yet.</div>
          ) : (
            <div className="overflow-x-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Date</TableHead>
                    <TableHead>Type</TableHead>
                    <TableHead className="text-right">Qty</TableHead>
                    <TableHead className="text-right">Balance</TableHead>
                    <TableHead>Reference</TableHead>
                    <TableHead>By</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {d.recentMovements.map((m) => (
                    <TableRow key={m.id}>
                      <TableCell className="whitespace-nowrap text-muted-foreground">{fmtDateTime(m.createdAt)}</TableCell>
                      <TableCell>{MOVEMENT_LABEL[m.movementType]}</TableCell>
                      <TableCell className="text-right">{movementQty(m.quantity)}</TableCell>
                      <TableCell className="text-right tabular-nums">{m.balanceAfter}</TableCell>
                      <TableCell className="text-muted-foreground">{m.referenceLabel ?? m.reason ?? "—"}</TableCell>
                      <TableCell className="text-muted-foreground">{m.performedByName ?? "—"}</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          )}
        </Card>
      )}

      {tab === "Purchases" && (
        <Card className="p-0">
          {d.purchases.length === 0 ? (
            <div className="p-10 text-center text-sm text-muted-foreground">This item has never been on a purchase order.</div>
          ) : (
            <div className="overflow-x-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>PO</TableHead>
                    <TableHead>Vendor</TableHead>
                    <TableHead>Date</TableHead>
                    <TableHead className="text-right">Ordered</TableHead>
                    <TableHead className="text-right">Received</TableHead>
                    <TableHead className="text-right">Unit Cost</TableHead>
                    <TableHead>Status</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {d.purchases.map((p) => (
                    <TableRow key={p.poId}>
                      <TableCell>
                        <Link href={`/inventory/purchase-orders/${p.poId}`} className="hover:underline">
                          {p.poNumber}
                        </Link>
                      </TableCell>
                      <TableCell className="text-muted-foreground">{p.vendorName}</TableCell>
                      <TableCell className="text-muted-foreground">{fmtDate(p.orderDate)}</TableCell>
                      <TableCell className="text-right tabular-nums">{p.quantityOrdered}</TableCell>
                      <TableCell className="text-right tabular-nums">{p.quantityReceived}</TableCell>
                      <TableCell className="text-right tabular-nums">{money(p.unitCostMinor)}</TableCell>
                      <TableCell className="text-muted-foreground">{PO_STATUS_LABEL[p.status as PoStatus]}</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          )}
        </Card>
      )}

      {move && (
        <RecordMovementDialog
          open
          onOpenChange={(v) => !v && setMove(null)}
          mode={move}
          itemId={d.id}
          itemName={d.name}
          currentStock={d.currentStock}
          unit={d.unit}
          onDone={() => void load()}
        />
      )}

      {editing && (
        <EditItemDialog
          detail={d}
          facilityId={facilityId}
          onClose={() => setEditing(false)}
          onSaved={() => {
            setEditing(false);
            void load();
          }}
        />
      )}
    </div>
  );
}

function EditItemDialog({
  detail,
  facilityId,
  onClose,
  onSaved,
}: {
  detail: ItemDetail;
  facilityId: string | null;
  onClose: () => void;
  onSaved: () => void;
}) {
  const [name, setName] = useState(detail.name);
  const [sku, setSku] = useState(detail.sku);
  const [brand, setBrand] = useState(detail.brand ?? "");
  const [unit, setUnit] = useState(detail.unit);
  const [reorder, setReorder] = useState(String(detail.reorderLevel));
  const [defaultCost, setDefaultCost] = useState(
    detail.defaultUnitCostMinor != null ? String(detail.defaultUnitCostMinor / 100) : "",
  );
  const [categoryId, setCategoryId] = useState(detail.categoryId ?? "NONE");
  const [status, setStatus] = useState(detail.status);
  const [description, setDescription] = useState(detail.description ?? "");
  const [categories, setCategories] = useState<CategoryRow[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!facilityId) return;
    getInventoryService().listCategories(facilityId).then(setCategories).catch(() => setCategories([]));
  }, [facilityId]);

  async function save() {
    setBusy(true);
    setError(null);
    try {
      await getInventoryService().updateItem({
        itemId: detail.id,
        name: name.trim(),
        sku: sku.trim(),
        brand: brand.trim() || null,
        unit: unit.trim(),
        reorderLevel: Number(reorder) || 0,
        defaultUnitCostMinor: defaultCost.trim() ? toMinorUnits(defaultCost, "INR") : null,
        categoryId: categoryId === "NONE" ? null : categoryId,
        status,
        description: description.trim() || null,
      });
      onSaved();
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Could not save changes.");
      setBusy(false);
    }
  }

  return (
    <Dialog open onOpenChange={(v) => !v && !busy && onClose()}>
      <DialogContent className="max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Edit item</DialogTitle>
        </DialogHeader>
        <div className="space-y-3">
          <F label="Name"><Input value={name} onChange={(e) => setName(e.target.value)} /></F>
          <F label="SKU"><Input value={sku} onChange={(e) => setSku(e.target.value)} /></F>
          <F label="Brand"><Input value={brand} onChange={(e) => setBrand(e.target.value)} /></F>
          <F label="Unit"><Input value={unit} onChange={(e) => setUnit(e.target.value)} /></F>
          <F label="Reorder level">
            <Input type="number" min="0" step="1" value={reorder} onChange={(e) => setReorder(e.target.value)} />
          </F>
          <F label="Default unit cost (₹)">
            <Input type="number" min="0" step="0.01" value={defaultCost} onChange={(e) => setDefaultCost(e.target.value)} />
          </F>
          <F label="Category">
            <Select value={categoryId} onValueChange={setCategoryId}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="NONE">None</SelectItem>
                {categories.map((c) => (
                  <SelectItem key={c.id} value={c.id}>
                    {c.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </F>
          <F label="Status">
            <Select value={status} onValueChange={(v) => setStatus(v as ItemDetail["status"])}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="ACTIVE">Active</SelectItem>
                <SelectItem value="INACTIVE">Inactive</SelectItem>
              </SelectContent>
            </Select>
          </F>
          <F label="Description">
            <Textarea rows={3} value={description} onChange={(e) => setDescription(e.target.value)} />
          </F>
          {error && <p className="text-sm text-destructive">{error}</p>}
        </div>
        <DialogFooter>
          <Button variant="outline" disabled={busy} onClick={onClose}>
            Cancel
          </Button>
          <Button disabled={busy} onClick={() => void save()}>
            {busy ? "Saving…" : "Save"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function BackLink() {
  return (
    <Link href="/inventory/items" className="text-sm text-muted-foreground hover:underline">
      ← Back to items
    </Link>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <Card className="p-3">
      <p className="text-xs text-muted-foreground">{label}</p>
      <p className="mt-0.5 text-lg font-semibold tabular-nums">{value}</p>
    </Card>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <>
      <dt className="text-muted-foreground">{label}</dt>
      <dd className="font-medium">{value}</dd>
    </>
  );
}

function F({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="space-y-1.5">
      <Label>{label}</Label>
      {children}
    </div>
  );
}
