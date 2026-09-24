"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { BadgeIndianRupee, ChevronRight, CircleCheck, LayoutGrid, Plus, Settings2, Users } from "lucide-react";
import { Card } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { cn } from "@/lib/utils";
import { useFacility } from "@/features/facility/hooks/use-facility";
import { useActiveFacilitySportId } from "@/features/facility/hooks/use-active-facility-sport";
import { useAllMemberships } from "@/features/memberships/hooks/use-membership-dashboard";
import { useFacilityBatches } from "@/features/membership-sessions/hooks/use-facility-batches";
import { MembershipStatCard, MembershipStatCardSkeleton } from "@/features/memberships/components/membership-stat-card";
import { MembershipPlansDialog } from "@/features/memberships/components/membership-plans-dialog";
import { PlanCard } from "@/features/memberships/components/plan-card";
import { PlansTable } from "@/features/memberships/components/plans-table";
import { planBadges, planStats } from "@/features/memberships/plan-insights";
import { membershipRowsForSport, plansForSport } from "@/features/memberships/sport-scope";
import { getMembershipService } from "@/services/memberships";
import type { MembershipPlan } from "@/features/memberships/types";
import type { MembershipBatch } from "@/features/membership-sessions/types";

/** A stable empty array, so a `?? EMPTY_BATCHES` fallback doesn't create a new reference every render. */
const EMPTY_BATCHES: MembershipBatch[] = [];

/**
 * This page's surfaces have no drawn border. Instead each card is slightly translucent over a
 * blur, edged with a light inner ring and lifted on a soft shadow — so it reads as glass rather
 * than an outlined box.
 */
const GLASS =
  "border-0 bg-card/70 shadow-[0_6px_24px_rgba(16,40,34,0.07)] ring-1 ring-white/60 backdrop-blur-md dark:bg-card/50 dark:ring-white/10";

function inr(v: number): string {
  return `₹${v.toLocaleString("en-IN")}`;
}

/**
 * Membership Plans: what the club offers, how many members are on each plan and what that
 * bills per month, with the plans themselves listed underneath.
 *
 * Plan counts and revenue are worked out from the memberships actually on each plan, so the
 * figures here always agree with the dashboard's.
 */
