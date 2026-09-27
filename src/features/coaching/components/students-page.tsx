"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import {
  CalendarPlus,
  CheckCircle2,
  ChevronRight,
  ClipboardList,
  GraduationCap,
  IndianRupee,
  LayoutGrid,
  List,
  MoreVertical,
  PauseCircle,
  Search,
  Star,
  UserPlus,
  Users,
} from "lucide-react";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Badge } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { MembershipDashboardHero } from "@/features/memberships/components/membership-dashboard-hero";
import { MembershipStatCard, MembershipStatCardSkeleton } from "@/features/memberships/components/membership-stat-card";
import { SKILL_LEVELS } from "@/features/coaching/components/use-program-wizard-form";
import { getCoachingService } from "@/services/coaching";
import { ServiceError } from "@/services/shared/service-error";
import { usePermissionContext } from "@/features/auth/context/permission-provider";
import type { ActiveBatchWithStudents, CoachOption, CoachingInsights, EnrollmentRow, ProgramOption } from "@/features/coaching/types";
import {
  EmptyState,
  ErrorState,
  Pagination,
  TableSkeleton,
  enrollmentStatusBadge,
  fmtTime,
  initials,
  money,
} from "@/features/coaching/components/shared";

const DAY_LABELS_SHORT = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

/** The next real-world moment a recurring batch runs, from now — today if its time hasn't
 *  passed yet, otherwise the nearest later day it's scheduled on. Batches with no matching day
 *  (shouldn't happen — every batch has at least one) sort last via Infinity. */
function nextOccurrence(daysOfWeek: number[], startTime: string, now: Date): number {
  if (daysOfWeek.length === 0) return Infinity;
  const [h, m] = startTime.split(":").map(Number);
  for (let addDays = 0; addDays < 8; addDays++) {
    const day = new Date(now.getFullYear(), now.getMonth(), now.getDate() + addDays, h ?? 0, m ?? 0, 0, 0);
    if (daysOfWeek.includes(day.getDay()) && day.getTime() > now.getTime()) return day.getTime();
  }
  return Infinity;
}
import { cn } from "@/lib/utils";

const PAGE_SIZE = 10;
const ALL = "ALL";
const TABS = ["All Students", "Active", "Inactive"] as const;
type Tab = (typeof TABS)[number];

const INSIGHTS_WINDOWS = [
  { value: "30", label: "Last 30 Days" },
  { value: "60", label: "Last 60 Days" },
  { value: "90", label: "Last 90 Days" },
] as const;

function levelBadgeVariant(level: string): "success" | "secondary" | "destructive" | "outline" {
  const l = level.toLowerCase();
  if (l.includes("beginner")) return "success";
  if (l.includes("intermediate")) return "secondary";
  if (l.includes("advanced")) return "destructive";
  return "outline";
}

/**
 * Manage Students — the coaching module's student roster, one row per program enrollment (the
 * existing `coaching_enrollments` relationship; no new Student entity). Add Student routes to the
 * dedicated wizard instead of the older quick-add dialog still used from Program Details.
 *
 * No "Attendance %" column data exists — there's no per-student check-in system in the app, only
 * a whole-session COMPLETED/CANCELLED status. Rather than show a fabricated number, that column
 * stays a plain "—" until a real attendance system exists.
 */
