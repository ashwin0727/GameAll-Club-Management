"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { ChevronRight, GraduationCap, IndianRupee, LayoutGrid, List, MoreVertical, Search, Trash2, Users, Wallet } from "lucide-react";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Badge } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";
import { useDeleteStudentFlow } from "@/features/coaching/components/use-delete-student-flow";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { MembershipDashboardHero } from "@/features/memberships/components/membership-dashboard-hero";
import { MembershipStatCard, MembershipStatCardSkeleton } from "@/features/memberships/components/membership-stat-card";
import { SKILL_LEVELS } from "@/features/coaching/components/use-program-wizard-form";
import { getCoachingService } from "@/services/coaching";
import { useSportIds } from "@/features/facility/hooks/use-sport-filter";
import { ServiceError } from "@/services/shared/service-error";
import { usePermissionContext } from "@/features/auth/context/permission-provider";
import type { CoachOption, EnrollmentPaymentStatus, EnrollmentRow, ProgramOption, StudentCardStats } from "@/features/coaching/types";
import {
  EmptyState,
  ErrorState,
  money,
  Pagination,
  TableSkeleton,
  enrollmentStatusBadge,
  fmtDate,
  initials,
} from "@/features/coaching/components/shared";
import { cn } from "@/lib/utils";

const PAGE_SIZE = 10;
const ALL = "ALL";
const TABS = ["All Students", "Active", "Inactive"] as const;
type Tab = (typeof TABS)[number];

/** Payment column — what the student still owes, in the words the roster uses. */
function studentPaymentBadge(s: EnrollmentPaymentStatus) {
  const map = { INCLUDED: "secondary", PAID: "success", PARTIAL: "warning", PENDING: "warning" } as const;
  const label = { INCLUDED: "Included", PAID: "Paid", PARTIAL: "Partial", PENDING: "Pending" }[s];
  return <Badge variant={map[s]}>{label}</Badge>;
}

