"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { Clock, UserPlus, Users, UsersRound } from "lucide-react";
import { Skeleton } from "@/components/ui/skeleton";
import { MembershipDashboardHero } from "@/features/memberships/components/membership-dashboard-hero";
import { MembershipStatCard, MembershipStatCardSkeleton } from "@/features/memberships/components/membership-stat-card";
import { useFacility } from "@/features/facility/hooks/use-facility";
import { useActiveFacilitySportId } from "@/features/facility/hooks/use-active-facility-sport";
import { useAllMemberships } from "@/features/memberships/hooks/use-membership-dashboard";
import { useFacilityBatches } from "@/features/membership-sessions/hooks/use-facility-batches";
import { membershipRowsForSport } from "@/features/memberships/sport-scope";
import {
  activeInactiveTrend,
  activeMembersChangePct,
  expiringSoon,
  expiringSoonChangePct,
  inactiveChangePct,
  inactiveMembers,
  membersDeltaAbs,
  summaryFromRows,
} from "@/features/memberships/dashboard-stats";
import { ActiveInactiveBarChart } from "@/features/memberships/components/active-inactive-bar-chart";
import { MembershipRevenueChart } from "@/features/memberships/components/membership-revenue-chart";
import { MembershipListTable } from "@/features/memberships/components/membership-list-table";
import { QuickActionsPanel } from "@/features/memberships/components/quick-actions-panel";
import { MembershipPlansDialog } from "@/features/memberships/components/membership-plans-dialog";
import type { MembershipBatch } from "@/features/membership-sessions/types";

/** A stable empty array, so a `?? EMPTY_BATCHES` fallback doesn't create a new reference every render. */
const EMPTY_BATCHES: MembershipBatch[] = [];

/**
 * The Membership Dashboard: an at-a-glance view of the club's members, reached from the
 * sidebar's "Memberships" item. The full searchable/filterable member list still lives at
 * /memberships, one click away via "View All".
 */
export function MembershipDashboardPage() {
  const router = useRouter();
  const { data: facility, isLoading: facilityLoading } = useFacility();
  const facilityId = facility?.id ?? null;
  const activeSportId = useActiveFacilitySportId(facilityId);
  const [plansOpen, setPlansOpen] = useState(false);

  const rowsQuery = useAllMemberships(facilityId);
  const batches = useFacilityBatches(facilityId).data ?? EMPTY_BATCHES;
  // Scoped to the top bar's active sport — same rule as the Plans page and every other
  // Membership v1 page: a facility with both Badminton and Cricket (Turf) shows one at a time.
  const rows = useMemo(() => (rowsQuery.data ? membershipRowsForSport(rowsQuery.data, batches, activeSportId) : undefined), [rowsQuery.data, batches, activeSportId]);

  const now = useMemo(() => new Date(), []);
  // The summary RPC has no sport parameter, so it can't be trusted once a sport filter is
  // narrowing things — computed straight from the (already sport-scoped) rows instead, same as
  // the Membership Plans page already does for its own stat cards.
  const summary = useMemo(() => (rows ? summaryFromRows(rows, now) : undefined), [rows, now]);
  const trend = useMemo(() => (rows ? activeInactiveTrend(rows, now, 6) : undefined), [rows, now]);
  const expiringCount = useMemo(() => (rows ? expiringSoon(rows, now).length : undefined), [rows, now]);
  const expiringDelta = useMemo(() => (rows ? expiringSoonChangePct(rows, now) : undefined), [rows, now]);
  const inactiveCount = useMemo(() => (rows ? inactiveMembers(rows).length : undefined), [rows]);
  const inactiveDelta = useMemo(() => (rows ? inactiveChangePct(rows, now) : undefined), [rows, now]);
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
        onAddMember={() => router.push("/memberships/v1/new")}
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
              icon={Clock}
              iconBg="bg-warning/15"
              iconColor="text-warning"
              value={expiringCount !== undefined ? String(expiringCount) : "—"}
              countTo={expiringCount}
              format={(v) => String(v)}
              deltaPct={expiringDelta ?? null}
              label="Expiring Soon"
              sub="Within next 5 days"
              index={2}
            />
            <MembershipStatCard
              icon={UserPlus}
              iconBg="bg-purple-500/15"
              iconColor="text-purple-600 dark:text-purple-400"
              value={inactiveCount !== undefined ? String(inactiveCount) : "—"}
              countTo={inactiveCount}
              format={(v) => String(v)}
              deltaPct={inactiveDelta ?? null}
              label="Inactive Members"
              sub="No active membership"
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
          <MembershipRevenueChart facilityId={facilityId} revenueInr={summary?.revenueInr} revenueChangePct={summary?.revenueChangePct} />
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
