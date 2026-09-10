"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { getInitials } from "@/lib/utils";
import { ServiceError } from "@/services/shared/service-error";
import { getInventoryService } from "@/services/inventory";
import { usePermissionContext } from "@/features/auth/context/permission-provider";
import type { VendorDetail } from "@/features/inventory/types";
import {
  ErrorState,
  TableSkeleton,
  Tabs,
  fmtDate,
  money,
  poPaymentBadge,
  poStatusBadge,
  vendorStatusBadge,
} from "@/features/inventory/components/shared";
import { VendorFormDialog } from "@/features/inventory/components/vendor-form-dialog";

const TABS = ["Overview", "Supplied Items", "Purchase History", "Payments", "Notes"] as const;

export function VendorDetailsPage({ vendorId }: { vendorId: string }) {
  const perms = usePermissionContext();
  const [tab, setTab] = useState<(typeof TABS)[number]>("Overview");
  const [detail, setDetail] = useState<VendorDetail | null>(null);
  const [state, setState] = useState<"loading" | "ready" | "error">("loading");
  const [error, setError] = useState<string | null>(null);
  const [editing, setEditing] = useState(false);

  const load = useCallback(async () => {
    setState("loading");
    setError(null);
    try {
      setDetail(await getInventoryService().getVendor(vendorId));
      setState("ready");
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Unable to load this vendor.");
      setState("error");
    }
  }, [vendorId]);

  useEffect(() => {
    void load();
  }, [load]);

  const canEdit = perms?.can("VENDOR_EDIT") ?? false;

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
  if (state === "loading" || !detail) {
    return (
      <div className="space-y-4">
        <Back />
        <Card className="p-0">
          <TableSkeleton rows={6} />
        </Card>
      </div>
    );
  }

  const d = detail;

  return (
    <div className="space-y-4">
      <Back />
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-3">
          <span className="flex h-12 w-12 items-center justify-center rounded-full bg-muted text-sm font-semibold">
            {getInitials(d.name)}
          </span>
          <div>
            <h1 className="text-xl font-semibold">{d.name}</h1>
            <div className="mt-0.5">{vendorStatusBadge(d.status)}</div>
          </div>
        </div>
        {canEdit && (
          <Button size="sm" onClick={() => setEditing(true)}>
            Edit
          </Button>
        )}
      </div>

      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <Stat label="Purchase Orders" value={String(d.summary.poCount)} />
        <Stat label="Total Purchases" value={money(d.summary.totalPurchasesMinor)} />
        <Stat label="Paid" value={money(d.summary.paidMinor)} />
        <Stat label="Outstanding" value={money(d.summary.outstandingMinor)} />
      </div>

      <Tabs tabs={TABS} active={tab} onChange={setTab} />

      {tab === "Overview" && (
        <Card className="p-4">
          <h2 className="text-sm font-semibold">Contact Information</h2>
          <dl className="mt-3 grid grid-cols-2 gap-x-4 gap-y-2 text-sm">
            <Row label="Contact person" value={d.contactPerson ?? "—"} />
            <Row label="Phone" value={d.phone ?? "—"} />
            <Row label="Email" value={d.email ?? "—"} />
            <Row label="Address" value={d.address ?? "—"} />
            <Row label="GST" value={d.gstNumber ?? "—"} />
            <Row label="PAN" value={d.panNumber ?? "—"} />
            <Row label="Last order" value={fmtDate(d.summary.lastOrderDate)} />
            <Row label="Added" value={fmtDate(d.createdAt)} />
          </dl>
        </Card>
      )}

      {tab === "Supplied Items" && (
        <Card className="p-0">
          {d.suppliedItems.length === 0 ? (
            <Empty message="No items are linked to this vendor yet." />
          ) : (
            <SimpleTable
              head={["Item", "SKU", "Stock", "Last Cost"]}
              rows={d.suppliedItems.map((i) => [
                <Link key="l" href={`/inventory/items/${i.id}`} className="hover:underline">
                  {i.name}
                </Link>,
                i.sku,
                `${i.currentStock} ${i.unit}`,
                i.lastUnitCostMinor != null ? money(i.lastUnitCostMinor) : "—",
              ])}
            />
          )}
        </Card>
      )}

      {tab === "Purchase History" && (
        <Card className="p-0">
          {d.purchaseHistory.length === 0 ? (
            <Empty message="No purchase orders for this vendor." />
          ) : (
            <div className="overflow-x-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>PO</TableHead>
                    <TableHead>Date</TableHead>
                    <TableHead>Status</TableHead>
                    <TableHead className="text-right">Total</TableHead>
                    <TableHead>Payment</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {d.purchaseHistory.map((p) => (
                    <TableRow key={p.poId}>
                      <TableCell>
                        <Link href={`/inventory/purchase-orders/${p.poId}`} className="hover:underline">
                          {p.poNumber}
                        </Link>
                      </TableCell>
                      <TableCell className="text-muted-foreground">{fmtDate(p.orderDate)}</TableCell>
                      <TableCell>{poStatusBadge(p.status)}</TableCell>
                      <TableCell className="text-right tabular-nums">{money(p.totalMinor)}</TableCell>
                      <TableCell>{poPaymentBadge(p.paymentStatus)}</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          )}
        </Card>
      )}

      {tab === "Payments" && (
        <Card className="p-0">
          {d.payments.length === 0 ? (
            <Empty message="No payments recorded for this vendor." />
          ) : (
            <SimpleTable
              head={["Date", "PO", "Method", "Reference", "Amount"]}
              rows={d.payments.map((p) => [
                fmtDate(p.paidOn),
                p.poNumber ?? "—",
                p.method ?? "—",
                p.reference ?? "—",
                money(p.amountMinor),
              ])}
            />
          )}
        </Card>
      )}

      {tab === "Notes" && (
        <Card className="p-4 text-sm">
          {d.notes ? <p className="whitespace-pre-wrap">{d.notes}</p> : <p className="text-muted-foreground">No notes.</p>}
        </Card>
      )}

      {editing && (
        <VendorFormDialog
          facilityId={d.facilityId}
          existing={d}
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

function Back() {
  return (
    <Link href="/inventory/vendors" className="text-sm text-muted-foreground hover:underline">
      ← Back to vendors
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

function Empty({ message }: { message: string }) {
  return <div className="p-10 text-center text-sm text-muted-foreground">{message}</div>;
}

function SimpleTable({ head, rows }: { head: string[]; rows: React.ReactNode[][] }) {
  return (
    <div className="overflow-x-auto">
      <Table>
        <TableHeader>
          <TableRow>
            {head.map((h) => (
              <TableHead key={h}>{h}</TableHead>
            ))}
          </TableRow>
        </TableHeader>
        <TableBody>
          {rows.map((r, i) => (
            <TableRow key={i}>
              {r.map((c, j) => (
                <TableCell key={j} className={j === 0 ? "" : "text-muted-foreground"}>
                  {c}
                </TableCell>
              ))}
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </div>
  );
}