/**
 * Manage Students — the coaching module's student roster, one row per program enrollment (the
 * existing `coaching_enrollments` relationship; no new Student entity). Columns are exactly:
 * Student (name + age), Program / Batch, Phone, Enrollment Date, Payment Status, Status, Actions.
 * Add Student routes to the dedicated wizard instead of the older quick-add dialog still used from
 * Program Details.
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

  const [kpis, setKpis] = useState<StudentCardStats | null>(null);
  // The cards read a database function (migration 0123); if it is missing they show dashes, not a spinner forever.
  const [kpisFailed, setKpisFailed] = useState(false);

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
  }, [facilityId]);

  const { sportIds, ready: sportsReady } = useSportIds(facilityId);

  const loadKpis = useCallback(async () => {
    if (!facilityId || !sportsReady) return;
    try {
      setKpis(await getCoachingService().getStudentCardStats(facilityId, sportIds));
    } catch {
      setKpis(null);
      setKpisFailed(true);
    }
  }, [facilityId, sportIds, sportsReady]);

  useEffect(() => {
    void loadKpis();
  }, [loadKpis]);

  const load = useCallback(async () => {
    if (!facilityId || !sportsReady) return;
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
        sportIds,
      },
      limit: PAGE_SIZE,
      offset: page * PAGE_SIZE,
    });
    setRows(result.enrollments);
    setTotalCount(result.totalCount);
  }, [facilityId, debounced, tab, programId, coachId, level, page, sportIds, sportsReady]);

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

  // Delete Student: confirm → (if payment/AutoPay is live) cancel coaching → delete on the next try.
  const deleteFlow = useDeleteStudentFlow({
    onDeleted: () => {
      void load().catch(() => undefined);
      void loadKpis();
    },
    onChanged: () => {
      void load().catch(() => undefined);
      void loadKpis();
    },
  });

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
        taglineSub="Track progress and performance for every student."
        buttonLabel="Add Student"
        onAddMember={canManage ? () => router.push("/coaching/students/new") : undefined}
      />

      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        {!kpis && !kpisFailed ? (
          Array.from({ length: 4 }).map((_, i) => <MembershipStatCardSkeleton key={i} compact />)
        ) : (
          <>
            <MembershipStatCard icon={Users} iconBg="bg-blue-500/15" iconColor="text-blue-600 dark:text-blue-400" value={kpis ? String(kpis.totalStudents) : "—"} label="Total Students" sub="All student records" index={0} compact />
            <MembershipStatCard icon={GraduationCap} iconBg="bg-success/15" iconColor="text-success" value={kpis ? String(kpis.enrolledStudents) : "—"} label="Enrolled Students" sub="Currently enrolled" index={1} compact />
            <MembershipStatCard icon={Wallet} iconBg="bg-warning/15" iconColor="text-warning" value={kpis ? money(kpis.revenueMinor) : "—"} label="Revenue Collected" sub="This month" index={2} compact />
            <MembershipStatCard icon={IndianRupee} iconBg="bg-purple-500/15" iconColor="text-purple-600 dark:text-purple-400" value={kpis ? money(kpis.pendingMinor) : "—"} label="Payments Pending" sub="Needs follow-up" index={3} compact />
          </>
        )}
      </div>

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
              <Input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Search student by name, phone or email…" aria-label="Search Students" className="h-10 pl-9" />
            </div>
            <Filter label="All Programs" value={programId} onChange={setProgramId} options={[{ value: ALL, label: "All Programs" }, ...programs.map((p) => ({ value: p.id, label: p.name }))]} />
            <Filter label="All Coaches" value={coachId} onChange={setCoachId} options={[{ value: ALL, label: "All Coaches" }, ...coaches.map((c) => ({ value: c.id, label: c.name }))]} />
            <Filter label="All Levels" value={level} onChange={setLevel} options={[{ value: ALL, label: "All Levels" }, ...SKILL_LEVELS.map((l) => ({ value: l, label: l }))]} />
            <div className="flex shrink-0 items-center gap-1 rounded-lg border border-input p-1">
              <button
                type="button"
                onClick={() => setView("list")}
                aria-label="List View"
                className={cn("flex h-7 w-7 items-center justify-center rounded-md", view === "list" ? "bg-primary text-primary-foreground" : "text-muted-foreground hover:bg-accent")}
              >
                <List className="h-4 w-4" aria-hidden />
              </button>
              <button
                type="button"
                onClick={() => setView("grid")}
                aria-label="Grid View"
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
                    <th className="p-3 font-medium">Program / Batch</th>
                    <th className="p-3 font-medium">Phone</th>
                    <th className="p-3 font-medium">Enrollment Date</th>
                    <th className="p-3 font-medium">Payment Status</th>
                    <th className="p-3 font-medium">Status</th>
                    <th className="p-3 text-right font-medium">Actions</th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map((e) => (
                    <tr key={e.id} className="border-b border-border last:border-0 hover:bg-accent/30">
                      <td className="p-3">
                        <div className="flex items-center gap-3">
                          <Avatar className="h-10 w-10">
                            <AvatarFallback>{initials(e.studentName)}</AvatarFallback>
                          </Avatar>
                          <div className="min-w-0">
                            <Link href={`/coaching/enrollments/${e.id}`} className="block truncate font-medium hover:underline">
                              {e.studentName}
                            </Link>
                            {e.studentAge != null && <p className="text-xs text-muted-foreground">age {e.studentAge}</p>}
                          </div>
                        </div>
                      </td>
                      <td className="p-3">
                        <p className="font-medium">{e.programName}</p>
                        {e.batchName && <p className="text-xs text-muted-foreground">{e.batchName}</p>}
                      </td>
                      <td className="p-3 tabular-nums text-muted-foreground">{e.studentPhone ?? "—"}</td>
                      <td className="p-3 text-muted-foreground">{fmtDate(e.startDate)}</td>
                      <td className="p-3">{studentPaymentBadge(e.paymentStatus)}</td>
                      <td className="p-3">{enrollmentStatusBadge(e.status)}</td>
                      <td className="p-3 text-right">
                        <DropdownMenu>
                          <DropdownMenuTrigger asChild>
                            <button type="button" aria-label="Student Actions" className="rounded-md p-1.5 hover:bg-accent">
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
                            {canManage && (
                              <DropdownMenuItem
                                className="text-destructive focus:text-destructive"
                                onSelect={() =>
                                  deleteFlow.start({ enrollmentId: e.id, studentName: e.studentName, programName: e.programName, status: e.status, paidMinor: e.paidMinor })
                                }
                              >
                                <Trash2 className="mr-2 h-4 w-4" aria-hidden />
                                Delete
                              </DropdownMenuItem>
                            )}
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
      {deleteFlow.dialogs}
    </div>
  );
}

/** Grid view carries the same fields as the table — nothing extra. */
function StudentGridCard({ row: e }: { row: EnrollmentRow }) {
  return (
    <Card className="p-3">
      <div className="flex items-center gap-3">
        <Avatar className="h-10 w-10">
          <AvatarFallback>{initials(e.studentName)}</AvatarFallback>
        </Avatar>
        <div className="min-w-0">
          <Link href={`/coaching/enrollments/${e.id}`} className="block truncate font-semibold hover:underline">
            {e.studentName}
          </Link>
          {e.studentAge != null && <p className="text-xs text-muted-foreground">age {e.studentAge}</p>}
        </div>
      </div>
      <div className="mt-3">
        <p className="text-sm font-medium">{e.programName}</p>
        {e.batchName && <p className="text-xs text-muted-foreground">{e.batchName}</p>}
      </div>
      <p className="mt-1 text-xs tabular-nums text-muted-foreground">
        {e.studentPhone ?? "—"} · {fmtDate(e.startDate)}
      </p>
      <div className="mt-2 flex items-center gap-1.5">
        {studentPaymentBadge(e.paymentStatus)}
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
