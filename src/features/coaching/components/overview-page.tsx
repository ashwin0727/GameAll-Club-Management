"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { CalendarPlus, CheckCircle2, ClipboardList, IndianRupee, Star, UserPlus, Users, UsersRound } from "lucide-react";
import { Card } from "@/components/ui/card";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { MembershipDashboardHero } from "@/features/memberships/components/membership-dashboard-hero";
import { MembershipStatCard, MembershipStatCardSkeleton } from "@/features/memberships/components/membership-stat-card";
import { ServiceError } from "@/services/shared/service-error";
import { getCoachingService } from "@/services/coaching";
import { usePermissionContext } from "@/features/auth/context/permission-provider";
import { CoachesListPanel } from "@/features/coaching/components/coaches-list-panel";
import { AddCoachSheet } from "@/features/coaching/components/add-coach-sheet";
import type { CoachingInsights, CoachingOverview } from "@/features/coaching/types";
import { EmptyState, ErrorState, fmtTime, money } from "@/features/coaching/components/shared";

const INSIGHTS_WINDOWS = [
  { value: "30", label: "Last 30 Days" },
  { value: "60", label: "Last 60 Days" },
  { value: "90", label: "Last 90 Days" },
] as const;

/**
 * The Coaching landing page — a hero, four KPI tiles, the searchable coach roster embedded
 * directly (same "hero + embedded list" pattern the Membership Dashboard already established),
 * and a right rail of Upcoming Sessions / Coaching Insights / Quick Actions. Replaces the plain
 * table-of-figures Overview page with the reference design's layout.
 */
