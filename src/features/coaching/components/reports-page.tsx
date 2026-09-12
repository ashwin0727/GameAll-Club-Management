"use client";

import { useCallback, useEffect, useState } from "react";
import { Card } from "@/components/ui/card";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { ServiceError } from "@/services/shared/service-error";
import { getCoachingService } from "@/services/coaching";
import { usePermissionContext } from "@/features/auth/context/permission-provider";
import type { CoachingReports } from "@/features/coaching/types";
import { ErrorState, KpiCard, PageHeader, TableSkeleton, money } from "@/features/coaching/components/shared";

const PRESETS = [
  { value: "THIS_MONTH", label: "This Month" },
  { value: "LAST_MONTH", label: "Last Month" },
  { value: "THIS_QUARTER", label: "This Quarter" },
  { value: "THIS_YEAR", label: "This Year" },
];

export function CoachingReportsPage() {
  const perms = usePermissionContext();
  const facilityId = perms?.facilityId ?? null;

  const [preset, setPreset] = useState("THIS_MONTH");
  const [data, setData] = useState<CoachingReports | null>(null);
  const [state, setState] = useState<"loading" | "ready" | "error">("loading");
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!facilityId) return;
    setState("loading");
    setError(null);
    try {
      setData(await getCoachingService().getReports({ facilityId, preset }));
      setState("ready");
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Unable to load coaching reports.");
      setState("error");
    }
  }, [facilityId, preset]);

  useEffect(() => {
    void load();
  }, [load]);

  const header = (
    <PageHeader
      title="Coaching Reports"
      subtitle="Program performance, coach utilization and student growth. Attendance is not a metric."
      action={
        <Select value={preset} onValueChange={setPreset}>
          <SelectTrigger className="w-[12rem]">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            {PRESETS.map((p) => (
              <SelectItem key={p.value} value={p.value}>
                {p.label}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
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
  const maxGrowth = Math.max(1, ...data.studentGrowth.map((g) => g.students));

  return (
    <div className="space-y-4">
      {header}

      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <KpiCard label="Active Students" value={String(k.activeStudents)} />
        <KpiCard label="Active Programs" value={String(k.activePrograms)} />
        <KpiCard label="Sessions" value={String(k.sessionsInRange)} hint={`${k.completedSessionsInRange} completed`} />
        <KpiCard label="Coaching Revenue" value={money(k.coachingRevenueMinor)} />
        <KpiCard label="Avg Capacity Utilization" value={`${k.avgCapacityUtilization}%`} />
      </div>

      <Card className="p-0">
        <h2 className="p-4 text-sm font-semibold">Program Performance</h2>
        {data.programPerformance.length === 0 ? (
          <div className="p-8 text-center text-sm text-muted-foreground">No programs yet.</div>
        ) : (
          <div className="overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Program</TableHead>
                  <TableHead className="text-right">Active Students</TableHead>
                  <TableHead className="text-right">Sessions</TableHead>
                  <TableHead className="text-right">Capacity Utilization</TableHead>
                  <TableHead className="text-right">Revenue</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {data.programPerformance.map((p) => (
                  <TableRow key={p.programId}>
                    <TableCell className="font-medium">{p.programName}</TableCell>
                    <TableCell className="text-right tabular-nums">{p.activeStudents}</TableCell>
                    <TableCell className="text-right tabular-nums">{p.sessions}</TableCell>
                    <TableCell className="text-right tabular-nums">{p.capacityUtilization}%</TableCell>
                    <TableCell className="text-right tabular-nums">{money(p.revenueMinor)}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        )}
      </Card>

      <Card className="p-0">
        <h2 className="p-4 text-sm font-semibold">Coach Utilization</h2>
        <p className="px-4 pb-2 text-xs text-muted-foreground">
          Scheduled coaching hours in range vs. the coach&apos;s weekly recurring available hours.
        </p>
        {data.coachUtilization.length === 0 ? (
          <div className="p-8 text-center text-sm text-muted-foreground">No coaches yet.</div>
        ) : (
          <div className="overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Coach</TableHead>
                  <TableHead className="text-right">Sessions</TableHead>
                  <TableHead className="text-right">Scheduled Hours</TableHead>
                  <TableHead className="text-right">Weekly Available Hours</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {data.coachUtilization.map((c) => (
                  <TableRow key={c.coachId}>
                    <TableCell className="font-medium">{c.coachName}</TableCell>
                    <TableCell className="text-right tabular-nums">{c.sessions}</TableCell>
                    <TableCell className="text-right tabular-nums">{c.scheduledHours}</TableCell>
                    <TableCell className="text-right tabular-nums">{c.weeklyAvailableHours}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        )}
      </Card>

      <Card className="p-4">
        <h2 className="text-sm font-semibold">Student Growth</h2>
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
  );
}
