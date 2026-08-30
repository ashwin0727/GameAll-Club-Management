"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { Link2, Plus, Users, UserCheck, Clock, UserX, Wallet } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { cn } from "@/lib/utils";
import { getFacilityService } from "@/services/facility";
import { getMembershipService } from "@/services/memberships";
import { useMembershipList, useMembershipSummary } from "@/features/memberships/hooks/use-memberships";
import { MemberProfileDialog } from "@/features/memberships/components/member-profile-dialog";
import { MembershipPlansDialog } from "@/features/memberships/components/membership-plans-dialog";
import { MembershipRevenueTrend } from "@/features/memberships/components/membership-revenue-trend";
import { formatSlot } from "@/features/memberships/slot-format";
import type {
  FacilityMemberRow,
  MembershipListRow,
  MembershipListSort,
  MembershipListStatus,
  MembershipPlan,
} from "@/features/memberships/types";

const PER_PAGE = 10;

const STATUS_OPTIONS: { value: MembershipListStatus | ""; label: string }[] = [
  { value: "", label: "All Status" },
  { value: "active", label: "Active" },
  { value: "expiring_soon", label: "Expiring Soon" },
  { value: "expired", label: "Expired" },
  { value: "cancelled", label: "Cancelled" },
];

const SORT_OPTIONS: { value: MembershipListSort; label: string }[] = [
  { value: "newest", label: "Newest First" },
  { value: "oldest", label: "Oldest First" },
  { value: "expiry_asc", label: "Expiry: Soonest" },
  { value: "expiry_desc", label: "Expiry: Latest" },
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
    case "expiring_soon":
      return <Badge variant="warning">Expiring Soon</Badge>;
    case "expired":
      return <Badge variant="destructive">Expired</Badge>;
    case "cancelled":
      return <Badge variant="secondary">Cancelled</Badge>;
  }
}

function expiryHint(row: MembershipListRow): { text: string; className: string } {
  if (row.status === "cancelled") return { text: "Cancelled", className: "text-muted-foreground" };
  if (row.daysLeft < 0) return { text: `Expired ${Math.abs(row.daysLeft)} days ago`, className: "text-destructive" };
  if (row.daysLeft === 0) return { text: "Expires today", className: "text-warning" };
  return {
    text: `${row.daysLeft} days left`,
    className: row.daysLeft <= 30 ? "text-warning" : "text-success",
  };
}

function toFacilityMemberRow(row: MembershipListRow): FacilityMemberRow {
  const raw =
    row.status === "expired" ? "expired" : row.status === "cancelled" ? "cancelled" : "active";
  return {
    memberId: row.memberId,
    fullName: row.memberName,
    phone: row.memberPhone,
    email: row.memberEmail,
    membershipId: row.membershipId,
    planId: row.planId,
    planName: row.planName,
    startDate: row.startDate,
    endDate: row.endDate,
    status: raw,
  };
}

