"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import {
  BookOpen,
  CalendarPlus,
  ChevronRight,
  ClipboardList,
  LayoutGrid,
  List,
  MoreVertical,
  Percent,
  Search,
  Star,
  UserPlus,
  Users,
} from "lucide-react";
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
import { useFacilitySportOptions } from "@/features/facility/hooks/use-facility-sport-options";
import { SKILL_LEVELS } from "@/features/coaching/components/use-program-wizard-form";
import { ServiceError } from "@/services/shared/service-error";
import { getCoachingService } from "@/services/coaching";
import { usePermissionContext } from "@/features/auth/context/permission-provider";
import type { ProgramInsights, ProgramRow, ProgramStatus } from "@/features/coaching/types";
import {
  EmptyState,
  ErrorState,
  Pagination,
  TableSkeleton,
} from "@/features/coaching/components/shared";
import { cn } from "@/lib/utils";

const PAGE_SIZE = 10;
const ALL = "ALL";

const TABS = ["All Programs", "Active", "Upcoming", "Completed"] as const;
type ProgramTab = (typeof TABS)[number];

function weeksBetween(p: ProgramRow): number | null {
  if (!p.startDate || !p.endDate) return null;
  const days = (new Date(p.endDate).getTime() - new Date(p.startDate).getTime()) / 86_400_000;
  return Math.max(1, Math.round(days / 7));
}

function durationWeeks(p: ProgramRow): string {
  const weeks = weeksBetween(p);
  return weeks != null ? `${weeks} Weeks` : "—";
}

/** The program's real total sessions — sessions per week × the number of weeks it runs — falling
 *  back to the legacy `sessionCount` ("sessions per package") field only when that can't be
 *  computed (no weekly cadence or no start/end date set). */
function totalSessions(p: ProgramRow): string {
  const weeks = weeksBetween(p);
  if (p.sessionsPerWeek && weeks != null) return String(p.sessionsPerWeek * weeks);
  return p.sessionCount != null ? String(p.sessionCount) : "—";
}

function levelBadgeVariant(level: string): "success" | "secondary" | "destructive" | "outline" {
  const l = level.toLowerCase();
  if (l.includes("beginner")) return "success";
  if (l.includes("intermediate")) return "secondary";
  if (l.includes("advanced")) return "destructive";
  return "outline";
}

/**
 * The Coaching Programs list — a dashboard-style page (hero, KPI row, tabs, filters, a table
 * with per-program enrollment bars, plus a Featured Program / Program Insights / Quick Actions
 * right rail), replacing the earlier plain-table list to match the reference design. Reuses the
 * Membership Dashboard's hero and stat-card components rather than building new ones.
 */
