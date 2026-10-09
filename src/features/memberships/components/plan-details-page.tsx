"use client";

import { useMemo, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import {
  Check,
  ChevronLeft,
  ChevronRight,
  CalendarDays,
  Eye,
  IndianRupee,
  MoreHorizontal,
  Pencil,
  Power,
  Search,
  Trophy,
  Users,
  Wallet,
} from "lucide-react";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { SelectField } from "@/components/shared/select-field";
import { EditBenefitsDialog, EditPlanDialog, EditSlotsDialog } from "@/features/memberships/components/plan-edit-dialogs";
import { useFacility } from "@/features/facility/hooks/use-facility";
import { useFacilityBatches } from "@/features/membership-sessions/hooks/use-facility-batches";
import { useAllMemberships } from "@/features/memberships/hooks/use-membership-dashboard";
import { usePlayingAreasList } from "@/features/memberships/hooks/use-member-schedule";
import { durationLabel, planFeatures, splitPlanName } from "@/features/memberships/plan-insights";
import { featureCountLabel, planCategoryLabel, planTotalAmountInr } from "@/features/memberships/plan-created";
import { planSlotsFor } from "@/features/memberships/plan-slots";
import {
  filterPlanMembers,
  initialsOf,
  membersOfPlan,
  paginate,
  planRevenue,
  slotsByDay,
  type MemberStatusFilter,
  type PlanSlotDetail,
} from "@/features/memberships/plan-detail-data";
import { formatClock } from "@/features/memberships/slot-format";
import { findDuplicatePlan } from "@/features/memberships/duplicate-guards";
import { getMembershipService } from "@/services/memberships";
import { getFinanceService } from "@/services/finance";
import { ServiceError } from "@/services/shared/service-error";
import type { MembershipPlan } from "@/features/memberships/types";
import { cn } from "@/lib/utils";

type TabKey = "overview" | "benefits" | "slots" | "members" | "payments";
const TABS: { key: TabKey; label: string }[] = [
  { key: "overview", label: "Overview" },
  { key: "benefits", label: "Benefits" },
  { key: "slots", label: "Slots" },
  { key: "members", label: "Members" },
  { key: "payments", label: "Payments & History" },
];

const MEMBERS_PER_PAGE = 5;

function inr(v: number): string {
  return `₹${v.toLocaleString("en-IN")}`;
}
function fmtDate(iso: string): string {
  return new Date(iso.length === 10 ? `${iso}T00:00:00` : iso).toLocaleDateString("en-IN", { day: "2-digit", month: "short", year: "numeric" });
}
function fmtDateTime(iso: string): string {
  const d = new Date(iso);
  return `${fmtDate(iso)}, ${d.toLocaleTimeString("en-IN", { hour: "numeric", minute: "2-digit", hour12: true }).toUpperCase()}`;
}

function StatusPill({ on, children }: { on: boolean; children: React.ReactNode }) {
  return (
    <span
      className={cn(
        "inline-flex items-center gap-1.5 whitespace-nowrap rounded-full px-2.5 py-0.5 text-xs font-medium",
        on ? "bg-success/15 text-success" : "bg-muted text-muted-foreground",
      )}
    >
      <span className="h-1.5 w-1.5 rounded-full bg-current" aria-hidden />
      {children}
    </span>
  );
}

function Stat({ icon: Icon, tone, value, label }: { icon: React.ComponentType<{ className?: string }>; tone: string; value: string; label: string }) {
  return (
    <div className="flex items-center gap-2.5">
      <span className={cn("flex h-9 w-9 shrink-0 items-center justify-center rounded-lg", tone)}>
        <Icon className="h-4 w-4" aria-hidden />
      </span>
      <div>
        <p className="text-sm font-bold text-black dark:text-foreground">{value}</p>
        <p className="text-[11px] text-muted-foreground">{label}</p>
      </div>
    </div>
  );
}

/**
 * One plan, in full — Overview, Benefits, Slots, Members and Payments & History. The plan can be
 * edited here, except its name and duration, which stay as created.
 */
export function PlanDetailsPage({ planId }: { planId: string }) {
  const router = useRouter();
  const queryClient = useQueryClient();
  const { data: facility, isLoading: facilityLoading } = useFacility();
  const facilityId = facility?.id ?? null;

  const [tab, setTab] = useState<TabKey>("overview");
  const [dialog, setDialog] = useState<"plan" | "benefits" | "slots" | "capacity" | null>(null);
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);

  const plansQuery = useQuery<MembershipPlan[]>({
    queryKey: ["membership-plans-all", facilityId],
    enabled: Boolean(facilityId),
    queryFn: () => getMembershipService().getFacilityPlans(facilityId!),
  });
  const plan = plansQuery.data?.find((p) => p.id === planId);

  const batches = useFacilityBatches(facilityId).data;
  const assignableQuery = useQuery({
    queryKey: ["plan-assignable-batches", facilityId, planId],
    enabled: Boolean(facilityId),
    queryFn: () => getMembershipService().listAssignableBatches(facilityId!, planId),
  });
  const areas = usePlayingAreasList(facilityId).data;
  const allRows = useAllMemberships(facilityId).data;

  const courtNames = useMemo(() => new Map((areas ?? []).map((a) => [a.id, a.name])), [areas]);
  const courts = useMemo(
    () => (areas ?? []).filter((a) => a.status === "ACTIVE").map((a) => ({ id: a.id, name: a.name, facilitySportId: a.facilitySportId })),
    [areas],
  );
  const slots: PlanSlotDetail[] = useMemo(() => {
    const sportOf = new Map((batches ?? []).map((b) => [b.id, b.facilitySportId]));
    const counts = new Map((assignableQuery.data ?? []).map((b) => [b.batchId, b]));
    return planSlotsFor(batches ?? [], planId, courtNames).map((s) => ({
      ...s,
      capacity: counts.get(s.batchId)?.capacity ?? 0,
      enrolledCount: counts.get(s.batchId)?.enrolledCount ?? 0,
      facilitySportId: sportOf.get(s.batchId) ?? "",
    }));
  }, [batches, assignableQuery.data, planId, courtNames]);
  const sportLabel = useMemo(() => [...new Set((assignableQuery.data ?? []).map((b) => b.sportName).filter(Boolean))].join(", "), [assignableQuery.data]);

  const members = useMemo(() => plan ? membersOfPlan(allRows ?? [], plan) : [], [allRows, plan]);
  const activeMembers = members.filter((m) => m.status === "active").length;

  const paymentsQuery = useQuery({
    queryKey: ["plan-payments", facilityId, planId],
    enabled: Boolean(facilityId) && tab === "payments",
    queryFn: async () => {
      const now = new Date();
      const start = new Date(now.getFullYear() - 3, now.getMonth(), now.getDate());
      const iso = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
      const page = await getFinanceService().listTransactions({
        facilityId: facilityId!,
        sourceType: "MEMBERSHIP",
        dateRange: { preset: "CUSTOM", startDate: iso(start), endDate: iso(now) },
        limit: 500,
        offset: 0,
      });
      return page.transactions;
    },
  });
  const planPayments = useMemo(() => {
    const ids = new Set(members.map((m) => m.membershipId));
    return (paymentsQuery.data ?? []).filter((t) => t.membershipId && ids.has(t.membershipId));
  }, [paymentsQuery.data, members]);

  function refreshPlan(saved?: MembershipPlan) {
    if (saved) {
      queryClient.setQueryData<MembershipPlan[]>(["membership-plans-all", facilityId], (old) => old?.map((p) => (p.id === saved.id ? saved : p)));
    }
    queryClient.invalidateQueries({ queryKey: ["membership-plans-all"] });
    queryClient.invalidateQueries({ queryKey: ["membership-list"] });
    queryClient.invalidateQueries({ queryKey: ["membership-dashboard-rows"] });
  }
  function refreshSlots() {
    queryClient.invalidateQueries({ queryKey: ["membership-batches"] });
    queryClient.invalidateQueries({ queryKey: ["plan-assignable-batches"] });
    queryClient.invalidateQueries({ queryKey: ["membership-detail"] });
    queryClient.invalidateQueries({ queryKey: ["membership-dashboard-rows"] });
  }

  async function toggleActive() {
    if (!plan) return;
    setBusy(true);
    try {
      refreshPlan(await getMembershipService().updatePlan(plan.id, { isActive: !plan.isActive }));
    } catch (err) {
      setNotice(err instanceof ServiceError ? err.message : "Unable to update the plan.");
    } finally {
      setBusy(false);
    }
  }

  if (facilityLoading || plansQuery.isLoading) {
    return (
      <div className="space-y-5">
        <Skeleton className="h-32 w-full rounded-2xl" />
        <Skeleton className="h-72 w-full rounded-xl" />
      </div>
    );
  }
  if (!plan) {
    return (
      <p className="text-sm text-muted-foreground">
        We couldn&apos;t find this plan.{" "}
        <Link href="/memberships/v1/plans" className="font-medium text-primary hover:underline">
          Back to plans
        </Link>
      </p>
    );
  }

  const name = splitPlanName(plan.name);
  const months = Math.max(1, Math.round(plan.durationDays / 30));
  const perMonth = Math.round(plan.priceInr / months);
  const features = planFeatures(plan);

  return (
    <div className="space-y-5">
      <nav aria-label="Breadcrumb" className="flex items-center gap-1 text-xs text-muted-foreground">
        <Link href="/memberships/v1/plans" className="hover:text-foreground">
          Membership Plans
        </Link>
        <ChevronRight className="h-3.5 w-3.5" aria-hidden />
        <span className="font-medium text-foreground">{name.main}</span>
      </nav>

      <Card className="rounded-2xl p-5">
        <div className="flex flex-col gap-4 sm:flex-row sm:items-start">
          <span className="flex h-28 w-28 shrink-0 items-center justify-center rounded-2xl bg-[#0B9B63]/15 text-[#0B7A55]">
            <Trophy className="h-12 w-12" aria-hidden />
          </span>
          <div className="min-w-0 flex-1 space-y-2">
            <div className="flex flex-wrap items-center gap-3">
              <h1 className="text-2xl font-bold text-black dark:text-foreground">{name.main}</h1>
              <StatusPill on={plan.isActive}>{plan.isActive ? "Active" : "Inactive"}</StatusPill>
              {plan.badgeText && <span className="rounded-full bg-[#0B9B63]/15 px-2.5 py-0.5 text-xs font-semibold text-[#0B7A55]">{plan.badgeText}</span>}
            </div>
            {name.detail && <p className="text-sm text-muted-foreground">{name.detail}</p>}
            {plan.description && <p className="text-sm text-muted-foreground">{plan.description}</p>}
            <div className="grid grid-cols-2 gap-4 pt-1 lg:grid-cols-4">
              <Stat icon={CalendarDays} tone="bg-success/15 text-success" value={durationLabel(plan.durationDays)} label="Duration" />
              <Stat icon={IndianRupee} tone="bg-warning/20 text-warning" value={inr(perMonth)} label="Price / month" />
              <Stat icon={Wallet} tone="bg-blue-500/15 text-blue-600 dark:text-blue-400" value={String(slots.length)} label={slots.length === 1 ? "Time slot" : "Time slots"} />
              <Stat icon={Users} tone="bg-destructive/15 text-destructive" value={String(activeMembers)} label="Active Members" />
            </div>
          </div>
          <div className="flex shrink-0 items-center gap-2">
            <button
              type="button"
              onClick={() => setDialog("plan")}
              className="flex h-10 items-center gap-2 rounded-lg border border-[#0B9B63] bg-card px-4 text-sm font-semibold text-[#0B7A55] transition-colors hover:bg-[#0B9B63]/5"
            >
              <Pencil className="h-4 w-4" aria-hidden />
              Edit Plan
            </button>
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <button
                  type="button"
                  aria-label="More actions"
                  disabled={busy}
                  className="flex h-10 w-10 items-center justify-center rounded-lg border border-input text-muted-foreground transition-colors hover:bg-accent"
                >
                  <MoreHorizontal className="h-4 w-4" />
                </button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end" className="w-48">
                <DropdownMenuItem onClick={toggleActive}>
                  <Power className="mr-2 h-4 w-4" />
                  {plan.isActive ? "Deactivate" : "Activate"}
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          </div>
        </div>
        {notice && <p className="mt-3 text-sm text-destructive">{notice}</p>}
      </Card>

      <div role="tablist" className="flex gap-6 overflow-x-auto border-b border-border">
        {TABS.map((t) => (
          <button
            key={t.key}
            type="button"
            role="tab"
            aria-selected={tab === t.key}
            onClick={() => setTab(t.key)}
            className={cn(
              "-mb-px whitespace-nowrap border-b-2 px-1 pb-3 text-sm transition-colors",
              tab === t.key ? "border-[#0B9B63] font-semibold text-[#0B7A55]" : "border-transparent text-muted-foreground hover:text-foreground",
            )}
          >
            {t.label}
          </button>
        ))}
      </div>

      {tab === "overview" && (
        <div className="grid grid-cols-1 gap-5 lg:grid-cols-[1fr_340px]">
          <Card className="space-y-1 rounded-xl p-5">
            <h2 className="pb-2 text-base font-bold text-black dark:text-foreground">Plan Information</h2>
            <dl className="divide-y divide-border text-sm">
              {(
                [
                  ["Plan Name", plan.name],
                  ["Description", plan.description || "—"],
                  ["Sport", sportLabel || "—"],
                  ["Plan Type", planCategoryLabel(plan.category) ?? (plan.planType === "RECURRING" ? "Recurring" : "Time based")],
                  ["Duration", durationLabel(plan.durationDays)],
                  ["Price", `${inr(plan.priceInr)} / ${months === 1 ? "month" : durationLabel(plan.durationDays)}`],
                  ...(plan.joiningFeeInr ? [["Joining Fee", inr(plan.joiningFeeInr)]] : []),
                  ...(plan.securityDepositInr ? [["Security Deposit", inr(plan.securityDepositInr)]] : []),
                  ["Total Amount", inr(planTotalAmountInr(plan))],
                ] as [string, string][]
              ).map(([k, v]) => (
                <div key={k} className="grid grid-cols-[140px_1fr] gap-3 py-2.5">
                  <dt className="text-muted-foreground">{k}</dt>
                  <dd className="font-medium text-foreground">{v}</dd>
                </div>
              ))}
              <div className="grid grid-cols-[140px_1fr] gap-3 py-2.5">
                <dt className="text-muted-foreground">Status</dt>
                <dd>
                  <StatusPill on={plan.isActive}>{plan.isActive ? "Active" : "Inactive"}</StatusPill>
                </dd>
              </div>
              <div className="grid grid-cols-[140px_1fr] gap-3 py-2.5">
                <dt className="text-muted-foreground">Created On</dt>
                <dd className="font-medium text-foreground">{fmtDateTime(plan.createdAt)}</dd>
              </div>
            </dl>
          </Card>

          <div className="space-y-5">
            <Card className="space-y-3 rounded-xl p-5">
              <h2 className="text-base font-bold text-black dark:text-foreground">Plan Highlights</h2>
              <ul className="space-y-2.5">
                {features.slice(0, 4).map((f) => (
                  <li key={f} className="flex items-center gap-2.5 text-sm">
                    <span className="flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-[#0B9B63]/20 text-[#0B7A55]">
                      <Check className="h-3 w-3" strokeWidth={3} aria-hidden />
                    </span>
                    {f}
                  </li>
                ))}
              </ul>
              {features.length > 4 && <p className="text-xs text-muted-foreground">+{features.length - 4} more — see Benefits.</p>}
            </Card>

          </div>
        </div>
      )}

      {tab === "benefits" && (
        <Card className="space-y-4 rounded-xl p-5">
          <div className="flex items-center justify-between gap-3">
            <div>
              <h2 className="text-base font-bold text-black dark:text-foreground">Included Benefits</h2>
              <p className="text-xs text-muted-foreground">{featureCountLabel(features.length)} with this plan.</p>
            </div>
            <button
              type="button"
              onClick={() => setDialog("benefits")}
              className="flex h-9 items-center gap-2 rounded-lg border border-[#0B9B63] bg-card px-3 text-sm font-semibold text-[#0B7A55] transition-colors hover:bg-[#0B9B63]/5"
            >
              <Pencil className="h-3.5 w-3.5" aria-hidden />
              Edit Benefits
            </button>
          </div>
          <ul className="space-y-3">
            {features.map((f) => (
              <li key={f} className="flex items-center gap-3">
                <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-[#0B9B63]/15 text-[#0B7A55]">
                  <Check className="h-5 w-5" aria-hidden />
                </span>
                <span className="text-sm font-semibold text-foreground">{f}</span>
              </li>
            ))}
          </ul>
        </Card>
      )}

      {tab === "slots" && (
        <div className="space-y-5">
          <Card className="space-y-3 rounded-xl p-5">
            <h2 className="text-base font-bold text-black dark:text-foreground">Slot Configuration</h2>
            {slots.length === 0 ? (
              <p className="text-sm text-muted-foreground">This plan has no slots yet.</p>
            ) : (
              <div className="divide-y divide-border rounded-lg bg-muted/30">
                {slots.map((s) => (
                  <div key={s.batchId} className="flex items-center justify-between gap-3 px-4 py-3 text-sm">
                    <span className="text-muted-foreground">
                      {s.courtName} · {formatClock(s.startTime)} - {formatClock(s.endTime)}
                    </span>
                    <span className="flex items-center gap-3">
                      <span className="text-xs text-muted-foreground">{s.enrolledCount} on slot</span>
                      <span className="font-semibold tabular-nums">Capacity {s.capacity}</span>
                    </span>
                  </div>
                ))}
              </div>
            )}
            {slots.length > 0 && (
              <div className="flex justify-end">
                <button
                  type="button"
                  onClick={() => setDialog("capacity")}
                  className="flex h-9 items-center gap-2 rounded-lg border border-[#0B9B63] bg-card px-4 text-sm font-semibold text-[#0B7A55] transition-colors hover:bg-[#0B9B63]/5"
                >
                  <Pencil className="h-3.5 w-3.5" aria-hidden />
                  Edit
                </button>
              </div>
            )}
          </Card>

          <Card className="space-y-3 rounded-xl p-5">
            <div className="flex items-start justify-between gap-3">
              <div>
                <h2 className="text-base font-bold text-black dark:text-foreground">Allocated Time Slots</h2>
                <p className="text-xs text-muted-foreground">Members with this plan can book the following time slots.</p>
              </div>
              {slots.length > 0 && (
                <button
                  type="button"
                  onClick={() => setDialog("slots")}
                  className="flex h-9 items-center gap-2 rounded-lg border border-[#0B9B63] bg-card px-4 text-sm font-semibold text-[#0B7A55] transition-colors hover:bg-[#0B9B63]/5"
                >
                  <Pencil className="h-3.5 w-3.5" aria-hidden />
                  Edit Slots
                </button>
              )}
            </div>
            <div className="divide-y divide-border rounded-lg border border-border">
              {slotsByDay(slots).map((d) => (
                <div key={d.day} className="grid grid-cols-[120px_1fr_auto] items-center gap-3 px-4 py-3 text-sm">
                  <span className="font-medium">{d.label}</span>
                  <span className="text-muted-foreground">
                    {d.slots.length === 0
                      ? "- Not available"
                      : d.slots.map((s) => `${formatClock(s.startTime)} – ${formatClock(s.endTime)} (${s.courtName})`).join(", ")}
                  </span>
                  <StatusPill on={d.slots.length > 0}>{d.slots.length > 0 ? "Active" : "Inactive"}</StatusPill>
                </div>
              ))}
            </div>
          </Card>
        </div>
      )}

      {tab === "members" && <PlanMembersTab members={members} onOpen={(id) => router.push(`/memberships/${id}`)} onEdit={(id) => router.push(`/memberships/v1/${id}/edit`)} />}

      {tab === "payments" && (
        <PlanPaymentsTab
          loading={paymentsQuery.isLoading}
          failed={paymentsQuery.isError}
          payments={planPayments}
          memberCount={members.length}
        />
      )}

      {dialog === "plan" && <EditPlanDialog plan={plan} otherNames={(plansQuery.data ?? []).filter((p) => p.id !== plan.id).map((p) => p.name)} open onOpenChange={(o) => !o && setDialog(null)} onSaved={refreshPlan} />}
      {dialog === "benefits" && <EditBenefitsDialog plan={plan} open onOpenChange={(o) => !o && setDialog(null)} onSaved={refreshPlan} />}
      {(dialog === "slots" || dialog === "capacity") && (
        <EditSlotsDialog
          slots={slots}
          courts={courts}
          capacityOnly={dialog === "capacity"}
          findDuplicate={(draft) =>
            findDuplicatePlan(
              draft,
              (plansQuery.data ?? []).map((p) => ({
                id: p.id,
                name: p.name,
                slots: (batches ?? []).filter((b) => b.isActive && b.planId === p.id),
              })),
              planId,
            )?.name ?? null
          }
          open
          onOpenChange={(o) => !o && setDialog(null)}
          onSaved={refreshSlots}
        />
      )}
    </div>
  );
}

function PlanMembersTab({
  members,
  onOpen,
  onEdit,
}: {
  members: ReturnType<typeof membersOfPlan>;
  onOpen: (membershipId: string) => void;
  onEdit: (membershipId: string) => void;
}) {
  const [query, setQuery] = useState("");
  const [status, setStatus] = useState<MemberStatusFilter>("all");
  const [page, setPage] = useState(1);
  const filtered = useMemo(() => filterPlanMembers(members, query, status), [members, query, status]);
  const view = paginate(filtered, page, MEMBERS_PER_PAGE);

  return (
    <Card className="space-y-4 rounded-xl p-5">
      <h2 className="text-base font-bold text-black dark:text-foreground">Members ({members.length})</h2>
      <div className="flex flex-col gap-3 sm:flex-row">
        <div className="relative flex-1">
          <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" aria-hidden />
          <Input
            value={query}
            onChange={(e) => {
              setQuery(e.target.value);
              setPage(1);
            }}
            placeholder="Search members..."
            className="pl-9"
          />
        </div>
        <SelectField
          ariaLabel="Status"
          value={status}
          onValueChange={(v) => {
            setStatus(v as MemberStatusFilter);
            setPage(1);
          }}
          options={[
            { value: "all", label: "All" },
            { value: "active", label: "Active" },
            { value: "inactive", label: "Inactive" },
          ]}
          wrapperClassName="sm:w-40"
          className="h-10 w-full rounded-lg border border-input bg-card px-3 text-sm outline-none transition-colors hover:border-foreground/30"
        />
      </div>

      {view.items.length === 0 ? (
        <p className="py-8 text-center text-sm text-muted-foreground">{members.length === 0 ? "No members are on this plan yet." : "No members match."}</p>
      ) : (
        <ul className="divide-y divide-border rounded-lg border border-border">
          {view.items.map((m) => (
            <li key={m.membershipId} className="flex items-center gap-3 px-4 py-3">
              <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-purple-500/15 text-xs font-semibold text-purple-700 dark:text-purple-300">
                {initialsOf(m.memberName)}
              </span>
              <div className="min-w-0 flex-1">
                <p className="truncate text-sm font-semibold">{m.memberName}</p>
                <p className="text-xs text-muted-foreground">{m.memberPhone}</p>
              </div>
              <StatusPill on={m.status === "active"}>{m.status === "active" ? "Active" : m.status === "inactive" ? "Inactive" : "Payment pending"}</StatusPill>
              <span className="hidden whitespace-nowrap text-xs text-muted-foreground sm:inline">Joined {fmtDate(m.startDate)}</span>
              <DropdownMenu>
                <DropdownMenuTrigger asChild>
                  <button
                    type="button"
                    aria-label={`Actions for ${m.memberName}`}
                    className="flex h-8 w-8 items-center justify-center rounded-lg border border-input text-muted-foreground hover:bg-accent"
                  >
                    <MoreHorizontal className="h-4 w-4" />
                  </button>
                </DropdownMenuTrigger>
                <DropdownMenuContent align="end" className="w-44">
                  <DropdownMenuItem onClick={() => onOpen(m.membershipId)}>
                    <Eye className="mr-2 h-4 w-4" />
                    View details
                  </DropdownMenuItem>
                  <DropdownMenuItem onClick={() => onEdit(m.membershipId)}>
                    <Pencil className="mr-2 h-4 w-4" />
                    Edit member
                  </DropdownMenuItem>
                </DropdownMenuContent>
              </DropdownMenu>
            </li>
          ))}
        </ul>
      )}

      {view.pages > 1 && (
        <div className="flex items-center justify-center gap-2">
          <button
            type="button"
            aria-label="Previous page"
            disabled={view.page === 1}
            onClick={() => setPage(view.page - 1)}
            className="flex h-8 w-8 items-center justify-center rounded-lg border border-input disabled:opacity-40"
          >
            <ChevronLeft className="h-4 w-4" />
          </button>
          {Array.from({ length: view.pages }, (_, i) => i + 1).map((p) => (
            <button
              key={p}
              type="button"
              onClick={() => setPage(p)}
              aria-current={p === view.page}
              className={cn(
                "h-8 w-8 rounded-lg text-sm",
                p === view.page ? "bg-[#0B9B63] font-semibold text-white" : "border border-input hover:bg-accent",
              )}
            >
              {p}
            </button>
          ))}
          <button
            type="button"
            aria-label="Next page"
            disabled={view.page === view.pages}
            onClick={() => setPage(view.page + 1)}
            className="flex h-8 w-8 items-center justify-center rounded-lg border border-input disabled:opacity-40"
          >
            <ChevronRight className="h-4 w-4" />
          </button>
        </div>
      )}
    </Card>
  );
}

function PlanPaymentsTab({
  loading,
  failed,
  payments,
  memberCount,
}: {
  loading: boolean;
  failed: boolean;
  payments: { id: string; customerName: string | null; amountMinor: number; paidAt: string | null; createdAt: string; status: string; membershipId: string | null }[];
  memberCount: number;
}) {
  if (loading) return <Skeleton className="h-64 w-full rounded-xl" />;
  if (failed) return <p className="text-sm text-muted-foreground">We couldn&apos;t load this plan&apos;s payments.</p>;

  const revenue = planRevenue(payments);
  const recent = [...payments].sort((a, b) => (b.paidAt ?? b.createdAt).localeCompare(a.paidAt ?? a.createdAt)).slice(0, 10);
  const cards = [
    { label: "Total Revenue", value: inr(revenue.totalMinor / 100), icon: Wallet, tone: "bg-success/15 text-success" },
    { label: "Total Members", value: String(memberCount), icon: Users, tone: "bg-blue-500/15 text-blue-600 dark:text-blue-400" },
    { label: "Avg. per Member", value: inr(revenue.avgPerMemberMinor / 100), icon: IndianRupee, tone: "bg-purple-500/15 text-purple-600 dark:text-purple-400" },
  ];

  return (
    <div className="space-y-5">
      <div className="space-y-3">
        <h2 className="text-base font-bold text-black dark:text-foreground">Revenue Overview</h2>
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
          {cards.map((c) => (
            <Card key={c.label} className="flex items-center gap-3 rounded-xl p-4">
              <span className={cn("flex h-11 w-11 shrink-0 items-center justify-center rounded-lg", c.tone)}>
                <c.icon className="h-5 w-5" aria-hidden />
              </span>
              <div>
                <p className="text-xl font-bold tabular-nums text-black dark:text-foreground">{c.value}</p>
                <p className="text-xs text-muted-foreground">{c.label}</p>
              </div>
            </Card>
          ))}
        </div>
      </div>

      <Card className="space-y-3 rounded-xl p-5">
        <h2 className="text-base font-bold text-black dark:text-foreground">Recent Payments</h2>
        {recent.length === 0 ? (
          <p className="py-6 text-center text-sm text-muted-foreground">No payments yet.</p>
        ) : (
          <div className="overflow-x-auto rounded-lg border border-border">
            <table className="w-full text-sm">
              <thead className="bg-muted/40 text-left text-xs text-muted-foreground">
                <tr>
                  <th className="px-4 py-2.5 font-medium">Member</th>
                  <th className="px-4 py-2.5 font-medium">Amount</th>
                  <th className="px-4 py-2.5 font-medium">Payment Date</th>
                  <th className="px-4 py-2.5 font-medium">Status</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-border">
                {recent.map((p) => (
                  <tr key={p.id}>
                    <td className="px-4 py-3 font-medium">{p.customerName ?? "—"}</td>
                    <td className="px-4 py-3 tabular-nums">{inr(p.amountMinor / 100)}</td>
                    <td className="px-4 py-3 text-muted-foreground">{fmtDate(p.paidAt ?? p.createdAt)}</td>
                    <td className="px-4 py-3">
                      <span
                        className={cn(
                          "rounded-full px-2.5 py-0.5 text-xs font-medium capitalize",
                          p.status === "paid" ? "bg-success/15 text-success" : p.status === "failed" ? "bg-destructive/15 text-destructive" : "bg-warning/20 text-warning",
                        )}
                      >
                        {p.status === "paid" ? "Paid" : p.status}
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>
    </div>
  );
}
