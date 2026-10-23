"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { IndianRupee, Users, UsersRound, Wallet } from "lucide-react";
import { Skeleton } from "@/components/ui/skeleton";
import { MembershipDashboardHero } from "@/features/memberships/components/membership-dashboard-hero";
import { MembershipStatCard, MembershipStatCardSkeleton } from "@/features/memberships/components/membership-stat-card";
import { useFacility } from "@/features/facility/hooks/use-facility";
import { useSportFilter } from "@/features/facility/hooks/use-sport-filter";
import { useAllMemberships, useMembershipOutstanding } from "@/features/memberships/hooks/use-membership-dashboard";
import { useMembershipRevenue } from "@/features/memberships/hooks/use-memberships";
import { useFacilityBatches } from "@/features/membership-sessions/hooks/use-facility-batches";
import { membershipRowsForSport } from "@/features/memberships/sport-scope";
import {
  activeInactiveTrend,
  activeMembersChangePct,
  membersDeltaAbs,
  membershipPendingAmountInr,
  summaryFromRows,
} from "@/features/memberships/dashboard-stats";
import { ActiveInactiveBarChart } from "@/features/memberships/components/active-inactive-bar-chart";
import { MembershipRevenueChart } from "@/features/memberships/components/membership-revenue-chart";
import { MembershipListTable } from "@/features/memberships/components/membership-list-table";
import { QuickActionsPanel } from "@/features/memberships/components/quick-actions-panel";
import { MembershipPlansDialog } from "@/features/memberships/components/membership-plans-dialog";
import { todayIso } from "@/features/memberships/revenue-window";
import type { MembershipBatch } from "@/features/membership-sessions/types";
import { useCanEditHere } from "@/features/auth/context/permission-provider";

const inrFmt = (v: number) => `₹${Math.round(v).toLocaleString("en-IN")}`;

/** A stable empty array, so a `?? EMPTY_BATCHES` fallback doesn't create a new reference every render. */
const EMPTY_BATCHES: MembershipBatch[] = [];

/**
 * The Membership Dashboard: an at-a-glance view of the club's members, reached from the
 * sidebar's "Memberships" item. The full searchable/filterable member list still lives at
 * /memberships, one click away via "View All".
 */
