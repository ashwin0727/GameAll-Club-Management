"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { Link2, Plus, Users, UserCheck, UserMinus, Wallet, MoreVertical, Trash2, Eye, IndianRupee } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from "@/components/ui/dialog";
import {
  DropdownMenu,
  DropdownMenuTrigger,
  DropdownMenuContent,
  DropdownMenuItem,
} from "@/components/ui/dropdown-menu";
import { cn } from "@/lib/utils";
import { useCountUp } from "@/features/dashboard/use-count-up";
import { ServiceError } from "@/services/shared/service-error";
import { getFacilityService } from "@/services/facility";
import { getMembershipService } from "@/services/memberships";
import { useMembershipList, useMembershipSummary } from "@/features/memberships/hooks/use-memberships";
import { MembershipPlansDialog } from "@/features/memberships/components/membership-plans-dialog";
import { MembershipAccessDaysDialog } from "@/features/memberships/components/membership-access-days-dialog";
import { MembershipRevenueTrend } from "@/features/memberships/components/membership-revenue-trend";
import { formatSlot } from "@/features/memberships/slot-format";
import { ALL_DAYS } from "@/features/memberships/slot-form";
import type {
  MembershipListSort,
  MembershipListStatus,
  MembershipPlan,
} from "@/features/memberships/types";

const PER_PAGE = 10;

const STATUS_OPTIONS: { value: MembershipListStatus | ""; label: string }[] = [
  { value: "", label: "All Status" },
  { value: "active", label: "Active" },
  { value: "payment_incomplete", label: "Payment Incomplete" },
  { value: "inactive", label: "Inactive" },
];

const SORT_OPTIONS: { value: MembershipListSort; label: string }[] = [
  { value: "oldest", label: "Oldest First" },
  { value: "next_payment", label: "Next Payment: Soonest" },
  { value: "name", label: "Name (A–Z)" },
];

function inr(v: number): string {
  return `₹${v.toLocaleString("en-IN")}`;
}
function fmtDate(iso: string): string {
  return new Date(iso).toLocaleDateString("en-IN", { day: "2-digit", month: "short", year: "numeric" });
}
function initials(name: string): string {
  return name
    .split(" ")
    .filter(Boolean)
    .slice(0, 2)
    .map((p) => p[0]!.toUpperCase())
    .join("");
}
function pct(v: number | null): string {
  if (v === null) return "";
  const rounded = Math.round(v * 10) / 10;
  return `${rounded >= 0 ? "↑" : "↓"} ${Math.abs(rounded)}%`;
}

function statusBadge(status: MembershipListStatus) {
  switch (status) {
    case "active":
      return <Badge variant="success">Active</Badge>;
    case "payment_incomplete":
      return <Badge variant="warning">Payment Incomplete</Badge>;
    case "inactive":
      return <Badge variant="secondary">Inactive</Badge>;
    default:
      // A stale RPC (migration 0030 not yet applied) can still send the old
      // status strings — show the raw value rather than an empty cell.
      return <Badge variant="secondary">{String(status).replace(/_/g, " ")}</Badge>;
  }
}

function isPastDate(iso: string): boolean {
  const d = new Date(iso);
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  return d < today;
}

function KpiCard({
  icon: Icon,
  label,
  value,
  hint,
  hintClass,
  accent,
  countTo,
  format,
  index = 0,
}: {
  icon: React.ComponentType<{ className?: string }>;
  label: string;
  value: string;
  hint?: string;
  hintClass?: string;
  accent: string;
  /** Numeric target for the count-up; requires `format`. Without both, `value` renders as-is. */
  countTo?: number;
  format?: (v: number) => string;
  /** Position in the KPI row — staggers the entrance left-to-right. */
  index?: number;
}) {
  const animated = useCountUp(countTo ?? 0);
  const animating = countTo !== undefined && format !== undefined;

  return (
    <Card
      className={cn(
        "stat-enter p-4 transition-shadow",
        "border-[var(--kpi-tint)] shadow-[0_6px_20px_-8px_var(--kpi-shadow)] hover:shadow-[0_10px_26px_-8px_var(--kpi-shadow-hover)]",
      )}
      style={
        {
          "--stat-delay": `${index * 70}ms`,
          "--kpi-tint": `${accent}3d`,
          "--kpi-shadow": `${accent}40`,
          "--kpi-shadow-hover": `${accent}66`,
        } as React.CSSProperties
      }
    >
      <div className="flex items-start justify-between gap-2">
        <p className="text-xs font-medium text-muted-foreground">{label}</p>
        <span
          className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full"
          style={{ backgroundColor: `${accent}1f`, color: accent }}
        >
          <Icon className="h-4 w-4" />
        </span>
      </div>
      {/* The animated figure is decorative motion over the same number — the
          accessible name always carries the settled value. */}
      <p className="mt-1 text-2xl font-semibold tabular-nums text-foreground" aria-label={value}>
        <span aria-hidden>{animating ? format(Math.round(animated)) : value}</span>
      </p>
      {hint && <p className={cn("mt-0.5 text-xs", hintClass ?? "text-muted-foreground")}>{hint}</p>}
    </Card>
  );
}

