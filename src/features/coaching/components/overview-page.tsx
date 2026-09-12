"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { Plus } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { ServiceError } from "@/services/shared/service-error";
import { getCoachingService } from "@/services/coaching";
import { usePermissionContext } from "@/features/auth/context/permission-provider";
import type { CoachingOverview } from "@/features/coaching/types";
import {
  EmptyState,
  ErrorState,
  KpiCard,
  PageHeader,
  TableSkeleton,
  fmtDate,
  fmtDateTime,
  money,
  sessionStatusBadge,
} from "@/features/coaching/components/shared";

export function CoachingOverviewPage() {
  const perms = usePermissionContext();
  const facilityId = perms?.facilityId ?? null;

  const [data, setData] = useState<CoachingOverview | null>(null);
  const [state, setState] = useState<"loading" | "ready" | "error">("loading");
  const [error, setError] = useState<string | null>(null);

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

  useEffect(() => {
    void load();
  }, [load]);

  const canSession = perms?.can("COACHING_CREATE_SESSION") ?? false;
  const canCoach = perms?.can("COACHING_MANAGE_COACHES") ?? false;
  const canProgram = perms?.can("COACHING_MANAGE_PROGRAMS") ?? false;

  const header = (
    <PageHeader
      title="Coaching Overview"
      subtitle="Manage your coaches, programs, sessions and students."
      action={
        <div className="flex flex-wrap gap-2">
          {canCoach && (
            <Button asChild size="sm" variant="outline">
              <Link href="/coaching/coaches/add">Add Coach</Link>
            </Button>
          )}
          {canProgram && (
            <Button asChild size="sm" variant="outline">
              <Link href="/coaching/programs/new">Create Program</Link>
            </Button>
          )}
          {canSession && (
            <Button asChild size="sm">
              <Link href="/coaching/sessions/new">
                <Plus className="h-4 w-4" aria-hidden /> New Session
              </Link>
            </Button>
          )}
        </div>
      }
    />
  );

  if (state === "error") {
    return (
      <div className="space-y-4">
        {header}
        <Card className="p-0">
          <ErrorState message={error ?? ""} onRetry={() => void load()} />
        </Card>
      </div>
    );
  }
  if (state === "loading" || !data) {
    return (
      <div className="space-y-4">
        {header}
        <Card className="p-0">
          <TableSkeleton rows={8} />
        </Card>
      </div>
    );
  }

  const k = data.kpis;
  const totalStudents = data.studentsByProgram.reduce((s, p) => s + p.students, 0);
  const maxGrowth = Math.max(1, ...data.studentGrowth.map((g) => g.students));

  return (
    <div className="space-y-4">
      {header}

      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <KpiCard label="Active Students" value={String(k.activeStudents)} />
        <KpiCard label="Active Programs" value={String(k.activePrograms)} />
        <KpiCard label="Coaches" value={String(k.activeCoaches)} hint={k.coachesOnLeave > 0 ? `${k.coachesOnLeave} on leave` : undefined} />
        <KpiCard label="Sessions This Month" value={String(k.sessionsThisMonth)} />
        <KpiCard label="Upcoming Sessions" value={String(k.upcomingSessions)} />
        <KpiCard label="Revenue This Month" value={money(k.revenueThisMonthMinor)} hint="collected coaching payments" />
      </div>

      <div className="grid gap-4 lg:grid-cols-3">
        <Card className="p-0 lg:col-span-2">
          <div className="flex items-center justify-between p-4">
            <h2 className="text-sm font-semibold">Upcoming Coaching Sessions</h2>
            <Link href="/coaching/schedule" className="text-xs text-primary hover:underline">
              View schedule
            </Link>
          </div>
          {data.upcomingSessions.length === 0 ? (
            <EmptyState message="No sessions scheduled." />
          ) : (
            <div className="overflow-x-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Time</TableHead>
                    <TableHead>Program</TableHead>
                    <TableHead>Coach</TableHead>
                    <TableHead className="text-right">Students</TableHead>
                    <TableHead>Court</TableHead>
                    <TableHead>Status</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {data.upcomingSessions.map((s) => (
                    <TableRow key={s.id}>
                      <TableCell className="whitespace-nowrap text-muted-foreground">{fmtDateTime(s.startAt)}</TableCell>
                      <TableCell>
                        <Link href={`/coaching/sessions/${s.id}`} className="font-medium hover:underline">
                          {s.programName}
                        </Link>
                      </TableCell>
                      <TableCell className="text-muted-foreground">{s.coachName}</TableCell>
                      <TableCell className="text-right tabular-nums">
                        {s.enrolled} / {s.capacity}
                      </TableCell>
                      <TableCell className="text-muted-foreground">{s.courtName}</TableCell>
                      <TableCell>{sessionStatusBadge(s.status)}</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          )}
        </Card>

        <Card className="p-4">
          <h2 className="text-sm font-semibold">Student Growth</h2>
          <p className="text-xs text-muted-foreground">Last 6 months</p>
          <ul className="mt-3 space-y-2">
            {data.studentGrowth.map((g) => (
              <li key={g.monthKey} className="text-sm">
                <div className="flex justify-between">
                  <span>{g.month}</span>
                  <span className="text-muted-foreground tabular-nums">{g.students}</span>
                </div>
                <div className="mt-1 h-2 rounded-full bg-muted">
                  <div className="h-2 rounded-full bg-primary" style={{ width: `${Math.max(4, (g.students / maxGrowth) * 100)}%` }} />
                </div>
              </li>
            ))}
          </ul>
        </Card>
      </div>

      <div className="grid gap-4 lg:grid-cols-2">
        <Card className="p-0">
          <div className="flex items-center justify-between p-4">
            <h2 className="text-sm font-semibold">Active Programs</h2>
            <Link href="/coaching/programs" className="text-xs text-primary hover:underline">
              View all
            </Link>
          </div>
          {data.activePrograms.length === 0 ? (
            <EmptyState message="No coaching programs yet." />
          ) : (
            <ul className="divide-y divide-border">
              {data.activePrograms.map((p) => (
                <li key={p.id} className="flex items-center justify-between p-3 text-sm">
                  <Link href={`/coaching/programs/${p.id}`} className="font-medium hover:underline">
                    {p.name}
                  </Link>
                  <span className="text-muted-foreground">
                    {p.level} · {p.studentCount} students · {p.sessionCount} sessions
                  </span>
                </li>
              ))}
            </ul>
          )}
        </Card>

        <Card className="p-4">
          <h2 className="text-sm font-semibold">Students by Program</h2>
          {data.studentsByProgram.length === 0 ? (
            <p className="mt-3 text-sm text-muted-foreground">No active enrollments yet.</p>
          ) : (
            <ul className="mt-3 space-y-2">
              {data.studentsByProgram.map((p) => {
                const pct = totalStudents > 0 ? Math.round((p.students / totalStudents) * 100) : 0;
                return (
                  <li key={p.programId} className="text-sm">
                    <div className="flex justify-between">
                      <span>{p.programName}</span>
                      <span className="text-muted-foreground">
                        {p.students} ({pct}%)
                      </span>
                    </div>
                    <div className="mt-1 h-2 rounded-full bg-muted">
                      <div className="h-2 rounded-full bg-primary" style={{ width: `${pct}%` }} />
                    </div>
                  </li>
                );
              })}
            </ul>
          )}
        </Card>
      </div>

      <Card className="p-0">
        <h2 className="p-4 text-sm font-semibold">Recent Enrollments</h2>
        {data.recentEnrollments.length === 0 ? (
          <EmptyState message="No active enrollments." />
        ) : (
          <ul className="divide-y divide-border">
            {data.recentEnrollments.map((e) => (
              <li key={e.id} className="flex items-center justify-between p-3 text-sm">
                <Link href={`/coaching/enrollments/${e.id}`} className="font-medium hover:underline">
                  {e.studentName}
                </Link>
                <span className="text-muted-foreground">
                  {e.programName} · {fmtDate(e.enrolledAt)}
                </span>
              </li>
            ))}
          </ul>
        )}
      </Card>
    </div>
  );
}