function KpiCard({
  icon: Icon,
  label,
  value,
  hint,
  hintClass,
  accent,
}: {
  icon: React.ComponentType<{ className?: string }>;
  label: string;
  value: string;
  hint?: string;
  hintClass?: string;
  accent: string;
}) {
  return (
    <Card className="p-4">
      <div className="flex items-start justify-between gap-2">
        <p className="text-xs font-medium text-muted-foreground">{label}</p>
        <span
          className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full"
          style={{ backgroundColor: `${accent}1f`, color: accent }}
        >
          <Icon className="h-4 w-4" />
        </span>
      </div>
      <p className="mt-1 text-2xl font-semibold text-foreground">{value}</p>
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
  const [sort, setSort] = useState<MembershipListSort>("newest");
  const [page, setPage] = useState(1);

  const [plans, setPlans] = useState<MembershipPlan[]>([]);
  const [plansOpen, setPlansOpen] = useState(false);
  const [profileRow, setProfileRow] = useState<FacilityMemberRow | null>(null);
  const [linkCopied, setLinkCopied] = useState(false);

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
  const hasFilters = Boolean(debouncedSearch || status || planId || sort !== "newest");

  function refetchAll() {
    summaryQuery.refetch();
    listQuery.refetch();
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
        <div className="grid grid-cols-2 gap-4 lg:grid-cols-5">
          {Array.from({ length: 5 }).map((_, i) => (
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
          <Button type="button" size="sm" onClick={() => router.push("/memberships/new")}>
            <Plus className="mr-1.5 h-4 w-4" />
            Create Membership
          </Button>
        </div>
      </div>

      {/* KPIs */}
      <div className="grid grid-cols-2 gap-4 lg:grid-cols-5">
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
            />
            <KpiCard
              icon={UserCheck}
              label="Active Members"
              value={String(summary.activeMembers)}
              hint={`${Math.round(summary.activePctOfTotal * 10) / 10}% of total members`}
              accent="#00D084"
            />
            <KpiCard
              icon={Clock}
              label="Expiring Soon"
              value={String(summary.expiringSoon)}
              hint="in next 30 days"
              accent="#FFB020"
            />
            <KpiCard
              icon={UserX}
              label="Expired Members"
              value={String(summary.expiredMembers)}
              hint={summary.expiredMembers > 0 ? "Needs attention" : "All clear"}
              hintClass={summary.expiredMembers > 0 ? "text-destructive" : "text-muted-foreground"}
              accent="#FF4D67"
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
            />
          </>
        ) : (
          Array.from({ length: 5 }).map((_, i) => <Skeleton key={i} className="h-24 rounded-xl" />)
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
              setSort("newest");
            }}
          >
            Clear Filters
          </Button>
        )}
      </div>

      {/* Table */}
      <Card className="overflow-hidden p-0">
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="border-b border-border text-left text-xs text-muted-foreground">
              <tr>
                <th className="px-4 py-3 font-medium">Member</th>
                <th className="px-4 py-3 font-medium">Membership Type</th>
                <th className="px-4 py-3 font-medium">Status</th>
                <th className="px-4 py-3 font-medium">Start Date</th>
                <th className="px-4 py-3 font-medium">Expiry Date</th>
                <th className="px-4 py-3 font-medium">Linked By</th>
                <th className="px-4 py-3 text-right font-medium">Actions</th>
              </tr>
            </thead>
            <tbody>
              {listQuery.isLoading ? (
                Array.from({ length: 6 }).map((_, i) => (
                  <tr key={i} className="border-b border-border/60">
                    <td colSpan={7} className="px-4 py-3">
                      <Skeleton className="h-8 w-full" />
                    </td>
                  </tr>
                ))
              ) : rows.length === 0 ? (
                <tr>
                  <td colSpan={7} className="px-4 py-10 text-center text-sm text-muted-foreground">
                    {hasFilters ? "No memberships match these filters." : "No memberships yet."}
                  </td>
                </tr>
              ) : (
                rows.map((row) => {
                  const hint = expiryHint(row);
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
                      <td className="px-4 py-3">
                        <p className="text-foreground">{fmtDate(row.endDate)}</p>
                        <p className={cn("text-xs", hint.className)}>{hint.text}</p>
                      </td>
                      <td className="px-4 py-3">
                        {row.createdById ? (
                          <span className="flex items-center gap-2">
                            <Avatar className="h-6 w-6">
                              <AvatarFallback className="text-[10px]">
                                {initials(row.createdByName ?? "?")}
                              </AvatarFallback>
                            </Avatar>
                            <span className="text-xs text-foreground">{row.createdByName ?? "Staff"}</span>
                          </span>
                        ) : (
                          <span className="text-xs text-muted-foreground">Self Registered</span>
                        )}
                      </td>
                      <td className="px-4 py-3 text-right">
                        <Button
                          type="button"
                          variant="outline"
                          size="sm"
                          onClick={() => setProfileRow(toFacilityMemberRow(row))}
                        >
                          View
                        </Button>
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
          <MemberProfileDialog
            open={profileRow !== null}
            onOpenChange={(o) => !o && setProfileRow(null)}
            facilityId={facilityId}
            member={profileRow}
            onChanged={refetchAll}
          />
        </>
      )}
    </div>
  );
}