export function MembershipsPage() {
  const router = useRouter();
  const [facilityId, setFacilityId] = useState<string | null>(null);
  const [loadState, setLoadState] = useState<"loading" | "ready" | "none">("loading");

  const [search, setSearch] = useState("");
  const [debouncedSearch, setDebouncedSearch] = useState("");
  const [status, setStatus] = useState<MembershipListStatus | "">("");
  const [planId, setPlanId] = useState("");
  const [sort, setSort] = useState<MembershipListSort>("oldest");
  const [page, setPage] = useState(1);

  const [plans, setPlans] = useState<MembershipPlan[]>([]);
  const [plansOpen, setPlansOpen] = useState(false);
  const [accessDaysOpen, setAccessDaysOpen] = useState(false);
  const [accessDays, setAccessDays] = useState<number[]>(ALL_DAYS);
  const [linkCopied, setLinkCopied] = useState(false);
  const [deleteTarget, setDeleteTarget] = useState<{ memberId: string; name: string } | null>(null);
  const [deleting, setDeleting] = useState(false);
  const [deleteError, setDeleteError] = useState<string | null>(null);
  const [payTarget, setPayTarget] = useState<{ id: string; name: string } | null>(null);
  const [paying, setPaying] = useState(false);
  const [payError, setPayError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const facility = await getFacilityService().getFacility();
      if (cancelled) return;
      if (!facility) {
        setLoadState("none");
        return;
      }
      setFacilityId(facility.id);
      setAccessDays(facility.membershipAccessDays);
      setLoadState("ready");
      getMembershipService()
        .getFacilityPlans(facility.id)
        .then((p) => !cancelled && setPlans(p))
        .catch(() => undefined);
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    const t = setTimeout(() => setDebouncedSearch(search), 300);
    return () => clearTimeout(t);
  }, [search]);

  useEffect(() => {
    setPage(1);
  }, [debouncedSearch, status, planId, sort]);

  const listParams = useMemo(
    () => ({
      search: debouncedSearch || undefined,
      status: status || undefined,
      planId: planId || undefined,
      sort,
      page,
      perPage: PER_PAGE,
    }),
    [debouncedSearch, status, planId, sort, page],
  );

  const summaryQuery = useMembershipSummary(facilityId);
  const listQuery = useMembershipList(facilityId, listParams);

  const summary = summaryQuery.data;
  const rows = listQuery.data?.rows ?? [];
  const totalCount = listQuery.data?.totalCount ?? 0;
  const totalPages = Math.max(1, Math.ceil(totalCount / PER_PAGE));
  const hasFilters = Boolean(debouncedSearch || status || planId || sort !== "oldest");

  function refetchAll() {
    summaryQuery.refetch();
    listQuery.refetch();
  }

  async function confirmPayment() {
    if (!payTarget) return;
    setPaying(true);
    setPayError(null);
    try {
      await getMembershipService().recordMembershipPayment(payTarget.id);
      setPayTarget(null);
      refetchAll();
    } catch (err) {
      setPayError(err instanceof ServiceError ? err.message : "Unable to record this payment.");
    } finally {
      setPaying(false);
    }
  }

  async function confirmDelete() {
    if (!deleteTarget) return;
    setDeleting(true);
    setDeleteError(null);
    try {
      await getMembershipService().deleteMember(deleteTarget.memberId);
      setDeleteTarget(null);
      refetchAll();
    } catch (err) {
      setDeleteError(err instanceof ServiceError ? err.message : "Unable to delete this member.");
    } finally {
      setDeleting(false);
    }
  }

  async function shareLink() {
    if (!facilityId) return;
    const url = `${window.location.origin}/join/${facilityId}`;
    try {
      await navigator.clipboard.writeText(url);
      setLinkCopied(true);
      setTimeout(() => setLinkCopied(false), 2000);
    } catch {
      window.prompt("Copy this membership sign-up link:", url);
    }
  }

  if (loadState === "loading") {
    return (
      <div className="space-y-6">
        <Skeleton className="h-16 w-full rounded-xl" />
        <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
          {Array.from({ length: 4 }).map((_, i) => (
            <Skeleton key={i} className="h-24 rounded-xl" />
          ))}
        </div>
        <Skeleton className="h-96 w-full rounded-xl" />
      </div>
    );
  }

  if (loadState === "none") {
    return <p className="text-sm text-muted-foreground">Complete your facility setup to manage memberships.</p>;
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <h1 className="text-xl font-semibold">Memberships</h1>
          <p className="text-sm text-muted-foreground">Manage your club memberships, members and sharing links.</p>
        </div>
        <div className="flex flex-wrap gap-2">
          <Button type="button" variant="outline" size="sm" onClick={shareLink}>
            <Link2 className="mr-1.5 h-4 w-4" />
            {linkCopied ? "Link copied" : "Share Membership Link"}
          </Button>
          <Button type="button" variant="outline" size="sm" onClick={() => setPlansOpen(true)}>
            Manage Plans
          </Button>
          <Button type="button" variant="outline" size="sm" onClick={() => setAccessDaysOpen(true)}>
            Access Days
          </Button>
          <Button type="button" size="sm" onClick={() => router.push("/memberships/new")}>
            <Plus className="mr-1.5 h-4 w-4" />
            Create Membership
          </Button>
        </div>
      </div>

      {/* KPIs */}
      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        {summary ? (
          <>
            <KpiCard
              icon={Users}
              label="Total Members"
              value={String(summary.totalMembers)}
              hint={
                summary.totalMembersChangePct !== null
                  ? `${pct(summary.totalMembersChangePct)} vs last month`
                  : undefined
              }
              hintClass={
                summary.totalMembersChangePct !== null && summary.totalMembersChangePct >= 0
                  ? "text-success"
                  : "text-destructive"
              }
              accent="#8B5CF6"
              countTo={summary.totalMembers}
              format={(v) => String(v)}
              index={0}
            />
            <KpiCard
              icon={UserCheck}
              label="Active Members"
              value={String(summary.activeMembers)}
              hint={`${Math.round(summary.activePctOfTotal * 10) / 10}% of total members`}
              accent="#00D084"
              countTo={summary.activeMembers}
              format={(v) => String(v)}
              index={1}
            />
            <KpiCard
              icon={UserMinus}
              label="Payment Incomplete"
              value={String(summary.paymentIncompleteMembers)}
              hint={summary.paymentIncompleteMembers > 0 ? "Payment due / overdue" : "All paid up"}
              hintClass={summary.paymentIncompleteMembers > 0 ? "text-destructive" : "text-muted-foreground"}
              accent="#FF4D67"
              countTo={summary.paymentIncompleteMembers}
              format={(v) => String(v)}
              index={2}
            />
            <KpiCard
              icon={Wallet}
              label="Membership Revenue"
              value={inr(summary.revenueInr)}
              hint={
                summary.revenueChangePct !== null
                  ? `${pct(summary.revenueChangePct)} vs last month`
                  : "this month"
              }
              hintClass={
                summary.revenueChangePct !== null && summary.revenueChangePct >= 0
                  ? "text-success"
                  : "text-destructive"
              }
              accent="#5B6CFF"
              countTo={summary.revenueInr}
              format={inr}
              index={3}
            />
          </>
        ) : (
          Array.from({ length: 4 }).map((_, i) => <Skeleton key={i} className="h-24 rounded-xl" />)
        )}
      </div>

      {/* Filters */}
      <div className="flex flex-wrap items-center gap-2">
        <Input
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder="Search by name, phone or email"
          className="h-9 w-full max-w-xs"
        />
        <select
          aria-label="Status"
          value={status}
          onChange={(e) => setStatus(e.target.value as MembershipListStatus | "")}
          className="h-9 rounded-md border border-input bg-secondary/60 px-2 text-sm"
        >
          {STATUS_OPTIONS.map((o) => (
            <option key={o.value} value={o.value}>
              {o.label}
            </option>
          ))}
        </select>
        <select
          aria-label="Membership type"
          value={planId}
          onChange={(e) => setPlanId(e.target.value)}
          className="h-9 rounded-md border border-input bg-secondary/60 px-2 text-sm"
        >
          <option value="">All Types</option>
          {plans.map((p) => (
            <option key={p.id} value={p.id}>
              {p.name}
            </option>
          ))}
        </select>
        <select
          aria-label="Sort by"
          value={sort}
          onChange={(e) => setSort(e.target.value as MembershipListSort)}
          className="h-9 rounded-md border border-input bg-secondary/60 px-2 text-sm"
        >
          {SORT_OPTIONS.map((o) => (
            <option key={o.value} value={o.value}>
              {o.label}
            </option>
          ))}
        </select>
        {hasFilters && (
          <Button
            type="button"
            variant="ghost"
            size="sm"
            onClick={() => {
              setSearch("");
              setStatus("");
              setPlanId("");
              setSort("oldest");
            }}
          >
            Clear Filters
          </Button>
        )}
      </div>

      {/* Table */}
      <Card className="stat-enter overflow-hidden p-0" style={{ "--stat-delay": "300ms" } as React.CSSProperties}>
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="border-b border-border text-left text-xs text-muted-foreground">
              <tr>
                <th className="px-4 py-3 font-medium">Member</th>
                <th className="px-4 py-3 font-medium">Membership Type</th>
                <th className="px-4 py-3 font-medium">Status</th>
                <th className="px-4 py-3 font-medium">Start Date</th>
                <th className="px-4 py-3 font-medium">Next Payment Date</th>
                <th className="px-4 py-3 text-right font-medium">Actions</th>
              </tr>
            </thead>
            <tbody>
              {listQuery.isLoading ? (
                Array.from({ length: 6 }).map((_, i) => (
                  <tr key={i} className="border-b border-border/60">
                    <td colSpan={6} className="px-4 py-3">
                      <Skeleton className="h-8 w-full" />
                    </td>
                  </tr>
                ))
              ) : rows.length === 0 ? (
                <tr>
                  <td colSpan={6} className="px-4 py-10 text-center text-sm text-muted-foreground">
                    {hasFilters ? "No memberships match these filters." : "No memberships yet."}
                  </td>
                </tr>
              ) : (
                rows.map((row) => {
                  return (
                    <tr key={row.membershipId} className="border-b border-border/60 last:border-b-0">
                      <td className="px-4 py-3">
                        <div className="flex items-center gap-3">
                          <Avatar>
                            <AvatarFallback>{initials(row.memberName)}</AvatarFallback>
                          </Avatar>
                          <div className="min-w-0">
                            <p className="truncate font-medium text-foreground">{row.memberName}</p>
                            <p className="truncate text-xs text-muted-foreground">
                              {row.memberPhone}
                              {row.memberEmail ? ` · ${row.memberEmail}` : ""}
                            </p>
                          </div>
                        </div>
                      </td>
                      <td className="px-4 py-3">
                        <p className="font-medium text-foreground">{row.planName}</p>
                        <p className="text-xs text-muted-foreground">{inr(row.monthlyPriceInr)} / month</p>
                        {row.slot && (
                          <p className="text-xs text-muted-foreground">
                            {row.slot.courtName ? `${row.slot.courtName} · ` : ""}
                            {formatSlot(row.slot.daysOfWeek, row.slot.startTime, row.slot.endTime)}
                          </p>
                        )}
                      </td>
                      <td className="px-4 py-3">{statusBadge(row.status)}</td>
                      <td className="px-4 py-3 text-muted-foreground">{fmtDate(row.startDate)}</td>
                      <td className={cn("px-4 py-3", isPastDate(row.endDate) ? "text-destructive" : "text-foreground")}>
                        {fmtDate(row.endDate)}
                      </td>
                      <td className="px-4 py-3 text-right">
                        <div className="flex items-center justify-end gap-1">
                          <Button
                            type="button"
                            variant="outline"
                            size="sm"
                            onClick={() => router.push(`/memberships/${row.membershipId}`)}
                          >
                            View
                          </Button>
                          <DropdownMenu>
                            <DropdownMenuTrigger asChild>
                              <Button type="button" variant="ghost" size="icon" aria-label="More actions">
                                <MoreVertical className="h-4 w-4" />
                              </Button>
                            </DropdownMenuTrigger>
                            <DropdownMenuContent align="end">
                              <DropdownMenuItem onClick={() => router.push(`/memberships/${row.membershipId}`)}>
                                <Eye className="mr-2 h-4 w-4" />
                                View details
                              </DropdownMenuItem>
                              {row.status === "payment_incomplete" && (
                                <DropdownMenuItem onClick={() => setPayTarget({ id: row.membershipId, name: row.memberName })}>
                                  <IndianRupee className="mr-2 h-4 w-4" />
                                  Record payment
                                </DropdownMenuItem>
                              )}
                              <DropdownMenuItem
                                className="text-destructive focus:text-destructive"
                                onClick={() => {
                                  setDeleteError(null);
                                  setDeleteTarget({ memberId: row.memberId, name: row.memberName });
                                }}
                              >
                                <Trash2 className="mr-2 h-4 w-4" />
                                Delete member
                              </DropdownMenuItem>
                            </DropdownMenuContent>
                          </DropdownMenu>
                        </div>
                      </td>
                    </tr>
                  );
                })
              )}
            </tbody>
          </table>
        </div>

        {/* Pagination */}
        <div className="flex flex-wrap items-center justify-between gap-2 border-t border-border px-4 py-3 text-xs text-muted-foreground">
          <span>
            {totalCount === 0
              ? "No members"
              : `Showing ${(page - 1) * PER_PAGE + 1} to ${Math.min(page * PER_PAGE, totalCount)} of ${totalCount} members`}
          </span>
          <div className="flex items-center gap-1">
            <Button
              type="button"
              variant="outline"
              size="sm"
              disabled={page <= 1}
              onClick={() => setPage((p) => Math.max(1, p - 1))}
            >
              Previous
            </Button>
            <span className="px-2">
              Page {page} / {totalPages}
            </span>
            <Button
              type="button"
              variant="outline"
              size="sm"
              disabled={page >= totalPages}
              onClick={() => setPage((p) => Math.min(totalPages, p + 1))}
            >
              Next
            </Button>
          </div>
        </div>
      </Card>

      {facilityId && <MembershipRevenueTrend facilityId={facilityId} />}

      {facilityId && (
        <>
          <MembershipPlansDialog open={plansOpen} onOpenChange={setPlansOpen} facilityId={facilityId} />
          <MembershipAccessDaysDialog
            open={accessDaysOpen}
            onOpenChange={setAccessDaysOpen}
            facilityId={facilityId}
            currentDays={accessDays}
            onSaved={setAccessDays}
          />
        </>
      )}

      <Dialog
        open={payTarget !== null}
        onOpenChange={(o) => {
          if (!o && !paying) {
            setPayTarget(null);
            setPayError(null);
          }
        }}
      >
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Record payment</DialogTitle>
            <DialogDescription>
              Mark this billing cycle as paid for{" "}
              <span className="font-medium text-foreground">{payTarget?.name}</span>. Use this when you&apos;ve collected
              the payment outside the app.
            </DialogDescription>
          </DialogHeader>
          {payError && <p className="text-sm text-destructive">{payError}</p>}
          <DialogFooter>
            <Button type="button" variant="outline" disabled={paying} onClick={() => setPayTarget(null)}>
              Cancel
            </Button>
            <Button type="button" disabled={paying} onClick={confirmPayment}>
              {paying ? "Recording…" : "Record payment"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog
        open={deleteTarget !== null}
        onOpenChange={(o) => {
          if (!o && !deleting) {
            setDeleteTarget(null);
            setDeleteError(null);
          }
        }}
      >
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Delete member</DialogTitle>
            <DialogDescription>
              Permanently remove <span className="font-medium text-foreground">{deleteTarget?.name}</span>. This only
              works for members with no bookings and no settled payments.
            </DialogDescription>
          </DialogHeader>
          {deleteError && <p className="text-sm text-destructive">{deleteError}</p>}
          <DialogFooter>
            <Button
              type="button"
              variant="outline"
              disabled={deleting}
              onClick={() => {
                setDeleteTarget(null);
                setDeleteError(null);
              }}
            >
              Cancel
            </Button>
            <Button
              type="button"
              variant="destructive"
              disabled={deleting}
              onClick={confirmDelete}
            >
              {deleting ? "Deleting…" : "Delete"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}