"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { Card } from "@/components/ui/card";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { ServiceError } from "@/services/shared/service-error";
import { getInventoryService } from "@/services/inventory";
import { usePermissionContext } from "@/features/auth/context/permission-provider";
import type { MovementType, StockMovementRow } from "@/features/inventory/types";
import {
  EmptyState,
  ErrorState,
  MOVEMENT_LABEL,
  PageHeader,
  Pagination,
  TableSkeleton,
  fmtDateTime,
  movementQty,
} from "@/features/inventory/components/shared";

const PAGE_SIZE = 25;
const ALL = "ALL";

export function StockMovementsPage() {
  const perms = usePermissionContext();
  const facilityId = perms?.facilityId ?? null;

  const [type, setType] = useState(ALL);
  const [page, setPage] = useState(0);
  const [rows, setRows] = useState<StockMovementRow[] | null>(null);
  const [totalCount, setTotalCount] = useState(0);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => setPage(0), [type]);

  const load = useCallback(async () => {
    if (!facilityId) return;
    setError(null);
    const result = await getInventoryService().listMovements({
      facilityId,
      filters: { movementType: type === ALL ? null : (type as MovementType) },
      limit: PAGE_SIZE,
      offset: page * PAGE_SIZE,
    });
    setRows(result.movements);
    setTotalCount(result.totalCount);
  }, [facilityId, type, page]);

  useEffect(() => {
    let cancelled = false;
    setRows(null);
    load().catch((e) => {
      if (cancelled) return;
      setError(e instanceof ServiceError ? e.message : "Unable to load stock movements.");
      setRows([]);
    });
    return () => {
      cancelled = true;
    };
  }, [load]);

  return (
    <div className="space-y-4">
      <PageHeader title="Stock Movements" subtitle="Every change to stock, with its reference." />

      <Card className="p-4">
        <div className="space-y-1.5">
          <span className="block text-xs text-muted-foreground">Type</span>
          <Select value={type} onValueChange={setType}>
            <SelectTrigger className="w-[13rem]">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value={ALL}>All Types</SelectItem>
              {(Object.keys(MOVEMENT_LABEL) as MovementType[]).map((t) => (
                <SelectItem key={t} value={t}>
                  {MOVEMENT_LABEL[t]}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
      </Card>

      <Card className="p-0">
        {error ? (
          <ErrorState message={error} onRetry={() => void load()} />
        ) : rows === null ? (
          <TableSkeleton />
        ) : rows.length === 0 ? (
          <EmptyState message="No stock movements match this filter." />
        ) : (
          <div className="overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Date</TableHead>
                  <TableHead>Type</TableHead>
                  <TableHead>Item</TableHead>
                  <TableHead className="text-right">Qty</TableHead>
                  <TableHead className="text-right">Balance</TableHead>
                  <TableHead>Reference</TableHead>
                  <TableHead>By</TableHead>
                  <TableHead>Notes</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {rows.map((m) => (
                  <TableRow key={m.id}>
                    <TableCell className="whitespace-nowrap text-muted-foreground">{fmtDateTime(m.createdAt)}</TableCell>
                    <TableCell>{MOVEMENT_LABEL[m.movementType]}</TableCell>
                    <TableCell>
                      <Link href={`/inventory/items/${m.itemId}`} className="hover:underline">
                        {m.itemName}
                      </Link>
                    </TableCell>
                    <TableCell className="text-right">{movementQty(m.quantity)}</TableCell>
                    <TableCell className="text-right tabular-nums">{m.balanceAfter}</TableCell>
                    <TableCell className="text-muted-foreground">{m.referenceLabel ?? m.reason ?? "—"}</TableCell>
                    <TableCell className="text-muted-foreground">{m.performedByName ?? "—"}</TableCell>
                    <TableCell className="max-w-[16rem] truncate text-muted-foreground">{m.notes ?? "—"}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        )}
        <Pagination page={page} pageSize={PAGE_SIZE} totalCount={totalCount} onPage={setPage} unit="movements" />
      </Card>
    </div>
  );
}