export function MembershipDashboardPage() {
  const canEdit = useCanEditHere();
  const router = useRouter();
  const { data: facility, isLoading: facilityLoading } = useFacility();
  const facilityId = facility?.id ?? null;
  // The sports ticked in the top bar (null = All Sports, nothing to filter).
  const sportScope = useSportFilter(facilityId).sportSet;
  const [plansOpen, setPlansOpen] = useState(false);

  const rowsQuery = useAllMemberships(facilityId);
  const batches = useFacilityBatches(facilityId).data ?? EMPTY_BATCHES;
  // Scoped to the top bar's active sport — same rule as the Plans page and every other
  // Membership v1 page: a facility with both Badminton and Cricket (Turf) shows one at a time.
  const rows = useMemo(() => (rowsQuery.data ? membershipRowsForSport(rowsQuery.data, batches, sportScope) : undefined), [rowsQuery.data, batches, sportScope]);

  // With a subset of sports ticked, the revenue card counts only these memberships' payments; under All Sports it
  // is the facility's total.
  const revenueMembershipIds = useMemo(() => (sportScope && rows ? rows.map((r) => r.membershipId) : null), [sportScope, rows]);

  const now = useMemo(() => new Date(), []);
  // The summary RPC has no sport parameter, so it can't be trusted once a sport filter is
  // narrowing things — computed straight from the (already sport-scoped) rows instead, same as
  // the Membership Plans page already does for its own stat cards.
  const summary = useMemo(() => (rows ? summaryFromRows(rows, now) : undefined), [rows, now]);
  const trend = useMemo(() => (rows ? activeInactiveTrend(rows, now, 3) : undefined), [rows, now]);
  // Overall Revenue: every membership payment ever collected (not just this month).
  const overallRevenueQuery = useMembershipRevenue(facilityId, "month", { from: "2000-01-01", to: todayIso(now) }, revenueMembershipIds);
  const overallRevenue = overallRevenueQuery.data ? overallRevenueQuery.data.reduce((sum, p) => sum + p.amountInr, 0) : undefined;
  const outstandingQuery = useMembershipOutstanding(facilityId);
  const pending = useMemo(
    () => (rows && outstandingQuery.data ? membershipPendingAmountInr(rows, outstandingQuery.data, now) : undefined),
    [rows, outstandingQuery.data, now],
  );
  const activeDelta = useMemo(
    () => (rows && summary ? activeMembersChangePct(rows, summary.activeMembers, now) : undefined),
    [rows, summary, now],
  );
  const totalDeltaAbs = summary ? membersDeltaAbs(summary.totalMembers, summary.totalMembersChangePct) : undefined;

  if (facilityLoading) {
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

  if (!facility) {
    return <p className="text-sm text-muted-foreground">Complete your facility setup to manage memberships.</p>;
  }

  return (
    <div className="space-y-6">
      <MembershipDashboardHero
        title="Membership Dashboard"
        subtitle="Manage your members, plans, schedules and grow your community."
        tagline="More Members. More Play. A Stronger Community."
        taglineSub="Keep your members active and engaged."
        onAddMember={canEdit ? () => router.push("/memberships/v1/new") : undefined}
      />

      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        {summary ? (
          <>
            <MembershipStatCard
              icon={Users}
              iconBg="bg-success/15"
              iconColor="text-success"
              value={String(summary.totalMembers)}
              countTo={summary.totalMembers}
              format={(v) => String(v)}
              deltaPct={summary.totalMembersChangePct}
              label="Total Members"
              sub={totalDeltaAbs != null ? `${totalDeltaAbs >= 0 ? "+" : ""}${totalDeltaAbs} from last month` : "No prior month to compare"}
              subTone={totalDeltaAbs != null ? (totalDeltaAbs >= 0 ? "text-success" : "text-destructive") : undefined}
              index={0}
            />
            <MembershipStatCard
              icon={UsersRound}
              iconBg="bg-blue-500/15"
              iconColor="text-blue-600 dark:text-blue-400"
              value={String(summary.activeMembers)}
              countTo={summary.activeMembers}
              format={(v) => String(v)}
              deltaPct={activeDelta ?? null}
              label="Active Members"
              sub="Currently active memberships"
              index={1}
            />
            <MembershipStatCard
              icon={IndianRupee}
              iconBg="bg-warning/15"
              iconColor="text-warning"
              value={overallRevenue !== undefined ? inrFmt(overallRevenue) : "—"}
              countTo={overallRevenue}
              format={inrFmt}
              label="Overall Revenue"
              sub="All membership payments collected"
              index={2}
            />
            <MembershipStatCard
              icon={Wallet}
              iconBg="bg-purple-500/15"
              iconColor="text-purple-600 dark:text-purple-400"
              value={pending !== undefined ? inrFmt(pending.amountInr) : "—"}
              countTo={pending?.amountInr}
              format={inrFmt}
              label="Payment Pending"
              sub={pending !== undefined ? (pending.count > 0 ? `${pending.count} membership${pending.count === 1 ? "" : "s"} unpaid or overdue` : "Nothing pending") : undefined}
              subTone={pending && pending.count > 0 ? "text-destructive" : undefined}
              index={3}
            />
          </>
        ) : (
          Array.from({ length: 4 }).map((_, i) => <MembershipStatCardSkeleton key={i} />)
        )}
      </div>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
        <ActiveInactiveBarChart points={trend} />
        {facilityId && (
          <MembershipRevenueChart facilityId={facilityId} membershipIds={revenueMembershipIds} />
        )}
        <QuickActionsPanel
          onAddMember={() => router.push("/memberships/v1/new")}
          onCreatePlan={() => router.push("/memberships/v1/plans")}
          onManageSchedule={() => router.push("/memberships/v1/schedule")}
        />
      </div>

      <div className="space-y-4">
        <MembershipListTable rows={rows} />

        <div className="stat-enter flex flex-col items-start justify-between gap-4 overflow-hidden rounded-2xl bg-gradient-to-r from-[#06301F] to-[#0B7A55] p-6 sm:flex-row sm:items-center" style={{ "--stat-delay": "460ms" } as React.CSSProperties}>
          <div>
            <p className="text-lg font-semibold text-white">Build a Healthier, Happier Community</p>
            <p className="mt-1 text-sm text-white/80">Memberships bring people together.</p>
          </div>
          <button
            type="button"
            onClick={() => setPlansOpen(true)}
            className="flex h-10 shrink-0 items-center gap-2 whitespace-nowrap rounded-[10px] bg-white px-4 text-sm font-semibold text-[#06301F] transition-opacity hover:opacity-90"
          >
            Grow Your Club →
          </button>
        </div>
      </div>

      {facilityId && <MembershipPlansDialog open={plansOpen} onOpenChange={setPlansOpen} facilityId={facilityId} />}
    </div>
  );
}