export function CoachingStudentsPage() {
  const perms = usePermissionContext();
  const router = useRouter();
  const facilityId = perms?.facilityId ?? null;

  const [tab, setTab] = useState<Tab>("All Students");
  const [search, setSearch] = useState("");
  const [debounced, setDebounced] = useState("");
  const [programId, setProgramId] = useState(ALL);
  const [coachId, setCoachId] = useState(ALL);
  const [level, setLevel] = useState(ALL);
  const [view, setView] = useState<"list" | "grid">("list");
  const [page, setPage] = useState(0);
  const [rows, setRows] = useState<EnrollmentRow[] | null>(null);
  const [totalCount, setTotalCount] = useState(0);
  const [error, setError] = useState<string | null>(null);
  const [programs, setPrograms] = useState<ProgramOption[]>([]);
  const [coaches, setCoaches] = useState<CoachOption[]>([]);

  const [kpis, setKpis] = useState<{ total: number; active: number; inactive: number; pendingPayment: number } | null>(null);

  const [activeBatches, setActiveBatches] = useState<ActiveBatchWithStudents[] | null>(null);
  const [insightsDays, setInsightsDays] = useState<30 | 60 | 90>(30);
  const [insights, setInsights] = useState<CoachingInsights | null>(null);

  const canManage = perms?.can("COACHING_MANAGE_ENROLLMENTS") ?? false;

  useEffect(() => {
    const t = setTimeout(() => setDebounced(search), 300);
    return () => clearTimeout(t);
  }, [search]);
  useEffect(() => setPage(0), [debounced, tab, programId, coachId, level]);

  useEffect(() => {
    if (!facilityId) return;
    getCoachingService().listProgramOptions(facilityId).then(setPrograms).catch(() => setPrograms([]));
    getCoachingService().listCoachOptions(facilityId).then(setCoaches).catch(() => setCoaches([]));
    getCoachingService().listActiveBatchesWithStudents(facilityId).then(setActiveBatches).catch(() => setActiveBatches([]));
  }, [facilityId]);

  useEffect(() => {
    if (!facilityId) return;
    getCoachingService()
      .getInsights(facilityId, insightsDays)
      .then(setInsights)
      .catch(() => setInsights(null));
  }, [facilityId, insightsDays]);

  const loadKpis = useCallback(async () => {
    if (!facilityId) return;
    try {
      const [totalPage, activePage] = await Promise.all([
        getCoachingService().listEnrollments({ facilityId, limit: 1 }),
        getCoachingService().listEnrollments({ facilityId, filters: { status: "ACTIVE" }, limit: 1 }),
      ]);
      // Payment Pending needs a real per-row status, not just a count — page through active
      // enrollments (bounded) to count PENDING/PARTIAL rather than adding a new aggregate RPC.
      const activeRows = await getCoachingService().listEnrollments({ facilityId, filters: { status: "ACTIVE" }, limit: 200 });
      const pendingPayment = activeRows.enrollments.filter((e) => e.paymentStatus === "PENDING" || e.paymentStatus === "PARTIAL").length;
      setKpis({ total: totalPage.totalCount, active: activePage.totalCount, inactive: totalPage.totalCount - activePage.totalCount, pendingPayment });
    } catch {
      setKpis(null);
    }
  }, [facilityId]);

  useEffect(() => {
    void loadKpis();
  }, [loadKpis]);

  const load = useCallback(async () => {
    if (!facilityId) return;
    setError(null);
    const status = tab === "Active" ? "ACTIVE" : tab === "Inactive" ? "NOT_ACTIVE" : null;
    const result = await getCoachingService().listEnrollments({
      facilityId,
      filters: {
        search: debounced,
        status,
        programId: programId === ALL ? null : programId,
        coachId: coachId === ALL ? null : coachId,
        level: level === ALL ? null : level,
      },
      limit: PAGE_SIZE,
      offset: page * PAGE_SIZE,
    });
    setRows(result.enrollments);
    setTotalCount(result.totalCount);
  }, [facilityId, debounced, tab, programId, coachId, level, page]);

  useEffect(() => {
    let cancelled = false;
    setRows(null);
    load().catch((e) => {
      if (cancelled) return;
      setError(e instanceof ServiceError ? e.message : "Unable to load students.");
      setRows([]);
    });
    return () => {
      cancelled = true;
    };
  }, [load]);

  // Every ACTIVE batch under an ACTIVE program with at least one enrolled student, projected to
  // its next real weekly occurrence and sorted soonest-first — the card only ever shows batches
  // that genuinely have someone enrolled and a real next session ahead of the current time.
  const now = new Date();
  const upcoming = (activeBatches ?? [])
    .map((b) => ({ batch: b, at: nextOccurrence(b.daysOfWeek, b.startTime, now) }))
    .filter((x) => Number.isFinite(x.at))
    .sort((a, b) => a.at - b.at)
    .slice(0, 5);

  return (
    <div className="space-y-4">
      <nav aria-label="Breadcrumb" className="flex items-center gap-1 text-xs text-muted-foreground">
        <Link href="/dashboard" className="hover:text-foreground">
          Home
        </Link>
        <ChevronRight className="h-3.5 w-3.5" aria-hidden />
        <Link href="/coaching" className="hover:text-foreground">
          Coaching
        </Link>
        <ChevronRight className="h-3.5 w-3.5" aria-hidden />
        <span className="font-medium text-foreground">Manage Students</span>
      </nav>

      <MembershipDashboardHero
        title="Manage Students"
        subtitle="View and manage all students enrolled in your coaching programs."
        tagline="Build Better Players."
        taglineSub="Track progress, attendance, and performance for every student."
        buttonLabel="Add Student"
        onAddMember={canManage ? () => router.push("/coaching/students/new") : undefined}
      />

      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        {!kpis ? (
          Array.from({ length: 4 }).map((_, i) => <MembershipStatCardSkeleton key={i} compact />)
        ) : (
          <>
            <MembershipStatCard icon={Users} iconBg="bg-blue-500/15" iconColor="text-blue-600 dark:text-blue-400" value={String(kpis.total)} label="Total Students" index={0} compact />
            <MembershipStatCard icon={GraduationCap} iconBg="bg-success/15" iconColor="text-success" value={String(kpis.active)} label="Active Students" index={1} compact />
            <MembershipStatCard icon={PauseCircle} iconBg="bg-warning/15" iconColor="text-warning" value={String(kpis.inactive)} label="Inactive Students" index={2} compact />
            <MembershipStatCard icon={IndianRupee} iconBg="bg-purple-500/15" iconColor="text-purple-600 dark:text-purple-400" value={String(kpis.pendingPayment)} label="Pending Payment" index={3} compact />
          </>
        )}
      </div>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-[1fr_320px]">
        <div className="space-y-3">
          <div className="flex flex-wrap gap-1 border-b border-border">
            {TABS.map((t) => (
              <button
                key={t}
                type="button"
                onClick={() => setTab(t)}
                className={cn(
                  "-mb-px border-b-2 px-3 py-2 text-sm font-medium transition-colors",
                  tab === t ? "border-primary text-primary" : "border-transparent text-muted-foreground hover:text-foreground",
                )}
              >
                {t}
              </button>
            ))}
          </div>

          <Card className="p-4">
            <div className="flex flex-wrap items-center gap-3">
              <div className="relative min-w-[14rem] flex-1">
                <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" aria-hidden />
                <Input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Search student by name, phone or email…" aria-label="Search students" className="h-10 pl-9" />
              </div>
              <Filter label="All Programs" value={programId} onChange={setProgramId} options={[{ value: ALL, label: "All Programs" }, ...programs.map((p) => ({ value: p.id, label: p.name }))]} />
              <Filter label="All Coaches" value={coachId} onChange={setCoachId} options={[{ value: ALL, label: "All Coaches" }, ...coaches.map((c) => ({ value: c.id, label: c.name }))]} />
              <Filter label="All Levels" value={level} onChange={setLevel} options={[{ value: ALL, label: "All Levels" }, ...SKILL_LEVELS.map((l) => ({ value: l, label: l }))]} />
              <div className="flex shrink-0 items-center gap-1 rounded-lg border border-input p-1">
                <button
                  type="button"
                  onClick={() => setView("list")}
                  aria-label="List view"
                  className={cn("flex h-7 w-7 items-center justify-center rounded-md", view === "list" ? "bg-primary text-primary-foreground" : "text-muted-foreground hover:bg-accent")}
                >
                  <List className="h-4 w-4" aria-hidden />
                </button>
                <button
                  type="button"
                  onClick={() => setView("grid")}
                  aria-label="Grid view"
                  className={cn("flex h-7 w-7 items-center justify-center rounded-md", view === "grid" ? "bg-primary text-primary-foreground" : "text-muted-foreground hover:bg-accent")}
                >
                  <LayoutGrid className="h-4 w-4" aria-hidden />
                </button>
              </div>
            </div>
          </Card>

          <Card className="p-0">
            {error ? (
              <ErrorState message={error} onRetry={() => void load()} />
            ) : rows === null ? (
              <TableSkeleton />
            ) : rows.length === 0 ? (
              <EmptyState message="Start by adding your first student." />
            ) : view === "grid" ? (
              <div className="grid grid-cols-1 gap-3 p-4 sm:grid-cols-2 xl:grid-cols-3">
                {rows.map((e) => (
                  <StudentGridCard key={e.id} row={e} />
                ))}
              </div>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="border-b border-border text-left text-xs text-muted-foreground">
                      <th className="p-3 font-medium">Student</th>
                      <th className="p-3 font-medium">Age</th>
                      <th className="p-3 font-medium">Program</th>
                      <th className="p-3 font-medium">Coach</th>
                      <th className="p-3 font-medium">Skill Level</th>
                      <th className="p-3 font-medium">Attendance</th>
                      <th className="p-3 font-medium">Status</th>
                      <th className="p-3 font-medium text-right">Actions</th>
                    </tr>
                  </thead>
                  <tbody>
                    {rows.map((e) => (
                      <tr key={e.id} className="border-b border-border last:border-0 hover:bg-accent/30">
                        <td className="p-3">
                          <Link href={`/coaching/enrollments/${e.id}`} className="font-medium hover:underline">
                            {e.studentName}
                          </Link>
                          {e.studentPhone && <p className="text-xs text-muted-foreground">{e.studentPhone}</p>}
                        </td>
                        <td className="p-3 tabular-nums text-muted-foreground">{e.studentAge ?? "—"}</td>
                        <td className="p-3">
                          <Badge variant="outline">{e.programName}</Badge>
                          {e.batchName && <p className="mt-1 text-xs text-muted-foreground">{e.batchName}</p>}
                        </td>
                        <td className="p-3">
                          {e.coachName ? (
                            <div className="flex items-center gap-2">
                              <Avatar className="h-6 w-6">
                                <AvatarImage src={e.coachAvatarUrl ?? undefined} alt="" />
                                <AvatarFallback className="text-[10px]">{initials(e.coachName)}</AvatarFallback>
                              </Avatar>
                              <span className="text-muted-foreground">{e.coachName}</span>
                            </div>
                          ) : (
                            <span className="text-muted-foreground">—</span>
                          )}
                        </td>
                        <td className="p-3">
                          <Badge variant={levelBadgeVariant(e.programLevel)}>{e.programLevel}</Badge>
                        </td>
                        <td className="p-3">
                          <div className="w-24">
                            <p className="text-xs text-muted-foreground">—</p>
                            <div className="mt-1 h-1.5 w-full rounded-full bg-muted" />
                          </div>
                        </td>
                        <td className="p-3">{enrollmentStatusBadge(e.status)}</td>
                        <td className="p-3 text-right">
                          <DropdownMenu>
                            <DropdownMenuTrigger asChild>
                              <button type="button" aria-label="Student actions" className="rounded-md p-1.5 hover:bg-accent">
                                <MoreVertical className="h-4 w-4" aria-hidden />
                              </button>
                            </DropdownMenuTrigger>
                            <DropdownMenuContent align="end">
                              <DropdownMenuItem asChild>
                                <Link href={`/coaching/enrollments/${e.id}`}>View Student</Link>
                              </DropdownMenuItem>
                              <DropdownMenuItem asChild>
                                <Link href={`/coaching/programs/${e.programId}`}>View Program</Link>
                              </DropdownMenuItem>
                            </DropdownMenuContent>
                          </DropdownMenu>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
            <Pagination page={page} pageSize={PAGE_SIZE} totalCount={totalCount} onPage={setPage} unit="students" />
          </Card>
        </div>

        <div className="space-y-4">
          {activeBatches === null ? (
            <Card className="p-4">
              <h2 className="text-sm font-semibold">Upcoming Coaching Sessions</h2>
              <Skeleton className="mt-3 h-40 w-full rounded-lg" />
            </Card>
          ) : (
            upcoming.length > 0 && (
              <Card className="p-4">
                <div className="flex items-center justify-between">
                  <h2 className="text-sm font-semibold">Upcoming Coaching Sessions</h2>
                  <Link href="/coaching/programs" className="text-xs text-primary hover:underline">
                    View All →
                  </Link>
                </div>
                <ul className="mt-3 space-y-2">
                  {upcoming.map(({ batch: b, at }) => (
                    <li key={b.id} className="flex items-start gap-3 rounded-lg border border-border p-2.5 text-sm">
                      <span className="shrink-0 rounded-md bg-success/15 px-2 py-1 text-xs font-semibold tabular-nums text-success">{fmtTime(new Date(at).toISOString())}</span>
                      <div className="min-w-0 flex-1">
                        <p className="truncate font-medium">{b.programName}</p>
                        <p className="truncate text-xs text-muted-foreground">
                          {DAY_LABELS_SHORT[new Date(at).getDay()]} · {b.coachName ?? "—"} · {b.courtName}
                        </p>
                      </div>
                      <span className="shrink-0 text-xs tabular-nums text-muted-foreground">
                        {b.enrolledCount}/{b.capacity}
                      </span>
                    </li>
                  ))}
                </ul>
              </Card>
            )
          )}

          <Card className="p-4">
            <div className="flex items-center justify-between">
              <h2 className="text-sm font-semibold">Student Insights</h2>
              <Select value={String(insightsDays)} onValueChange={(v) => setInsightsDays(Number(v) as 30 | 60 | 90)}>
                <SelectTrigger className="h-8 w-[9.5rem] text-xs" aria-label="Student Insights time window">
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
            {!insights ? (
              <Skeleton className="mt-3 h-24 w-full rounded-lg" />
            ) : (
              <div className="mt-3 grid grid-cols-2 gap-3">
                <InsightTile icon={Users} iconBg="bg-purple-500/15" iconColor="text-purple-600 dark:text-purple-400" label="Total Students" value={String(insights.totalStudents)} />
                <InsightTile icon={CheckCircle2} iconBg="bg-success/15" iconColor="text-success" label="Session Attendance" value={insights.sessionAttendancePct != null ? `${insights.sessionAttendancePct}%` : "—"} />
                <InsightTile icon={IndianRupee} iconBg="bg-warning/15" iconColor="text-warning" label="Coaching Revenue" value={money(insights.coachingRevenueMinor)} />
                <InsightTile icon={Star} iconBg="bg-blue-500/15" iconColor="text-blue-600 dark:text-blue-400" label="Average Rating" value={insights.averageRating != null ? insights.averageRating.toFixed(1) : "—"} />
              </div>
            )}
          </Card>

          <Card className="p-4">
            <h2 className="text-sm font-semibold">Quick Actions</h2>
            <div className="mt-3 grid grid-cols-2 gap-2">
              {canManage && <QuickAction icon={UserPlus} tone="success" label="Add Student" desc="Enroll a new student" href="/coaching/students/new" />}
              {canManage && <QuickAction icon={ClipboardList} tone="blue" label="Assign to Program" desc="Add to coaching program" href="/coaching/students/new" />}
              <QuickAction icon={CalendarPlus} tone="purple" label="View Programs" desc="Manage coaching programs" href="/coaching/programs" />
              <QuickAction icon={GraduationCap} tone="warning" label="View Coaches" desc="Manage coaching staff" href="/coaching/coaches" />
            </div>
          </Card>
        </div>
      </div>
    </div>
  );
}

function StudentGridCard({ row: e }: { row: EnrollmentRow }) {
  return (
    <Card className="p-3">
      <div className="flex items-center gap-2">
        <Avatar className="h-9 w-9">
          <AvatarFallback>{initials(e.studentName)}</AvatarFallback>
        </Avatar>
        <div className="min-w-0">
          <Link href={`/coaching/enrollments/${e.id}`} className="block truncate font-semibold hover:underline">
            {e.studentName}
          </Link>
          {e.studentPhone && <p className="truncate text-xs text-muted-foreground">{e.studentPhone}</p>}
        </div>
      </div>
      <div className="mt-2 flex flex-wrap items-center gap-1.5">
        <Badge variant="outline">{e.programName}</Badge>
        <Badge variant={levelBadgeVariant(e.programLevel)}>{e.programLevel}</Badge>
      </div>
      <div className="mt-2 flex items-center justify-between text-xs text-muted-foreground">
        <span>{e.coachName ?? "—"}</span>
        {enrollmentStatusBadge(e.status)}
      </div>
    </Card>
  );
}

function Filter({ label, value, onChange, options }: { label: string; value: string; onChange: (v: string) => void; options: { value: string; label: string }[] }) {
  return (
    <Select value={value} onValueChange={onChange}>
      <SelectTrigger className="w-[10rem]" aria-label={label}>
        <SelectValue placeholder={label} />
      </SelectTrigger>
      <SelectContent>
        {options.map((o) => (
          <SelectItem key={o.value} value={o.value}>
            {o.label}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  );
}

function InsightTile({ icon: Icon, iconBg, iconColor, label, value }: { icon: typeof Users; iconBg: string; iconColor: string; label: string; value: string }) {
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

function QuickAction({ icon: Icon, tone, label, desc, href }: { icon: typeof Users; tone: keyof typeof QUICK_ACTION_TONES; label: string; desc: string; href: string }) {
  const { iconBg, iconColor } = QUICK_ACTION_TONES[tone];
  return (
    <Link href={href} className="flex flex-col gap-2 rounded-lg border border-border p-3 text-left transition-colors hover:bg-accent/40">
      <span className={`flex h-8 w-8 items-center justify-center rounded-lg ${iconBg}`}>
        <Icon className={`h-4 w-4 ${iconColor}`} aria-hidden />
      </span>
      <span className="text-xs font-semibold">{label}</span>
      <span className="text-[11px] leading-tight text-muted-foreground">{desc}</span>
    </Link>
  );
}