export function CoachingOverviewPage() {
  const perms = usePermissionContext();
  const facilityId = perms?.facilityId ?? null;

  const [data, setData] = useState<CoachingOverview | null>(null);
  const [state, setState] = useState<"loading" | "ready" | "error">("loading");
  const [error, setError] = useState<string | null>(null);

  const [insightsDays, setInsightsDays] = useState<30 | 60 | 90>(30);
  const [insights, setInsights] = useState<CoachingInsights | null>(null);
  const [insightsError, setInsightsError] = useState<string | null>(null);

  const [addCoachOpen, setAddCoachOpen] = useState(false);
  // Bumped after a coach is added from the hero/Quick Actions sheet, forcing the roster panel
  // (which owns its own load()) to remount and refetch, since it doesn't expose a refresh handle.
  const [rosterKey, setRosterKey] = useState(0);

  const load = useCallback(async () => {
    if (!facilityId) return;
    setState("loading");
    setError(null);
    try {
      setData(await getCoachingService().getOverview(facilityId));
      setState("ready");
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Unable to load the coaching overview.");
      setState("error");
    }
  }, [facilityId]);

  const loadInsights = useCallback(async () => {
    if (!facilityId) return;
    setInsightsError(null);
    try {
      setInsights(await getCoachingService().getInsights(facilityId, insightsDays));
    } catch (e) {
      setInsightsError(e instanceof ServiceError ? e.message : "Unable to load coaching insights.");
    }
  }, [facilityId, insightsDays]);

  useEffect(() => {
    void load();
  }, [load]);

  useEffect(() => {
    setInsights(null);
    void loadInsights();
  }, [loadInsights]);

  const canSession = perms?.can("COACHING_CREATE_SESSION") ?? false;
  const canCoach = perms?.can("COACHING_MANAGE_COACHES") ?? false;
  const canProgram = perms?.can("COACHING_MANAGE_PROGRAMS") ?? false;

  if (!facilityId) return null;

  if (state === "error") {
    return (
      <div className="space-y-4">
        <MembershipDashboardHero
          title="Coaching"
          subtitle="Manage your coaching team, sessions, and training programs."
          tagline="Better Coaching. Stronger Players."
          taglineSub="Manage coaches, schedule sessions, and grow your community."
          buttonLabel="Add Coach"
          onAddMember={canCoach ? () => setAddCoachOpen(true) : undefined}
        />
        <Card className="p-0">
          <ErrorState message={error ?? ""} onRetry={() => void load()} />
        </Card>
        <AddCoachSheet facilityId={facilityId} open={addCoachOpen} onOpenChange={setAddCoachOpen} />
      </div>
    );
  }

  const totalStudents = data ? data.studentsByProgram.reduce((s, p) => s + p.students, 0) : 0;

  return (
    <div className="space-y-4">
      <MembershipDashboardHero
        title="Coaching"
        subtitle="Manage your coaching team, sessions, and training programs."
        tagline="Better Coaching. Stronger Players."
        taglineSub="Manage coaches, schedule sessions, and grow your community."
        buttonLabel="Add Coach"
        onAddMember={canCoach ? () => setAddCoachOpen(true) : undefined}
      />

      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        {!data ? (
          Array.from({ length: 4 }).map((_, i) => <MembershipStatCardSkeleton key={i} compact />)
        ) : (
          <>
            <MembershipStatCard
              icon={UsersRound}
              iconBg="bg-success/15"
              iconColor="text-success"
              value={String(data.kpis.activeCoaches)}
              label="Active Coaches"
              sub={data.kpis.coachesOnLeave > 0 ? `${data.kpis.coachesOnLeave} on leave` : undefined}
              index={0}
              compact
            />
            <MembershipStatCard
              icon={Users}
              iconBg="bg-blue-500/15"
              iconColor="text-blue-600 dark:text-blue-400"
              value={String(totalStudents)}
              label="Total Students"
              index={1}
              compact
            />
            <MembershipStatCard
              icon={ClipboardList}
              iconBg="bg-purple-500/15"
              iconColor="text-purple-600 dark:text-purple-400"
              value={String(data.kpis.sessionsThisMonth)}
              label="Coaching Sessions"
              sub="This month"
              index={2}
              compact
            />
            <MembershipStatCard
              icon={Star}
              iconBg="bg-warning/15"
              iconColor="text-warning"
              value={money(data.kpis.revenueThisMonthMinor)}
              label="Coaching Revenue"
              sub="This month"
              index={3}
              compact
            />
          </>
        )}
      </div>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-[1fr_320px]">
        <CoachesListPanel key={rosterKey} facilityId={facilityId} />

        <div className="space-y-4">
          <Card className="p-4">
            <div className="flex items-center justify-between">
              <h2 className="text-sm font-semibold">Upcoming Coaching Sessions</h2>
              <Link href="/coaching/schedule" className="text-xs text-primary hover:underline">
                View All
              </Link>
            </div>
            {!data ? (
              <Skeleton className="mt-3 h-40 w-full rounded-lg" />
            ) : data.upcomingSessions.length === 0 ? (
              <EmptyState message="No coaching sessions scheduled." />
            ) : (
              <ul className="mt-3 space-y-2">
                {data.upcomingSessions.slice(0, 5).map((s) => (
                  <li key={s.id} className="flex items-start gap-3 rounded-lg border border-border p-2.5 text-sm">
                    <span className="shrink-0 rounded-md bg-success/15 px-2 py-1 text-xs font-semibold tabular-nums text-success">
                      {fmtTime(s.startAt)}
                    </span>
                    <div className="min-w-0 flex-1">
                      <p className="truncate font-medium">{s.programName}</p>
                      <p className="truncate text-xs text-muted-foreground">
                        {s.coachName} · {s.courtName}
                      </p>
                    </div>
                    <span className="shrink-0 text-xs tabular-nums text-muted-foreground">
                      {s.enrolled}/{s.capacity}
                    </span>
                  </li>
                ))}
              </ul>
            )}
          </Card>

          <Card className="p-4">
            <div className="flex items-center justify-between">
              <h2 className="text-sm font-semibold">Coaching Insights</h2>
              <Select value={String(insightsDays)} onValueChange={(v) => setInsightsDays(Number(v) as 30 | 60 | 90)}>
                <SelectTrigger className="h-8 w-[9.5rem] text-xs" aria-label="Coaching Insights time window">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {INSIGHTS_WINDOWS.map((w) => (
                    <SelectItem key={w.value} value={w.value}>
                      {w.label}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            {insightsError ? (
              <p className="mt-3 text-xs text-destructive">{insightsError}</p>
            ) : !insights ? (
              <Skeleton className="mt-3 h-24 w-full rounded-lg" />
            ) : (
              <div className="mt-3 grid grid-cols-2 gap-3">
                <InsightTile
                  icon={Users}
                  iconBg="bg-purple-500/15"
                  iconColor="text-purple-600 dark:text-purple-400"
                  label="Total Students"
                  value={String(insights.totalStudents)}
                />
                <InsightTile
                  icon={CheckCircle2}
                  iconBg="bg-success/15"
                  iconColor="text-success"
                  label="Session Attendance"
                  value={insights.sessionAttendancePct != null ? `${insights.sessionAttendancePct}%` : "—"}
                />
                <InsightTile
                  icon={IndianRupee}
                  iconBg="bg-warning/15"
                  iconColor="text-warning"
                  label="Coaching Revenue"
                  value={money(insights.coachingRevenueMinor)}
                />
                <InsightTile
                  icon={Star}
                  iconBg="bg-blue-500/15"
                  iconColor="text-blue-600 dark:text-blue-400"
                  label="Average Rating"
                  value={insights.averageRating != null ? insights.averageRating.toFixed(1) : "—"}
                />
              </div>
            )}
          </Card>

          <Card className="p-4">
            <h2 className="text-sm font-semibold">Quick Actions</h2>
            <div className="mt-3 grid grid-cols-2 gap-2">
              {canCoach && (
                <QuickAction icon={UserPlus} tone="success" label="Add Coach" desc="Onboard a new coach" onClick={() => setAddCoachOpen(true)} />
              )}
              {canSession && (
                <QuickAction icon={CalendarPlus} tone="blue" label="Schedule Session" desc="Create coaching session" href="/coaching/sessions/new" />
              )}
              <QuickAction icon={Users} tone="purple" label="Manage Students" desc="View enrolled students" href="/coaching/enrollments" />
              {canProgram && (
                <QuickAction icon={ClipboardList} tone="warning" label="Coaching Programs" desc="Create training programs" href="/coaching/programs" />
              )}
            </div>
          </Card>
        </div>
      </div>

      <AddCoachSheet
        facilityId={facilityId}
        open={addCoachOpen}
        onOpenChange={setAddCoachOpen}
        onCoachAdded={() => setRosterKey((k) => k + 1)}
      />
    </div>
  );
}

function InsightTile({
  icon: Icon,
  iconBg,
  iconColor,
  label,
  value,
}: {
  icon: typeof UserPlus;
  iconBg: string;
  iconColor: string;
  label: string;
  value: string;
}) {
  return (
    <div className="flex flex-col gap-2 rounded-lg border border-border p-3">
      <span className={`flex h-8 w-8 shrink-0 items-center justify-center rounded-lg ${iconBg}`}>
        <Icon className={`h-4 w-4 ${iconColor}`} aria-hidden />
      </span>
      <div className="min-w-0">
        <p className="truncate text-lg font-bold tabular-nums leading-tight">{value}</p>
        <p className="mt-0.5 text-xs leading-snug text-muted-foreground">{label}</p>
      </div>
    </div>
  );
}

const QUICK_ACTION_TONES = {
  success: { iconBg: "bg-success/15", iconColor: "text-success" },
  blue: { iconBg: "bg-blue-500/15", iconColor: "text-blue-600 dark:text-blue-400" },
  purple: { iconBg: "bg-purple-500/15", iconColor: "text-purple-600 dark:text-purple-400" },
  warning: { iconBg: "bg-warning/15", iconColor: "text-warning" },
} as const;

function QuickAction({
  icon: Icon,
  tone,
  label,
  desc,
  href,
  onClick,
}: {
  icon: typeof UserPlus;
  tone: keyof typeof QUICK_ACTION_TONES;
  label: string;
  desc: string;
  href?: string;
  /** Used instead of `href` for actions that open a sheet (Add Coach) rather than navigate. */
  onClick?: () => void;
}) {
  const { iconBg, iconColor } = QUICK_ACTION_TONES[tone];
  const className = "flex flex-col gap-2 rounded-lg border border-border p-3 text-left transition-colors hover:bg-accent/40";
  const content = (
    <>
      <span className={`flex h-8 w-8 items-center justify-center rounded-lg ${iconBg}`}>
        <Icon className={`h-4 w-4 ${iconColor}`} aria-hidden />
      </span>
      <span className="text-xs font-semibold">{label}</span>
      <span className="text-[11px] leading-tight text-muted-foreground">{desc}</span>
    </>
  );
  if (onClick) {
    return (
      <button type="button" onClick={onClick} className={className}>
        {content}
      </button>
    );
  }
  return (
    <Link href={href!} className={className}>
      {content}
    </Link>
  );
}