export function ProgramsPage() {
  const perms = usePermissionContext();
  const router = useRouter();
  const facilityId = perms?.facilityId ?? null;
  const sportsQuery = useFacilitySportOptions(facilityId ?? undefined);

  const [tab, setTab] = useState<ProgramTab>("All Programs");
  const [search, setSearch] = useState("");
  const [debounced, setDebounced] = useState("");
  const [sportId, setSportId] = useState(ALL);
  const [level, setLevel] = useState(ALL);
  const [view, setView] = useState<"list" | "grid">("list");
  const [page, setPage] = useState(0);
  const [rows, setRows] = useState<ProgramRow[] | null>(null);
  const [totalCount, setTotalCount] = useState(0);
  const [error, setError] = useState<string | null>(null);

  const [insights, setInsights] = useState<ProgramInsights | null>(null);
  const [insightsError, setInsightsError] = useState<string | null>(null);

  const canCreate = perms?.can("COACHING_MANAGE_PROGRAMS") ?? false;

  useEffect(() => {
    const t = setTimeout(() => setDebounced(search), 300);
    return () => clearTimeout(t);
  }, [search]);
  useEffect(() => setPage(0), [debounced, sportId, level, tab]);

  const today = new Date().toISOString().slice(0, 10);

  const load = useCallback(async () => {
    if (!facilityId) return;
    setError(null);
    const status: ProgramStatus | null = tab === "Active" || tab === "Upcoming" ? "ACTIVE" : tab === "Completed" ? "COMPLETED" : null;
    const result = await getCoachingService().listPrograms({
      facilityId,
      filters: {
        search: debounced,
        status,
        facilitySportId: sportId === ALL ? null : sportId,
        level: level === ALL ? null : level,
      },
      limit: PAGE_SIZE,
      offset: page * PAGE_SIZE,
    });
    const filtered = tab === "Upcoming" ? result.programs.filter((p) => p.startDate && p.startDate > today) : result.programs;
    setRows(filtered);
    setTotalCount(tab === "Upcoming" ? filtered.length : result.totalCount);
  }, [facilityId, debounced, sportId, level, tab, page, today]);

  useEffect(() => {
    let cancelled = false;
    setRows(null);
    load().catch((e) => {
      if (cancelled) return;
      setError(e instanceof ServiceError ? e.message : "Unable to load programs.");
      setRows([]);
    });
    return () => {
      cancelled = true;
    };
  }, [load]);

  const loadInsights = useCallback(async () => {
    if (!facilityId) return;
    setInsightsError(null);
    try {
      setInsights(await getCoachingService().getProgramInsights(facilityId));
    } catch (e) {
      setInsightsError(e instanceof ServiceError ? e.message : "Unable to load program insights.");
    }
  }, [facilityId]);

  useEffect(() => {
    void loadInsights();
  }, [loadInsights]);

  if (!facilityId) return null;

  const sportName = (id: string | null) => sportsQuery.data?.find((s) => s.facilitySportId === id)?.name ?? "—";

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
        <span className="font-medium text-foreground">Coaching Programs</span>
      </nav>

      <MembershipDashboardHero
        title="Coaching Programs"
        subtitle="Create and manage training programs for different age groups and skill levels."
        tagline="Structured Training. Stronger Players."
        taglineSub="Create programs, assign coaches, manage batches, and track progress."
        buttonLabel="Create Program"
        onAddMember={canCreate ? () => router.push("/coaching/programs/new") : undefined}
      />

      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        {!insights ? (
            Array.from({ length: 4 }).map((_, i) => <MembershipStatCardSkeleton key={i} compact />)
          ) : (
            <>
              <MembershipStatCard
                icon={BookOpen}
                iconBg="bg-success/15"
                iconColor="text-success"
                value={String(insights.totalPrograms)}
                label="Total Programs"
                sub={insights.newProgramsThisMonth > 0 ? `${insights.newProgramsThisMonth} new this month` : undefined}
                subTone="text-success"
                index={0}
                compact
              />
              <MembershipStatCard
                icon={Users}
                iconBg="bg-blue-500/15"
                iconColor="text-blue-600 dark:text-blue-400"
                value={String(insights.enrolledStudents)}
                label="Enrolled Students"
                deltaPct={insights.enrolledStudentsPctChange ?? undefined}
                sub={insights.enrolledStudentsPctChange != null ? "from last month" : undefined}
                index={1}
                compact
              />
              <MembershipStatCard
                icon={Percent}
                iconBg="bg-warning/15"
                iconColor="text-warning"
                value={insights.avgCompletionPct != null ? `${insights.avgCompletionPct}%` : "—"}
                label="Average Completion"
                index={2}
                compact
              />
              <MembershipStatCard
                icon={Star}
                iconBg="bg-purple-500/15"
                iconColor="text-purple-600 dark:text-purple-400"
                value={insights.averageRating != null ? insights.averageRating.toFixed(1) : "—"}
                label="Average Rating"
                index={3}
                compact
              />
            </>
          )}
      </div>
      {insightsError && <p className="text-xs text-destructive">{insightsError}</p>}

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
                <Input
                  value={search}
                  onChange={(e) => setSearch(e.target.value)}
                  placeholder="Search program by name…"
                  aria-label="Search programs"
                  className="h-10 pl-9"
                />
              </div>
              <Select value={sportId} onValueChange={setSportId}>
                <SelectTrigger className="w-[10rem]">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value={ALL}>All Sports</SelectItem>
                  {(sportsQuery.data ?? []).map((s) => (
                    <SelectItem key={s.facilitySportId} value={s.facilitySportId}>
                      {s.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
              <Select value={level} onValueChange={setLevel}>
                <SelectTrigger className="w-[10rem]">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value={ALL}>All Levels</SelectItem>
                  {SKILL_LEVELS.map((l) => (
                    <SelectItem key={l} value={l}>
                      {l}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
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
              <EmptyState message="No coaching programs match these filters." />
            ) : view === "grid" ? (
              <div className="grid grid-cols-1 gap-3 p-4 sm:grid-cols-2 xl:grid-cols-3">
                {rows.map((p) => (
                  <ProgramGridCard key={p.id} program={p} sportName={sportName(p.facilitySportId)} />
                ))}
              </div>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="border-b border-border text-left text-xs text-muted-foreground">
                      <th className="p-3 font-medium">Program</th>
                      <th className="p-3 font-medium">Sport</th>
                      <th className="p-3 font-medium">Level</th>
                      <th className="p-3 font-medium">Duration</th>
                      <th className="p-3 font-medium">Sessions</th>
                      <th className="p-3 font-medium">Enrolled</th>
                      <th className="p-3 font-medium">Status</th>
                      <th className="p-3 font-medium text-right">Actions</th>
                    </tr>
                  </thead>
                  <tbody>
                    {rows.map((p) => {
                      const pct = p.defaultCapacity > 0 ? Math.min(100, Math.round((p.studentCount / p.defaultCapacity) * 100)) : 0;
                      return (
                        <tr key={p.id} className="border-b border-border last:border-0 hover:bg-accent/30">
                          <td className="p-3">
                            <div className="flex items-center gap-3">
                              {p.imageUrl ? (
                                // eslint-disable-next-line @next/next/no-img-element -- program thumbnails are user-uploaded, arbitrary-domain URLs
                                <img src={p.imageUrl} alt="" className="h-10 w-10 shrink-0 rounded-lg object-cover" />
                              ) : (
                                <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-muted">
                                  <BookOpen className="h-4.5 w-4.5 text-muted-foreground" aria-hidden />
                                </div>
                              )}
                              <div className="min-w-0">
                                <Link href={`/coaching/programs/${p.id}`} className="block truncate font-medium hover:underline">
                                  {p.name}
                                </Link>
                                <p className="truncate text-xs text-muted-foreground">{p.ageGroup}</p>
                              </div>
                            </div>
                          </td>
                          <td className="p-3 text-muted-foreground">{sportName(p.facilitySportId)}</td>
                          <td className="p-3">
                            <Badge variant={levelBadgeVariant(p.level)}>{p.level}</Badge>
                          </td>
                          <td className="p-3 whitespace-nowrap text-muted-foreground">{durationWeeks(p)}</td>
                          <td className="p-3 tabular-nums text-muted-foreground">{totalSessions(p)}</td>
                          <td className="p-3">
                            <div className="w-28">
                              <p className="text-xs tabular-nums text-muted-foreground">
                                {p.studentCount} / {p.defaultCapacity}
                              </p>
                              <div className="mt-1 h-1.5 w-full rounded-full bg-muted">
                                <div className="h-1.5 rounded-full bg-success" style={{ width: `${pct}%` }} />
                              </div>
                            </div>
                          </td>
                          <td className="p-3">
                            <Badge variant={p.status === "ACTIVE" ? "success" : p.status === "COMPLETED" ? "outline" : "secondary"}>
                              {p.status === "ACTIVE" ? "Active" : p.status === "COMPLETED" ? "Completed" : p.status === "DRAFT" ? "Draft" : "Inactive"}
                            </Badge>
                          </td>
                          <td className="p-3 text-right">
                            <DropdownMenu>
                              <DropdownMenuTrigger asChild>
                                <button type="button" aria-label="Program actions" className="rounded-md p-1.5 hover:bg-accent">
                                  <MoreVertical className="h-4 w-4" aria-hidden />
                                </button>
                              </DropdownMenuTrigger>
                              <DropdownMenuContent align="end">
                                <DropdownMenuItem asChild>
                                  <Link href={`/coaching/programs/${p.id}`}>View Details</Link>
                                </DropdownMenuItem>
                                <DropdownMenuItem asChild>
                                  <Link href={`/coaching/enrollments?programId=${p.id}`}>View Enrollments</Link>
                                </DropdownMenuItem>
                              </DropdownMenuContent>
                            </DropdownMenu>
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            )}
            <Pagination page={page} pageSize={PAGE_SIZE} totalCount={totalCount} onPage={setPage} unit="programs" />
          </Card>
        </div>

        <div className="space-y-4">
          <Card className="p-4">
            <h2 className="text-sm font-semibold">Program Insights</h2>
            {!insights ? (
              <Skeleton className="mt-3 h-24 w-full rounded-lg" />
            ) : (
              <div className="mt-3 grid grid-cols-2 gap-3">
                <InsightTile icon={Users} iconBg="bg-purple-500/15" iconColor="text-purple-600 dark:text-purple-400" label="Total Enrolled" value={String(insights.enrolledStudents)} />
                <InsightTile icon={Percent} iconBg="bg-success/15" iconColor="text-success" label="Completion Rate" value={insights.avgCompletionPct != null ? `${insights.avgCompletionPct}%` : "—"} />
                <InsightTile icon={ClipboardList} iconBg="bg-warning/15" iconColor="text-warning" label="Active Batches" value={String(insights.activeBatches)} />
                <InsightTile icon={Star} iconBg="bg-blue-500/15" iconColor="text-blue-600 dark:text-blue-400" label="Average Rating" value={insights.averageRating != null ? insights.averageRating.toFixed(1) : "—"} />
              </div>
            )}
          </Card>

          <Card className="p-4">
            <h2 className="text-sm font-semibold">Quick Actions</h2>
            <div className="mt-3 grid grid-cols-2 gap-2">
              {canCreate && <QuickAction icon={ClipboardList} tone="success" label="Create Program" desc="Set up a new training program" href="/coaching/programs/new" />}
              <QuickAction icon={BookOpen} tone="blue" label="Manage Batches" desc="View and manage batches" href="/coaching/programs" />
              <QuickAction icon={UserPlus} tone="purple" label="Assign Coaches" desc="Assign coaches to programs" href="/coaching/coaches" />
              <QuickAction icon={CalendarPlus} tone="warning" label="View Enrollments" desc="See student enrollments" href="/coaching/enrollments" />
            </div>
          </Card>
        </div>
      </div>
    </div>
  );
}

function ProgramGridCard({ program: p, sportName }: { program: ProgramRow; sportName: string }) {
  const pct = p.defaultCapacity > 0 ? Math.min(100, Math.round((p.studentCount / p.defaultCapacity) * 100)) : 0;
  return (
    <Card className="overflow-hidden p-0">
      <div className="h-28 w-full bg-muted">
        {p.imageUrl ? (
          // eslint-disable-next-line @next/next/no-img-element -- user-uploaded program image
          <img src={p.imageUrl} alt="" className="h-full w-full object-cover" />
        ) : (
          <div className="flex h-full w-full items-center justify-center">
            <BookOpen className="h-8 w-8 text-muted-foreground" aria-hidden />
          </div>
        )}
      </div>
      <div className="p-3">
        <Link href={`/coaching/programs/${p.id}`} className="block truncate font-semibold hover:underline">
          {p.name}
        </Link>
        <div className="mt-1 flex flex-wrap items-center gap-1.5">
          <Badge variant={levelBadgeVariant(p.level)}>{p.level}</Badge>
          <span className="text-xs text-muted-foreground">{sportName}</span>
        </div>
        <p className="mt-2 text-xs tabular-nums text-muted-foreground">
          {p.studentCount} / {p.defaultCapacity} enrolled
        </p>
        <div className="mt-1 h-1.5 w-full rounded-full bg-muted">
          <div className="h-1.5 rounded-full bg-success" style={{ width: `${pct}%` }} />
        </div>
      </div>
    </Card>
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

function QuickAction({
  icon: Icon,
  tone,
  label,
  desc,
  href,
}: {
  icon: typeof Users;
  tone: keyof typeof QUICK_ACTION_TONES;
  label: string;
  desc: string;
  href: string;
}) {
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
