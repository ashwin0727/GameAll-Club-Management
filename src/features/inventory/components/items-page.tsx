"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { Plus, Search } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { ServiceError } from "@/services/shared/service-error";
import { getInventoryService } from "@/services/inventory";
import { usePermissionContext } from "@/features/auth/context/permission-provider";
import type { CategoryRow, ItemRow, ItemStatus, StockStatus } from "@/features/inventory/types";
import {
  EmptyState,
  ErrorState,
  PageHeader,
  Pagination,
  TableSkeleton,
  itemStatusBadge,
  money,
  stockStatusBadge,
} from "@/features/inventory/components/shared";
import { RecordMovementDialog } from "@/features/inventory/components/record-movement-dialog";

const PAGE_SIZE = 20;
const ALL = "ALL";

export function ItemsPage() {
  const perms = usePermissionContext();
  const facilityId = perms?.facilityId ?? null;

  const [search, setSearch] = useState("");
  const [debounced, setDebounced] = useState("");
  const [categoryId, setCategoryId] = useState(ALL);
  const [status, setStatus] = useState(ALL);
  const [stockStatus, setStockStatus] = useState(ALL);
  const [page, setPage] = useState(0);

  const [categories, setCategories] = useState<CategoryRow[]>([]);
  const [items, setItems] = useState<ItemRow[] | null>(null);
  const [totalCount, setTotalCount] = useState(0);
  const [error, setError] = useState<string | null>(null);
  const [move, setMove] = useState<{ mode: "STOCK_IN" | "STOCK_OUT"; item: ItemRow } | null>(null);

  const canCreate = perms?.can("INVENTORY_CREATE_ITEM") ?? false;
  const canStockIn = perms?.can("INVENTORY_STOCK_IN") ?? false;
  const canStockOut = perms?.can("INVENTORY_STOCK_OUT") ?? false;

  useEffect(() => {
    const t = setTimeout(() => setDebounced(search), 300);
    return () => clearTimeout(t);
  }, [search]);
  useEffect(() => setPage(0), [debounced, categoryId, status, stockStatus]);

  useEffect(() => {
    if (!facilityId) return;
    getInventoryService().listCategories(facilityId).then(setCategories).catch(() => setCategories([]));
  }, [facilityId]);

  const load = useCallback(async () => {
    if (!facilityId) return;
    setError(null);
    const result = await getInventoryService().listItems({
      facilityId,
      filters: {
        search: debounced,
        categoryId: categoryId === ALL ? null : categoryId,
        status: status === ALL ? null : (status as ItemStatus),
        stockStatus: stockStatus === ALL ? null : (stockStatus as StockStatus),
      },
      limit: PAGE_SIZE,
      offset: page * PAGE_SIZE,
    });
    setItems(result.items);
    setTotalCount(result.totalCount);
  }, [facilityId, debounced, categoryId, status, stockStatus, page]);

  useEffect(() => {
    let cancelled = false;
    setItems(null);
    load().catch((e) => {
      if (cancelled) return;
      setError(e instanceof ServiceError ? e.message : "Unable to load items.");
      setItems([]);
    });
    return () => {
      cancelled = true;
    };
  }, [load]);

  return (
    <div className="space-y-4">
      <PageHeader
        title="Items"
        subtitle="Supplies, consumables and equipment stock."
        action={
          canCreate && (
            <Button asChild size="sm">
              <Link href="/inventory/items/new">
                <Plus className="h-4 w-4" aria-hidden /> Add Item
              </Link>
            </Button>
          )
        }
      />

      <Card className="p-4">
        <div className="flex flex-wrap items-end gap-3">
          <div className="relative min-w-[14rem] flex-1">
            <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" aria-hidden />
            <Input
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Search by name, SKU or brand…"
              aria-label="Search items"
              className="h-10 pl-9"
            />
          </div>
          <Filter label="Category" value={categoryId} onChange={setCategoryId} options={[{ value: ALL, label: "All Categories" }, ...categories.map((c) => ({ value: c.id, label: c.name }))]} />
          <Filter
            label="Stock"
            value={stockStatus}
            onChange={setStockStatus}
            options={[
              { value: ALL, label: "All Stock" },
              { value: "IN_STOCK", label: "In Stock" },
              { value: "LOW_STOCK", label: "Low Stock" },
              { value: "OUT_OF_STOCK", label: "Out of Stock" },
            ]}
          />
          <Filter
            label="Status"
            value={status}
            onChange={setStatus}
            options={[
              { value: ALL, label: "All Status" },
              { value: "ACTIVE", label: "Active" },
              { value: "INACTIVE", label: "Inactive" },
            ]}
          />
        </div>
      </Card>

      <Card className="p-0">
        {error ? (
          <ErrorState message={error} onRetry={() => void load()} />
        ) : items === null ? (
          <TableSkeleton />
        ) : items.length === 0 ? (
          <EmptyState message="No items match these filters." />
        ) : (
          <div className="overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Item</TableHead>
                  <TableHead>SKU</TableHead>
                  <TableHead>Category</TableHead>
                  <TableHead className="text-right">Current Stock</TableHead>
                  <TableHead className="text-right">Reorder</TableHead>
                  <TableHead className="text-right">Value</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead />
                </TableRow>
              </TableHeader>
              <TableBody>
                {items.map((i) => (
                  <TableRow key={i.id}>
                    <TableCell>
                      <Link href={`/inventory/items/${i.id}`} className="font-medium hover:underline">
                        {i.name}
                      </Link>
                      {i.brand && <span className="block text-xs text-muted-foreground">{i.brand}</span>}
                    </TableCell>
                    <TableCell className="text-muted-foreground">{i.sku}</TableCell>
                    <TableCell className="text-muted-foreground">{i.categoryName ?? "—"}</TableCell>
                    <TableCell className="text-right tabular-nums">
                      {i.currentStock} {i.unit}
                      <span className="ml-2">{stockStatusBadge(i.stockStatus)}</span>
                    </TableCell>
                    <TableCell className="text-right tabular-nums text-muted-foreground">{i.reorderLevel}</TableCell>
                    <TableCell className="text-right tabular-nums">{money(i.inventoryValueMinor)}</TableCell>
                    <TableCell>{itemStatusBadge(i.status)}</TableCell>
                    <TableCell className="text-right">
                      <div className="flex justify-end gap-1">
                        {canStockIn && i.status === "ACTIVE" && (
                          <Button size="sm" variant="outline" onClick={() => setMove({ mode: "STOCK_IN", item: i })}>
                            In
                          </Button>
                        )}
                        {canStockOut && i.status === "ACTIVE" && (
                          <Button size="sm" variant="outline" onClick={() => setMove({ mode: "STOCK_OUT", item: i })}>
                            Out
                          </Button>
                        )}
                      </div>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        )}
        <Pagination page={page} pageSize={PAGE_SIZE} totalCount={totalCount} onPage={setPage} unit="items" />
      </Card>

      {move && (
        <RecordMovementDialog
          open
          onOpenChange={(v) => !v && setMove(null)}
          mode={move.mode}
          itemId={move.item.id}
          itemName={move.item.name}
          currentStock={move.item.currentStock}
          unit={move.item.unit}
          onDone={() => void load()}
        />
      )}
    </div>
  );
}

function Filter({
  label,
  value,
  onChange,
  options,
}: {
  label: string;
  value: string;
  onChange: (v: string) => void;
  options: { value: string; label: string }[];
}) {
  return (
    <div className="space-y-1.5">
      <span className="block text-xs text-muted-foreground">{label}</span>
      <Select value={value} onValueChange={onChange}>
        <SelectTrigger className="w-[11rem]">
          <SelectValue />
        </SelectTrigger>
        <SelectContent>
          {options.map((o) => (
            <SelectItem key={o.value} value={o.value}>
              {o.label}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>
    </div>
  );
}