export function MembershipPlansPage() {
  const router = useRouter();
  const { data: facility, isLoading: facilityLoading } = useFacility();
  const facilityId = facility?.id ?? null;
  const activeSportId = useActiveFacilitySportId(facilityId);

  const [allPlans, setAllPlans] = useState<MembershipPlan[] | null>(null);
  const [plansOpen, setPlansOpen] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const rowsQuery = useAllMemberships(facilityId);
  const allRows = useMemo(() => rowsQuery.data ?? [], [rowsQuery.data]);
  const batchesQuery = useFacilityBatches(facilityId);
  const batches = batchesQuery.data ?? EMPTY_BATCHES;

  const loadPlans = useCallback(() => {
    if (!facilityId) return;
    getMembershipService()
      .getFacilityPlans(facilityId)
      .then(setAllPlans)
      .catch(() => setError("Unable to load plans. Please try again."));
  }, [facilityId]);

  useEffect(loadPlans, [loadPlans]);
  // The plans dialog creates and edits plans; pick its changes up when it closes.
  useEffect(() => {
    if (!plansOpen) loadPlans();
  }, [plansOpen, loadPlans]);

  // Scoped to the top bar's active sport — a facility with both Badminton and Cricket (Turf)
  // shows only one sport's plans/members/revenue at a time; switching sport up there switches
  // what's shown here, exactly like the Bookings and Dashboard pages already do for courts.
  const plans = useMemo(() => (allPlans ? plansForSport(allPlans, batches, activeSportId) : null), [allPlans, batches, activeSportId]);
  const rows = useMemo(() => membershipRowsForSport(allRows, batches, activeSportId), [allRows, batches, activeSportId]);

  const stats = plans ? planStats(plans, rows) : null;
  const badges = useMemo(() => (plans ? planBadges(plans, rows) : new Map()), [plans, rows]);
  const popular = (plans ?? []).filter((p) => p.isActive).slice(0, 4);

  async function toggleActive(plan: MembershipPlan) {
    try {
      await getMembershipService().updatePlan(plan.id, { isActive: !plan.isActive });
      loadPlans();
    } catch {
      setError("Unable to update that plan. Please try again.");
    }
  }

  if (facilityLoading) {
    return (
      <div className="space-y-6">
        <Skeleton className="h-24 w-full rounded-2xl" />
        <Skeleton className="h-28 w-full rounded-xl" />
        <Skeleton className="h-96 w-full rounded-xl" />
      </div>
    );
  }

  if (!facility) {
    return <p className="text-sm text-muted-foreground">Complete your facility setup to manage membership plans.</p>;
  }

  return (
    <div className="space-y-5">
      <nav aria-label="Breadcrumb" className="flex items-center gap-1 text-xs text-muted-foreground">
        <Link href="/memberships/v1" className="hover:text-foreground">
          Membership
        </Link>
        <ChevronRight className="h-3.5 w-3.5" aria-hidden />
        <span className="font-medium text-foreground">Membership Plans</span>
      </nav>

      <div className={cn("flex flex-col overflow-hidden rounded-2xl lg:h-[92px] lg:flex-row lg:items-stretch", GLASS)}>
        <div className="flex min-w-0 flex-col justify-center gap-1 px-6 py-4 lg:w-[42%]">
          <h1 className="truncate text-2xl font-bold text-black dark:text-foreground">Membership Plans</h1>
          <p className="truncate text-sm text-muted-foreground">
            Create and manage membership plans for your club. Offer flexible plans with dedicated court timings.
          </p>
        </div>
        {/* Hidden on mobile/tablet — decorative only; desktop (lg+) is unaffected. */}
        <div
          className="relative hidden flex-1 items-center px-6 lg:flex"
          style={{
            backgroundImage: `url(/assets/Membership_Dashboard.png), linear-gradient(to right, hsl(var(--card)) 0%, #EAF9F1 22%, #EAF9F1 100%)`,
            backgroundSize: "60%, 100% 100%",
            backgroundPosition: "right 12px center, left center",
            backgroundRepeat: "no-repeat, no-repeat",
          }}
        >
          <div
            aria-hidden
            className="pointer-events-none absolute inset-y-0 left-0 w-[62%]"
            style={{ backgroundImage: "linear-gradient(to right, transparent 0%, #EAF9F1 14%, #EAF9F1 40%, transparent 100%)" }}
          />
          <div className="relative z-10 min-w-0">
            <p className="text-[15px] font-bold leading-snug text-black">Build a Stronger Community</p>
            <p className="mt-1 text-xs text-black/70">
              Create membership plans that give players a consistent time to play and grow together.
            </p>
          </div>
        </div>
      </div>

      {/* Four equal tiles sharing the row with the button at the end, as in the design. */}
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-[repeat(4,minmax(0,1fr))_auto]">
        {stats ? (
          <>
            <MembershipStatCard
              icon={LayoutGrid}
              iconBg="bg-blue-500/15"
              iconColor="text-blue-600 dark:text-blue-400"
              value={String(stats.totalPlans)}
              countTo={stats.totalPlans}
              format={(v) => String(v)}
              label="Total Plans"
              sub="Across your club"
              index={0}
              className={GLASS}
              compact
            />
            <MembershipStatCard
              icon={CircleCheck}
              iconBg="bg-success/15"
              iconColor="text-success"
              value={String(stats.activePlans)}
              countTo={stats.activePlans}
              format={(v) => String(v)}
              label="Active Plans"
              sub="Open for sign-ups"
              index={1}
              className={GLASS}
              compact
            />
            <MembershipStatCard
              icon={Users}
              iconBg="bg-purple-500/15"
              iconColor="text-purple-600 dark:text-purple-400"
              value={String(stats.totalMembers)}
              countTo={stats.totalMembers}
              format={(v) => String(v)}
              label="Total Members"
              sub="On a membership plan"
              index={2}
              className={GLASS}
              compact
            />
            <MembershipStatCard
              icon={BadgeIndianRupee}
              iconBg="bg-warning/15"
              iconColor="text-warning"
              value={inr(stats.monthlyRevenueEstInr)}
              label="Monthly Revenue (Est.)"
              sub="From current plan members"
              index={3}
              className={GLASS}
              compact
            />
          </>
        ) : (
          Array.from({ length: 4 }).map((_, i) => <MembershipStatCardSkeleton key={i} compact />)
        )}

        {/* Plan Customization sits at the end of this row, in place of the old button — it
            carries the Create New Plan action itself. */}
        <Card
          className={cn("stat-enter flex flex-col gap-2.5 rounded-xl p-3 lg:w-[300px]", GLASS)}
          style={{ "--stat-delay": "280ms" } as React.CSSProperties}
        >
          <div className="flex items-start gap-2.5">
            <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-blue-500/15 text-blue-600 dark:text-blue-400">
              <Settings2 className="h-5 w-5" aria-hidden />
            </span>
            <div className="min-w-0">
              <p className="text-sm font-semibold">Plan Customization</p>
              <p className="mt-0.5 text-[11px] leading-snug text-muted-foreground">
                Create custom plans with their own durations, pricing, court access and day/time configurations.
              </p>
            </div>
          </div>
          <button
            type="button"
            onClick={() => router.push("/memberships/v1/plans/new")}
            className="flex h-9 w-full items-center justify-center gap-2 rounded-lg bg-[#0B7A55] text-sm font-semibold text-white transition-opacity hover:opacity-90 dark:bg-primary dark:text-primary-foreground"
          >
            <Plus className="h-4 w-4" aria-hidden />
            Create New Plan
          </button>
        </Card>
      </div>

      {error && <p className="text-sm text-destructive">{error}</p>}

      <Card className={cn("stat-enter space-y-4 rounded-xl p-5", GLASS)} style={{ "--stat-delay": "300ms" } as React.CSSProperties}>
        <div>
          <h2 className="text-base font-bold text-black dark:text-foreground">Popular Plans</h2>
          <p className="text-xs text-muted-foreground">Quick view of your active membership plans.</p>
        </div>

        {!plans ? (
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
            {Array.from({ length: 4 }).map((_, i) => (
              <Skeleton key={i} className="h-72 rounded-2xl" />
            ))}
          </div>
        ) : popular.length === 0 ? (
          <p className="py-10 text-center text-sm text-muted-foreground">
            No active plans yet. Create one to start offering memberships.
          </p>
        ) : (
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
            {popular.map((p, i) => (
              <PlanCard key={p.id} plan={p} badge={badges.get(p.id)} index={i} glass onViewDetails={() => setPlansOpen(true)} />
            ))}
          </div>
        )}
      </Card>

      {plans ? (
        <PlansTable
          plans={plans}
          rows={rows}
          badges={badges}
          className={GLASS}
          onEdit={() => setPlansOpen(true)}
          onToggleActive={toggleActive}
        />
      ) : (
        <Skeleton className="h-80 w-full rounded-xl" />
      )}

      {facilityId && <MembershipPlansDialog open={plansOpen} onOpenChange={setPlansOpen} facilityId={facilityId} />}
    </div>
  );
}
