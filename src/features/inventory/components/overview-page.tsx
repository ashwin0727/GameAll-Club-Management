"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { Card } from "@/components/ui/card";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { ServiceError } from "@/services/shared/service-error";
import { getInventoryService } from "@/services/inventory";
import { usePermissionContext } from "@/features/auth/context/permission-provider";
import type { InventoryOverview } from "@/features/inventory/types";
import {
  EmptyState,
  ErrorState,
  KpiCard,
  MOVEMENT_LABEL,
  PageHeader,
  TableSkeleton,
  fmtDateTime,
  money,
  movementQty,
} from "@/features/inventory/components/shared";

export function InventoryOverviewPage() {
  const perms = usePermissionContext();
  const facilityId = perms?.facilityId ?? null;

  const [data, setData] = useState<InventoryOverview | null>(null);
  const [state, setState] = useState<"loading" | "ready" | "error">("loading");
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!facilityId) return;
    setState("loading");
    setError(null);
    try {
      setData(await getInventoryService().getOverview(facilityId));
      setState("ready");
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Unable to load the inventory overview.");
      setState("error");
    }
  }, [facilityId]);

  useEffect(() => {
    void load();
  }, [load]);

  if (state === "error") {
    return (
      <div className="space-y-4">
        <PageHeader title="Inventory Overview" />
        <Card className="p-0">
          <ErrorState message={error ?? ""} onRetry={() => void load()} />
        </Card>
      </div>
    );
  }

  if (state === "loading" || !data) {
    return (
      <div className="space-y-4">
        <PageHeader title="Inventory Overview" />
        <Card className="p-0">
          <TableSkeleton rows={8} />
        </Card>
      </div>
    );
  }

  const k = data.kpis;
  const total = data.stockStatus.inStock + data.stockStatus.lowStock + data.stockStatus.outOfStock;

  return (
    <div className="space-y-4">
      <PageHeader title="Inventory Overview" subtitle="Stock health, recent activity and value at a glance." />

      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <KpiCard label="Total Items" value={String(k.totalItems)} hint={`${k.inactiveItems} inactive`} />
        <KpiCard label="Low Stock" value={String(k.lowStockItems)} hint="at or below reorder level" />
        <KpiCard label="Out of Stock" value={String(k.outOfStockItems)} />
        <KpiCard label="Inventory Value" value={money(k.inventoryValueMinor)} hint="weighted average cost" />
        <KpiCard label="Active Vendors" value={String(k.activeVendors)} />
        <KpiCard label="Pending POs" value={String(k.pendingPurchaseOrders)} hint="ordered, not fully received" />
      </div>

      <div className="grid gap-4 lg:grid-cols-3">
        <Card className="p-4">
          <h2 className="text-sm font-semibold">Stock Status</h2>
          <ul className="mt-3 space-y-2 text-sm">
            <StatusRow label="In Stock" count={data.stockStatus.inStock} total={total} tone="bg-emerald-500" />
            <StatusRow label="Low Stock" count={data.stockStatus.lowStock} total={total} tone="bg-amber-500" />
            <StatusRow label="Out of Stock" count={data.stockStatus.outOfStock} total={total} tone="bg-destructive" />
          </ul>
        </Card>

        <Card className="p-4 lg:col-span-2">
          <h2 className="text-sm font-semibold">Low Stock Items</h2>
          {data.lowStockItems.length === 0 ? (
            <p className="mt-3 text-sm text-muted-foreground">Everything is above its reorder level.</p>
          ) : (
            <ul className="mt-3 divide-y divide-border">
              {data.lowStockItems.map((i) => (
                <li key={i.id} className="flex items-center justify-between py-2 text-sm">
                  <Link href={`/inventory/items/${i.id}`} className="font-medium hover:underline">
                    {i.name}
                  </Link>
                  <span className="text-muted-foreground">
                    {i.currentStock} / {i.reorderLevel} {i.unit}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </Card>
      </div>

      <Card className="p-4">
        <h2 className="text-sm font-semibold">Top Categories by Value</h2>
        {data.topCategoriesByValue.length === 0 ? (
          <p className="mt-3 text-sm text-muted-foreground">No categorised stock yet.</p>
        ) : (
          <ul className="mt-3 space-y-2">
            {data.topCategoriesByValue.map((c) => {
              const max = data.topCategoriesByValue[0]?.valueMinor || 1;
              return (
                <li key={c.id} className="text-sm">
                  <div className="flex justify-between">
                    <span>{c.name}</span>
                    <span className="text-muted-foreground">
                      {money(c.valueMinor)} · {c.itemCount} items
                    </span>
                  </div>
                  <div className="mt-1 h-2 rounded-full bg-muted">
                    <div
                      className="h-2 rounded-full bg-primary"
                      style={{ width: `${Math.max(4, (c.valueMinor / max) * 100)}%` }}
                    />
                  </div>
                </li>
              );
            })}
          </ul>
        )}
      </Card>

      <Card className="p-0">
        <h2 className="p-4 text-sm font-semibold">Recent Stock Movements</h2>
        {data.recentMovements.length === 0 ? (
          <EmptyState message="No stock movements recorded yet." />
        ) : (
          <div className="overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Date</TableHead>
                  <TableHead>Type</TableHead>
                  <TableHead>Item</TableHead>
                  <TableHead className="text-right">Qty</TableHead>
                  <TableHead>Reference</TableHead>
                  <TableHead>By</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {data.recentMovements.map((m) => (
                  <TableRow key={m.id}>
                    <TableCell className="whitespace-nowrap text-muted-foreground">{fmtDateTime(m.createdAt)}</TableCell>
                    <TableCell>{MOVEMENT_LABEL[m.movementType]}</TableCell>
                    <TableCell>
                      <Link href={`/inventory/items/${m.itemId}`} className="hover:underline">
                        {m.itemName}
                      </Link>
                    </TableCell>
                    <TableCell className="text-right">{movementQty(m.quantity)}</TableCell>
                    <TableCell className="text-muted-foreground">{m.referenceLabel ?? "—"}</TableCell>
                    <TableCell className="text-muted-foreground">{m.performedByName ?? "—"}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        )}
      </Card>
    </div>
  );
}

function StatusRow({ label, count, total, tone }: { label: string; count: number; total: number; tone: string }) {
  const pct = total > 0 ? Math.round((count / total) * 100) : 0;
  return (
    <li>
      <div className="flex justify-between">
        <span>{label}</span>
        <span className="text-muted-foreground">
          {count} ({pct}%)
        </span>
      </div>
      <div className="mt-1 h-2 rounded-full bg-muted">
        <div className={`h-2 rounded-full ${tone}`} style={{ width: `${pct}%` }} />
      </div>
    </li>
  );
}
