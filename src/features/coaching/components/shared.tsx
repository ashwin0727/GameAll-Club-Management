"use client";

import { cn } from "@/lib/utils";
import { Badge } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { formatCurrency } from "@/features/pricing/money";
import type {
  CoachStatus,
  EnrollmentPaymentStatus,
  EnrollmentStatus,
  ProgressStatus,
  SessionStatus,
} from "@/features/coaching/types";

export function money(minor: number | null | undefined): string {
  return formatCurrency(minor ?? 0, "INR");
}

export function fmtDate(iso: string | null): string {
  if (!iso) return "—";
  return new Date(iso).toLocaleDateString("en-IN", { day: "2-digit", month: "short", year: "numeric" });
}

export function fmtTime(iso: string): string {
  return new Date(iso).toLocaleTimeString("en-IN", { hour: "2-digit", minute: "2-digit" });
}

export function fmtDateTime(iso: string | null): string {
  if (!iso) return "—";
  return `${fmtDate(iso)} · ${fmtTime(iso)}`;
}

export const DAY_LABELS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

export const SESSION_STATUS_LABEL: Record<SessionStatus, string> = {
  SCHEDULED: "Scheduled",
  CONFIRMED: "Confirmed",
  IN_PROGRESS: "In Progress",
  COMPLETED: "Completed",
  CANCELLED: "Cancelled",
};

export function sessionStatusBadge(s: SessionStatus) {
  const map: Record<SessionStatus, "outline" | "warning" | "success" | "secondary" | "destructive"> = {
    SCHEDULED: "outline",
    CONFIRMED: "success",
    IN_PROGRESS: "warning",
    COMPLETED: "secondary",
    CANCELLED: "destructive",
  };
  return <Badge variant={map[s]}>{SESSION_STATUS_LABEL[s]}</Badge>;
}

export function coachStatusBadge(s: CoachStatus) {
  const map = { ACTIVE: "success", INACTIVE: "secondary", ON_LEAVE: "warning" } as const;
  const label = { ACTIVE: "Active", INACTIVE: "Inactive", ON_LEAVE: "On Leave" }[s];
  return <Badge variant={map[s]}>{label}</Badge>;
}

export function enrollmentStatusBadge(s: EnrollmentStatus) {
  const map = { ACTIVE: "success", PAUSED: "warning", COMPLETED: "secondary", CANCELLED: "destructive" } as const;
  const label = { ACTIVE: "Active", PAUSED: "Paused", COMPLETED: "Completed", CANCELLED: "Cancelled" }[s];
  return <Badge variant={map[s]}>{label}</Badge>;
}

export function paymentStatusBadge(s: EnrollmentPaymentStatus) {
  const map = { INCLUDED: "secondary", PAID: "success", PARTIAL: "warning", PENDING: "warning" } as const;
  const label = { INCLUDED: "Included", PAID: "Paid", PARTIAL: "Partially Paid", PENDING: "Unpaid" }[s];
  return <Badge variant={map[s]}>{label}</Badge>;
}

export const PROGRESS_LABEL: Record<ProgressStatus, string> = {
  ON_TRACK: "On Track",
  NEEDS_WORK: "Needs Work",
  EXCELLING: "Excelling",
  AT_RISK: "At Risk",
};

export function progressBadge(s: ProgressStatus) {
  const map: Record<ProgressStatus, "success" | "warning" | "destructive" | "secondary"> = {
    ON_TRACK: "secondary",
    EXCELLING: "success",
    NEEDS_WORK: "warning",
    AT_RISK: "destructive",
  };
  return <Badge variant={map[s]}>{PROGRESS_LABEL[s]}</Badge>;
}

export function initials(name: string): string {
  const parts = name.trim().split(/\s+/).filter(Boolean);
  if (!parts.length) return "?";
  return ((parts[0]?.[0] ?? "") + (parts.length > 1 ? (parts[parts.length - 1]?.[0] ?? "") : "")).toUpperCase() || "?";
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

export function KpiCard({ label, value, hint }: { label: string; value: string; hint?: string }) {
  return (
    <Card className="p-4">
      <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">{label}</p>
      <p className="mt-1 text-2xl font-semibold tabular-nums">{value}</p>
      {hint && <p className="mt-0.5 text-xs text-muted-foreground">{hint}</p>}
    </Card>
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

/** For the wizard prices: "3000" (rupees typed) → 300000 minor. */
export function rupeesToMinor(v: string): number | null {
  const s = v.trim();
  if (!s) return null;
  const n = Number(s);
  if (!Number.isFinite(n) || n < 0) return null;
  return Math.round(n * 100);
}

/** minor → "3000" for prefilling a rupee input. */
export function minorToRupees(minor: number | null | undefined): string {
  if (minor == null) return "";
  return String(minor / 100);
}

/** A local datetime-local value ("2026-09-08T09:00") → ISO string. */
export function localToIso(value: string): string {
  return new Date(value).toISOString();
}

/** ISO → "YYYY-MM-DDTHH:MM" for a datetime-local input. */
export function isoToLocal(iso: string): string {
  const d = new Date(iso);
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}
