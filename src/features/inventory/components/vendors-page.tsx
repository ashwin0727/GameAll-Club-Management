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
import type { VendorRow, VendorStatus } from "@/features/inventory/types";
import {
  EmptyState,
  ErrorState,
  PageHeader,
  Pagination,
  TableSkeleton,
  money,
  vendorStatusBadge,
} from "@/features/inventory/components/shared";
import { VendorFormDialog } from "@/features/inventory/components/vendor-form-dialog";

const PAGE_SIZE = 20;
const ALL = "ALL";

export function VendorsPage() {
  const perms = usePermissionContext();
  const facilityId = perms?.facilityId ?? null;

  const [search, setSearch] = useState("");
  const [debounced, setDebounced] = useState("");
  const [status, setStatus] = useState(ALL);
  const [page, setPage] = useState(0);
  const [rows, setRows] = useState<VendorRow[] | null>(null);
  const [totalCount, setTotalCount] = useState(0);
  const [error, setError] = useState<string | null>(null);
  const [adding, setAdding] = useState(false);

  const canCreate = perms?.can("VENDOR_CREATE") ?? false;

  useEffect(() => {
    const t = setTimeout(() => setDebounced(search), 300);
    return () => clearTimeout(t);
  }, [search]);
  useEffect(() => setPage(0), [debounced, status]);

  const load = useCallback(async () => {
    if (!facilityId) return;
    setError(null);
    const result = await getInventoryService().listVendors({
      facilityId,
      filters: { search: debounced, status: status === ALL ? null : (status as VendorStatus) },
      limit: PAGE_SIZE,
      offset: page * PAGE_SIZE,
    });
    setRows(result.vendors);
    setTotalCount(result.totalCount);
  }, [facilityId, debounced, status, page]);

  useEffect(() => {
    let cancelled = false;
    setRows(null);
    load().catch((e) => {
      if (cancelled) return;
      setError(e instanceof ServiceError ? e.message : "Unable to load vendors.");
      setRows([]);
    });
    return () => {
      cancelled = true;
    };
  }, [load]);

  return (
    <div className="space-y-4">
      <PageHeader
        title="Vendors"
        subtitle="Suppliers this facility buys from."
        action={
          canCreate && (
            <Button size="sm" onClick={() => setAdding(true)}>
              <Plus className="h-4 w-4" aria-hidden /> Add Vendor
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
              placeholder="Search vendors…"
              aria-label="Search vendors"
              className="h-10 pl-9"
            />
          </div>
          <div className="space-y-1.5">
            <span className="block text-xs text-muted-foreground">Status</span>
            <Select value={status} onValueChange={setStatus}>
              <SelectTrigger className="w-[11rem]">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value={ALL}>All Status</SelectItem>
                <SelectItem value="ACTIVE">Active</SelectItem>
                <SelectItem value="INACTIVE">Inactive</SelectItem>
              </SelectContent>
            </Select>
          </div>
        </div>
      </Card>

      <Card className="p-0">
        {error ? (
          <ErrorState message={error} onRetry={() => void load()} />
        ) : rows === null ? (
          <TableSkeleton />
        ) : rows.length === 0 ? (
          <EmptyState message="No vendors match these filters." />
        ) : (
          <div className="overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Vendor</TableHead>
                  <TableHead>Contact</TableHead>
                  <TableHead>Phone</TableHead>
                  <TableHead className="text-right">POs</TableHead>
                  <TableHead className="text-right">Purchases</TableHead>
                  <TableHead className="text-right">Outstanding</TableHead>
                  <TableHead>Status</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {rows.map((v) => (
                  <TableRow key={v.id}>
                    <TableCell>
                      <Link href={`/inventory/vendors/${v.id}`} className="font-medium hover:underline">
                        {v.name}
                      </Link>
                      {v.email && <span className="block text-xs text-muted-foreground">{v.email}</span>}
                    </TableCell>
                    <TableCell className="text-muted-foreground">{v.contactPerson ?? "—"}</TableCell>
                    <TableCell className="text-muted-foreground">{v.phone ?? "—"}</TableCell>
                    <TableCell className="text-right tabular-nums">{v.poCount}</TableCell>
                    <TableCell className="text-right tabular-nums">{money(v.totalPurchasesMinor)}</TableCell>
                    <TableCell className="text-right tabular-nums">{money(v.outstandingMinor)}</TableCell>
                    <TableCell>{vendorStatusBadge(v.status)}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        )}
        <Pagination page={page} pageSize={PAGE_SIZE} totalCount={totalCount} onPage={setPage} unit="vendors" />
      </Card>

      {adding && facilityId && (
        <VendorFormDialog
          facilityId={facilityId}
          onClose={() => setAdding(false)}
          onSaved={() => {
            setAdding(false);
            void load();
          }}
        />
      )}
    </div>
  );
}
