"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { Plus } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { ServiceError } from "@/services/shared/service-error";
import { getInventoryService } from "@/services/inventory";
import { usePermissionContext } from "@/features/auth/context/permission-provider";
import type { PoStatus, PurchaseOrderRow } from "@/features/inventory/types";
import {
  EmptyState,
  ErrorState,
  PO_STATUS_LABEL,
  PageHeader,
  Pagination,
  TableSkeleton,
  fmtDate,
  money,
  poPaymentBadge,
  poStatusBadge,
} from "@/features/inventory/components/shared";

const PAGE_SIZE = 20;
const ALL = "ALL";

export function PurchaseOrdersPage() {
  const perms = usePermissionContext();
  const facilityId = perms?.facilityId ?? null;

  const [status, setStatus] = useState(ALL);
  const [page, setPage] = useState(0);
  const [rows, setRows] = useState<PurchaseOrderRow[] | null>(null);
  const [totalCount, setTotalCount] = useState(0);
  const [error, setError] = useState<string | null>(null);

  const canCreate = perms?.can("PURCHASE_CREATE") ?? false;

  useEffect(() => setPage(0), [status]);

  const load = useCallback(async () => {
    if (!facilityId) return;
    setError(null);
    const result = await getInventoryService().listPurchaseOrders({
      facilityId,
      filters: { status: status === ALL ? null : (status as PoStatus) },
      limit: PAGE_SIZE,
      offset: page * PAGE_SIZE,
    });
    setRows(result.purchaseOrders);
    setTotalCount(result.totalCount);
  }, [facilityId, status, page]);

  useEffect(() => {
    let cancelled = false;
    setRows(null);
    load().catch((e) => {
      if (cancelled) return;
      setError(e instanceof ServiceError ? e.message : "Unable to load purchase orders.");
      setRows([]);
    });
    return () => {
      cancelled = true;
    };
  }, [load]);

  return (
    <div className="space-y-4">
      <PageHeader
        title="Purchase Orders"
        subtitle="Order supplies from vendors. Placing a PO records the expense; stock only moves on receipt."
        action={
          canCreate && (
            <Button asChild size="sm">
              <Link href="/inventory/purchase-orders/new">
                <Plus className="h-4 w-4" aria-hidden /> New Purchase Order
              </Link>
            </Button>
          )
        }
      />

      <Card className="p-4">
        <div className="space-y-1.5">
          <span className="block text-xs text-muted-foreground">Status</span>
          <Select value={status} onValueChange={setStatus}>
            <SelectTrigger className="w-[13rem]">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value={ALL}>All Status</SelectItem>
              {(Object.keys(PO_STATUS_LABEL) as PoStatus[]).map((s) => (
                <SelectItem key={s} value={s}>
                  {PO_STATUS_LABEL[s]}
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
          <EmptyState message="No purchase orders match this filter." />
        ) : (
          <div className="overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>PO Number</TableHead>
                  <TableHead>Vendor</TableHead>
                  <TableHead>Order Date</TableHead>
                  <TableHead className="text-right">Items</TableHead>
                  <TableHead className="text-right">Total</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead>Payment</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {rows.map((p) => (
                  <TableRow key={p.id}>
                    <TableCell>
                      <Link href={`/inventory/purchase-orders/${p.id}`} className="font-medium hover:underline">
                        {p.poNumber}
                      </Link>
                    </TableCell>
                    <TableCell className="text-muted-foreground">{p.vendorName}</TableCell>
                    <TableCell className="text-muted-foreground">{fmtDate(p.orderDate)}</TableCell>
                    <TableCell className="text-right tabular-nums">{p.itemCount}</TableCell>
                    <TableCell className="text-right tabular-nums">{money(p.totalMinor)}</TableCell>
                    <TableCell>{poStatusBadge(p.status)}</TableCell>
                    <TableCell>{poPaymentBadge(p.paymentStatus)}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        )}
        <Pagination page={page} pageSize={PAGE_SIZE} totalCount={totalCount} onPage={setPage} unit="purchase orders" />
      </Card>
    </div>
  );
}
