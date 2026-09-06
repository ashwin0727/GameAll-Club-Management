"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { AlertOctagon, Ban, CalendarClock, CheckCircle2, IndianRupee, Loader2, Plus } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { StatCard } from "@/components/shared/stat-card";
import {
  COURT_STATUS_DOT_CLASS,
  COURT_STATUS_LABEL,
  PRIORITY_BADGE_CLASS,
  PRIORITY_LABEL,
  STATUS_BADGE_CLASS,
  STATUS_LABEL,
  formatDateTime,
  formatMoney,
} from "@/features/maintenance/status";
import type { MaintenanceOverview } from "@/features/maintenance/types";
import { getFacilityService } from "@/services/facility";
import { getMaintenanceService } from "@/services/maintenance";
import { ServiceError } from "@/services/shared/service-error";

export function MaintenanceOverviewPage() {
  const [facilityId, setFacilityId] = useState<string | null>(null);
  const [loadState, setLoadState] = useState<"loading" | "ready" | "none" | "error">("loading");
  const [overview, setOverview] = useState<MaintenanceOverview | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    getFacilityService()
      .getFacility()
      .then((f) => {
        if (cancelled) return;
        if (!f) return setLoadState("none");
        setFacilityId(f.id);
        setLoadState("ready");
      })
      .catch(() => !cancelled && setLoadState("error"));
    return () => {
      cancelled = true;
    };
  }, []);

  const load = useCallback(async () => {
    if (!facilityId) return;
    setError(null);
    try {
      setOverview(await getMaintenanceService().getOverview(facilityId));
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Unable to load the maintenance overview.");
    }
  }, [facilityId]);

  useEffect(() => {
    void load();
  }, [load]);

  if (loadState === "loading") return <Skeleton className="h-96 w-full rounded-xl" />;
  if (loadState === "none") return <p className="text-sm text-muted-foreground">No facility found for this account yet.</p>;
  if (loadState === "error") return <p className="text-sm text-destructive">Unable to load this page. Please try again.</p>;
  if (error) return <p className="text-sm text-destructive">{error}</p>;
  if (!overview) return <Skeleton className="h-96 w-full rounded-xl" />;

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-xl font-semibold">Court Maintenance</h1>
          <p className="text-sm text-muted-foreground">Keep your courts in top condition. Track issues, schedule maintenance and manage court availability.</p>
        </div>
        <Button asChild>
          <Link href="/maintenance/tickets/new">
            <Plus className="mr-1.5 h-4 w-4" /> New Maintenance Ticket
          </Link>
        </Button>
      </div>

      <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-6">
        <StatCard icon={AlertOctagon} label="Open Issues" value={String(overview.openIssues)} accent="#FF4D67" />
        <StatCard icon={Loader2} label="In Progress" value={String(overview.inProgress)} accent="#5B6CFF" />
        <StatCard icon={CalendarClock} label="Scheduled" value={String(overview.scheduled)} accent="#FFB020" />
        <StatCard icon={CheckCircle2} label="Resolved This Month" value={String(overview.resolvedThisMonth)} accent="#00D084" />
        <StatCard icon={Ban} label="Courts Blocked" value={String(overview.courtsBlocked)} accent="#8B5CF6" />
        <StatCard icon={IndianRupee} label="Repair Cost" value={formatMoney(overview.repairCostThisMonthMinor)} accent="#00D084" />
      </div>

      <div className="grid gap-4 lg:grid-cols-[1fr_320px]">
        <Card className="space-y-3 p-4">
          <h2 className="text-sm font-semibold">Court Status</h2>
          <div className="grid grid-cols-2 gap-2 sm:grid-cols-3">
            {overview.courtStatus.map((c) => (
              <div key={c.courtId} className="rounded-lg border border-border p-3 text-sm">
                <div className="flex items-center justify-between">
                  <span className="font-medium">{c.courtName}</span>
                  <span className={`h-2 w-2 rounded-full ${COURT_STATUS_DOT_CLASS[c.status]}`} aria-hidden />
                </div>
                <p className="text-xs text-muted-foreground">{c.sportName}</p>
                <p className="mt-1 text-xs font-medium">{COURT_STATUS_LABEL[c.status]}</p>
              </div>
            ))}
          </div>
        </Card>

        <Card className="space-y-1.5 p-4">
          <h2 className="text-sm font-semibold">Quick Actions</h2>
          <div className="grid gap-1.5">
            <Button variant="outline" size="sm" className="justify-start" asChild>
              <Link href="/maintenance/tickets/new">Report an Issue</Link>
            </Button>
            <Button variant="outline" size="sm" className="justify-start" asChild>
              <Link href="/maintenance/tickets/new">Schedule Maintenance</Link>
            </Button>
            <Button variant="outline" size="sm" className="justify-start" asChild>
              <Link href="/maintenance/tickets">View All Tickets</Link>
            </Button>
            <Button variant="outline" size="sm" className="justify-start" asChild>
              <Link href="/maintenance/court-schedule">View Court Schedule</Link>
            </Button>
          </div>
        </Card>
      </div>

      <Card className="space-y-3 p-4">
        <div className="flex items-center justify-between">
          <h2 className="text-sm font-semibold">Maintenance Tickets</h2>
          <Link href="/maintenance/tickets" className="text-xs text-primary hover:underline">
            View All
          </Link>
        </div>
        {overview.recentTickets.length === 0 ? (
          <p className="text-sm text-muted-foreground">No maintenance tickets yet.</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="text-left text-xs text-muted-foreground">
                <tr>
                  <th className="py-1.5 pr-3 font-medium">#</th>
                  <th className="py-1.5 pr-3 font-medium">Court</th>
                  <th className="py-1.5 pr-3 font-medium">Issue</th>
                  <th className="py-1.5 pr-3 font-medium">Priority</th>
                  <th className="py-1.5 pr-3 font-medium">Status</th>
                  <th className="py-1.5 pr-3 font-medium">Assigned</th>
                </tr>
              </thead>
              <tbody>
                {overview.recentTickets.map((t) => (
                  <tr key={t.ticketId} className="border-t border-border hover:bg-secondary/20">
                    <td className="py-1.5 pr-3">
                      <Link href={`/maintenance/tickets/${t.ticketId}`} className="font-medium text-foreground hover:underline">
                        {t.code}
                      </Link>
                    </td>
                    <td className="py-1.5 pr-3">{t.courtName}</td>
                    <td className="max-w-[200px] truncate py-1.5 pr-3">{t.title}</td>
                    <td className="py-1.5 pr-3">
                      <Badge className={PRIORITY_BADGE_CLASS[t.priority]}>{PRIORITY_LABEL[t.priority]}</Badge>
                    </td>
                    <td className="py-1.5 pr-3">
                      <Badge className={STATUS_BADGE_CLASS[t.status]}>{STATUS_LABEL[t.status]}</Badge>
                    </td>
                    <td className="py-1.5 pr-3 text-muted-foreground">{t.assignedToName ?? "Unassigned"}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>

      <div className="grid gap-4 lg:grid-cols-2">
        <Card className="space-y-2 p-4">
          <h2 className="text-sm font-semibold">Court Maintenance Schedule</h2>
          {overview.upcomingSchedule.length === 0 ? (
            <p className="text-sm text-muted-foreground">No upcoming maintenance scheduled.</p>
          ) : (
            <ul className="space-y-2 text-sm">
              {overview.upcomingSchedule.map((s, i) => (
                <li key={`${s.ticketId}-${i}`} className="flex items-center justify-between border-b border-border pb-2 last:border-0">
                  <div>
                    <p className="font-medium">
                      {s.courtName} — {s.title}
                    </p>
                    <p className="text-xs text-muted-foreground">
                      {formatDateTime(s.startTime)} → {formatDateTime(s.endTime)}
                    </p>
                  </div>
                </li>
              ))}
            </ul>
          )}
        </Card>

        <Card className="space-y-2 p-4">
          <h2 className="text-sm font-semibold">Recent Activity</h2>
          {overview.recentActivity.length === 0 ? (
            <p className="text-sm text-muted-foreground">No recent maintenance activity.</p>
          ) : (
            <ul className="space-y-2 text-sm">
              {overview.recentActivity.map((a) => (
                <li key={a.id} className="border-b border-border pb-2 last:border-0">
                  <p>
                    <span className="font-medium">{a.eventType.replaceAll("_", " ").toLowerCase()}</span>
                    {a.note ? ` — ${a.note}` : ""}
                  </p>
                  <p className="text-[11px] text-muted-foreground">
                    {formatDateTime(a.createdAt)} {a.actorName ? `· ${a.actorName}` : ""}
                  </p>
                </li>
              ))}
            </ul>
          )}
        </Card>
      </div>
    </div>
  );
}
