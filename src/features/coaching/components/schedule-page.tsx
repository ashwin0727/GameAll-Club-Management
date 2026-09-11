"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { ChevronLeft, ChevronRight, Plus } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { cn } from "@/lib/utils";
import { ServiceError } from "@/services/shared/service-error";
import { getCoachingService } from "@/services/coaching";
import { usePermissionContext } from "@/features/auth/context/permission-provider";
import type { SessionRow } from "@/features/coaching/types";
import { ErrorState, PageHeader, TableSkeleton, fmtTime, sessionStatusBadge } from "@/features/coaching/components/shared";

function startOfWeek(d: Date): Date {
  const x = new Date(d);
  x.setHours(0, 0, 0, 0);
  x.setDate(x.getDate() - x.getDay()); // Sunday-start, matching the availability engine
  return x;
}

const DAY_FMT: Intl.DateTimeFormatOptions = { weekday: "short", day: "numeric", month: "short" };

export function SchedulePage() {
  const perms = usePermissionContext();
  const facilityId = perms?.facilityId ?? null;

  const [weekStart, setWeekStart] = useState(() => startOfWeek(new Date()));
  const [rows, setRows] = useState<SessionRow[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  const weekEnd = useMemo(() => {
    const e = new Date(weekStart);
    e.setDate(e.getDate() + 7);
    return e;
  }, [weekStart]);

  const days = useMemo(
    () => Array.from({ length: 7 }, (_, i) => new Date(weekStart.getFullYear(), weekStart.getMonth(), weekStart.getDate() + i)),
    [weekStart],
  );

  const load = useCallback(async () => {
    if (!facilityId) return;
    setError(null);
    try {
      const result = await getCoachingService().listSessions({
        facilityId,
        filters: { from: weekStart.toISOString(), to: weekEnd.toISOString() },
        limit: 500,
      });
      setRows(result.sessions);
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Unable to load the schedule.");
      setRows([]);
    }
  }, [facilityId, weekStart, weekEnd]);

  useEffect(() => {
    setRows(null);
    void load();
  }, [load]);

  const byDay = useMemo(() => {
    const map = new Map<string, SessionRow[]>();
    for (const s of rows ?? []) {
      const key = new Date(s.startAt).toDateString();
      const list = map.get(key) ?? [];
      list.push(s);
      map.set(key, list);
    }
    for (const list of map.values()) list.sort((a, b) => a.startAt.localeCompare(b.startAt));
    return map;
  }, [rows]);

  const canCreate = perms?.can("COACHING_CREATE_SESSION") ?? false;
  const today = new Date().toDateString();

  return (
    <div className="space-y-4">
      <PageHeader
        title="Coaching Schedule"
        subtitle="Manage coaching sessions, court allocation and availability."
        action={
          canCreate && (
            <Button asChild size="sm">
              <Link href="/coaching/sessions/new">
                <Plus className="h-4 w-4" aria-hidden /> Add Session
              </Link>
            </Button>
          )
        }
      />

      <Card className="flex flex-wrap items-center justify-between gap-3 p-3">
        <div className="flex items-center gap-2">
          <Button
            variant="outline"
            size="sm"
            aria-label="Previous week"
            onClick={() => setWeekStart((w) => new Date(w.getFullYear(), w.getMonth(), w.getDate() - 7))}
          >
            <ChevronLeft className="h-4 w-4" aria-hidden />
          </Button>
          <Button variant="outline" size="sm" onClick={() => setWeekStart(startOfWeek(new Date()))}>
            Today
          </Button>
          <Button
            variant="outline"
            size="sm"
            aria-label="Next week"
            onClick={() => setWeekStart((w) => new Date(w.getFullYear(), w.getMonth(), w.getDate() + 7))}
          >
            <ChevronRight className="h-4 w-4" aria-hidden />
          </Button>
        </div>
        <p className="text-sm font-medium">
          {weekStart.toLocaleDateString("en-IN", { day: "numeric", month: "short" })} –{" "}
          {days[6]?.toLocaleDateString("en-IN", { day: "numeric", month: "short", year: "numeric" })}
        </p>
      </Card>

      {error ? (
        <Card className="p-0">
          <ErrorState message={error} onRetry={() => void load()} />
        </Card>
      ) : rows === null ? (
        <Card className="p-0">
          <TableSkeleton rows={7} />
        </Card>
      ) : (
        <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-4">
          {days.map((d) => {
            const list = byDay.get(d.toDateString()) ?? [];
            return (
              <Card key={d.toISOString()} className={cn("p-3", d.toDateString() === today && "ring-1 ring-primary")}>
                <p className="text-sm font-semibold">{d.toLocaleDateString("en-IN", DAY_FMT)}</p>
                {list.length === 0 ? (
                  <p className="mt-2 text-xs text-muted-foreground">No sessions</p>
                ) : (
                  <ul className="mt-2 space-y-2">
                    {list.map((s) => (
                      <li key={s.id}>
                        <Link
                          href={`/coaching/sessions/${s.id}`}
                          className="block rounded-lg border border-border p-2 text-xs hover:bg-accent"
                        >
                          <span className="flex items-center justify-between gap-1">
                            <span className="font-medium">{fmtTime(s.startAt)}</span>
                            {sessionStatusBadge(s.status)}
                          </span>
                          <span className="mt-0.5 block font-medium">{s.programName}</span>
                          <span className="block text-muted-foreground">
                            {s.coachName} · {s.courtName} · {s.enrolledCount}/{s.capacity}
                          </span>
                        </Link>
                      </li>
                    ))}
                  </ul>
                )}
              </Card>
            );
          })}
        </div>
      )}
    </div>
  );
}
