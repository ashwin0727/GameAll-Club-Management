"use client";

import { cn } from "@/lib/utils";
import { Badge } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { formatCurrency } from "@/features/pricing/money";
import type { ItemStatus, MovementType, PoPaymentStatus, PoStatus, StockStatus, VendorStatus } from "@/features/inventory/types";

export function money(minor: number): string {
  return formatCurrency(minor, "INR");
}

export function fmtDate(iso: string | null): string {
  if (!iso) return "—";
  return new Date(iso).toLocaleDateString("en-IN", { day: "2-digit", month: "short", year: "numeric" });
}

export function fmtDateTime(iso: string | null): string {
  if (!iso) return "—";
  return new Date(iso).toLocaleString("en-IN", {
    day: "2-digit",
    month: "short",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

export function stockStatusBadge(s: StockStatus) {
  const map = { IN_STOCK: "success", LOW_STOCK: "warning", OUT_OF_STOCK: "destructive" } as const;
  const label = { IN_STOCK: "In Stock", LOW_STOCK: "Low Stock", OUT_OF_STOCK: "Out of Stock" }[s];
  return <Badge variant={map[s]}>{label}</Badge>;
}

export function itemStatusBadge(s: ItemStatus) {
  return <Badge variant={s === "ACTIVE" ? "success" : "secondary"}>{s === "ACTIVE" ? "Active" : "Inactive"}</Badge>;
}

export function vendorStatusBadge(s: VendorStatus) {
  return <Badge variant={s === "ACTIVE" ? "success" : "secondary"}>{s === "ACTIVE" ? "Active" : "Inactive"}</Badge>;
}

export const PO_STATUS_LABEL: Record<PoStatus, string> = {
  DRAFT: "Draft",
  ORDERED: "Ordered",
  PARTIALLY_RECEIVED: "Partially Received",
  RECEIVED: "Received",
  CANCELLED: "Cancelled",
};

export function poStatusBadge(s: PoStatus) {
  const map: Record<PoStatus, "secondary" | "warning" | "success" | "destructive" | "outline"> = {
    DRAFT: "outline",
    ORDERED: "warning",
    PARTIALLY_RECEIVED: "warning",
    RECEIVED: "success",
    CANCELLED: "destructive",
  };
  return <Badge variant={map[s]}>{PO_STATUS_LABEL[s]}</Badge>;
}

export const PO_PAYMENT_LABEL: Record<PoPaymentStatus, string> = {
  UNBILLED: "Unbilled",
  PENDING: "Unpaid",
  PARTIAL: "Partially Paid",
  PAID: "Paid",
};

export function poPaymentBadge(s: PoPaymentStatus) {
  const map: Record<PoPaymentStatus, "secondary" | "warning" | "success"> = {
    UNBILLED: "secondary",
    PENDING: "warning",
    PARTIAL: "warning",
    PAID: "success",
  };
  return <Badge variant={map[s]}>{PO_PAYMENT_LABEL[s]}</Badge>;
}

export const MOVEMENT_LABEL: Record<MovementType, string> = {
  STOCK_IN: "Stock In",
  STOCK_OUT: "Stock Out",
  ADJUSTMENT: "Adjustment",
  PURCHASE_RECEIVED: "Received",
  RETURN: "Return",
};

export function movementQty(qty: number) {
  const positive = qty > 0;
  return (
    <span className={cn("font-medium tabular-nums", positive ? "text-emerald-600" : "text-destructive")}>
      {positive ? "+" : ""}
      {qty}
    </span>
  );
}

export function PageHeader({
  title,
  subtitle,
  action,
}: {
  title: string;
  subtitle?: string;
  action?: React.ReactNode;
}) {
  return (
    <div className="flex flex-wrap items-center justify-between gap-3">
      <div>
        <h1 className="text-xl font-semibold">{title}</h1>
        {subtitle && <p className="text-sm text-muted-foreground">{subtitle}</p>}
      </div>
      {action}
    </div>
  );
}

export function TableSkeleton({ rows = 6 }: { rows?: number }) {
  return (
    <div className="space-y-2 p-4">
      {Array.from({ length: rows }).map((_, i) => (
        <Skeleton key={i} className="h-12 w-full rounded-lg" />
      ))}
    </div>
  );
}

export function ErrorState({ message, onRetry }: { message: string; onRetry?: () => void }) {
  return (
    <div className="p-10 text-center">
      <p className="text-sm font-semibold text-destructive">Something went wrong</p>
      <p className="mt-1 text-sm text-muted-foreground">{message}</p>
      {onRetry && (
        <button
          type="button"
          onClick={onRetry}
          className="mt-4 rounded-md border border-border px-3 py-1.5 text-sm hover:bg-accent"
        >
          Try again
        </button>
      )}
    </div>
  );
}

export function EmptyState({ message }: { message: string }) {
  return <div className="p-10 text-center text-sm text-muted-foreground">{message}</div>;
}

export function Tabs<T extends string>({
  tabs,
  active,
  onChange,
}: {
  tabs: readonly T[];
  active: T;
  onChange: (t: T) => void;
}) {
  return (
    <div className="flex flex-wrap gap-1 border-b border-border">
      {tabs.map((t) => (
        <button
          key={t}
          type="button"
          onClick={() => onChange(t)}
          className={cn(
            "-mb-px border-b-2 px-3 py-2 text-sm font-medium transition-colors",
            active === t
              ? "border-primary text-primary"
              : "border-transparent text-muted-foreground hover:text-foreground",
          )}
        >
          {t}
        </button>
      ))}
    </div>
  );
}

export function KpiCard({ label, value, hint }: { label: string; value: string; hint?: string }) {
  return (
    <Card className="p-4">
      <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">{label}</p>
      <p className="mt-1 text-2xl font-semibold tabular-nums">{value}</p>
      {hint && <p className="mt-0.5 text-xs text-muted-foreground">{hint}</p>}
    </Card>
  );
}

export function Pagination({
  page,
  pageSize,
  totalCount,
  onPage,
  unit,
}: {
  page: number;
  pageSize: number;
  totalCount: number;
  onPage: (p: number) => void;
  unit: string;
}) {
  const totalPages = Math.max(1, Math.ceil(totalCount / pageSize));
  if (totalCount === 0) return null;
  return (
    <div className="flex items-center justify-between gap-3 border-t border-border p-3">
      <p className="text-xs text-muted-foreground">
        Showing {page * pageSize + 1} to {Math.min((page + 1) * pageSize, totalCount)} of {totalCount} {unit}
      </p>
      <div className="flex items-center gap-1">
        <button
          type="button"
          disabled={page === 0}
          onClick={() => onPage(page - 1)}
          className="rounded-md border border-border px-2 py-1 text-xs disabled:opacity-50"
        >
          Prev
        </button>
        <span className="px-2 text-xs text-muted-foreground">
          {page + 1} / {totalPages}
        </span>
        <button
          type="button"
          disabled={page + 1 >= totalPages}
          onClick={() => onPage(page + 1)}
          className="rounded-md border border-border px-2 py-1 text-xs disabled:opacity-50"
        >
          Next
        </button>
      </div>
    </div>
  );
}
