"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { CalendarClock, CalendarCheck2, CalendarDays, DoorOpen, Gauge, Plus, Link2, MoreVertical } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import {
  DropdownMenu,
  DropdownMenuTrigger,
  DropdownMenuContent,
  DropdownMenuItem,
} from "@/components/ui/dropdown-menu";
import { cn } from "@/lib/utils";
import { getFacilityService } from "@/services/facility";
import { getMembershipSessionService } from "@/services/membership-sessions";
import { getSportsService } from "@/services/sports";
import { getPlayingAreasService } from "@/services/playing-areas";
import { formatSlot } from "@/features/memberships/slot-format";
import { CreateSessionDialog } from "@/features/membership-sessions/components/create-session-dialog";
import { SessionDetailDrawer } from "@/features/membership-sessions/components/session-detail-drawer";
import type {
  MembershipSessionListRow,
  MembershipSessionStatus,
  MembershipSessionsSummary,
} from "@/features/membership-sessions/types";
import type { FacilitySport, Sport } from "@/features/sports-setup/types";
import type { PlayingArea } from "@/features/courts-setup/types";

const PER_PAGE = 10;
const STATUS_OPTIONS: { value: MembershipSessionStatus | ""; label: string }[] = [
  { value: "", label: "All Status" },
  { value: "active", label: "Active" },
  { value: "paused", label: "Paused" },
  { value: "full", label: "Full" },
];
const DAY_OPTIONS = [
  { value: "", label: "All Days" },
  { value: "1", label: "Mon" },
  { value: "2", label: "Tue" },
  { value: "3", label: "Wed" },
  { value: "4", label: "Thu" },
  { value: "5", label: "Fri" },
  { value: "6", label: "Sat" },
  { value: "0", label: "Sun" },
];
const selectCls = "h-9 rounded-md border border-input bg-secondary/60 px-2 text-sm";

function Kpi({ icon: Icon, label, value, accent }: { icon: React.ComponentType<{ className?: string }>; label: string; value: string; accent: string }) {
  return (
    <Card className="p-4">
      <div className="flex items-start justify-between gap-2">
        <p className="text-xs font-medium text-muted-foreground">{label}</p>
        <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full" style={{ backgroundColor: `${accent}1f`, color: accent }}>
          <Icon className="h-4 w-4" />
        </span>
      </div>
      <p className="mt-1 text-2xl font-semibold text-foreground">{value}</p>
    </Card>
  );
}

function statusBadge(s: MembershipSessionStatus) {
  if (s === "active") return <Badge variant="success">Active</Badge>;
  if (s === "full") return <Badge variant="destructive">Full</Badge>;
  return <Badge variant="secondary">Paused</Badge>;
}

export function MembershipSessionsPage() {
  const [facilityId, setFacilityId] = useState<string | null>(null);
  const [summary, setSummary] = useState<MembershipSessionsSummary | null>(null);
  const [rows, setRows] = useState<MembershipSessionListRow[] | null>(null);
  const [totalCount, setTotalCount] = useState(0);

  const [search, setSearch] = useState("");
  const [debounced, setDebounced] = useState("");
  const [sportId, setSportId] = useState("");
  const [courtId, setCourtId] = useState("");
  const [status, setStatus] = useState<MembershipSessionStatus | "">("");
  const [day, setDay] = useState("");
  const [page, setPage] = useState(1);

  const [sports, setSports] = useState<Sport[]>([]);
  const [facilitySports, setFacilitySports] = useState<FacilitySport[]>([]);
  const [areas, setAreas] = useState<PlayingArea[]>([]);

  const [createOpen, setCreateOpen] = useState(false);
  const [selected, setSelected] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const f = await getFacilityService().getFacility();
      if (cancelled || !f) return;
      setFacilityId(f.id);
      const [fs, allSports, pa] = await Promise.all([
        getSportsService().getFacilitySports(f.id),
        getSportsService().getActiveSports(),
        getPlayingAreasService().getPlayingAreas(f.id),
      ]);
      if (cancelled) return;
      setFacilitySports(fs.filter((x) => x.enabled));
      setSports(allSports);
      setAreas(pa.filter((a) => !a.archived));
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    const t = setTimeout(() => setDebounced(search), 300);
    return () => clearTimeout(t);
  }, [search]);

  useEffect(() => {
    setPage(1);
  }, [debounced, sportId, courtId, status, day]);

  const reload = useCallback(async () => {
    if (!facilityId) return;
    setRows(null);
    const svc = getMembershipSessionService();
    const [sum, list] = await Promise.all([
      svc.getSessionsSummary(facilityId),
      svc.listSessionsAdmin(facilityId, {
        search: debounced || undefined,
        facilitySportId: sportId || undefined,
        courtId: courtId || undefined,
        status: status || undefined,
        day: day === "" ? undefined : Number(day),
        page,
        perPage: PER_PAGE,
      }),
    ]);
    setSummary(sum);
    setRows(list.rows);
    setTotalCount(list.totalCount);
  }, [facilityId, debounced, sportId, courtId, status, day, page]);

  useEffect(() => {
    reload();
  }, [reload]);

  const totalPages = Math.max(1, Math.ceil(totalCount / PER_PAGE));
  const courtsForSport = useMemo(
    () => (sportId ? areas.filter((a) => a.facilitySportId === sportId) : areas),
    [areas, sportId],
  );
  const joinUrl = facilityId ? `${typeof window !== "undefined" ? window.location.origin : ""}/join/${facilityId}` : "";

  if (!facilityId) return <Skeleton className="h-96 w-full rounded-xl" />;

  return (
    <div className="flex gap-4">
      <div className={cn("min-w-0 flex-1 space-y-6", selected && "hidden xl:block xl:flex-1")}>
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div>
            <h1 className="text-xl font-semibold">Membership Sessions</h1>
            <p className="text-sm text-muted-foreground">Manage membership court sessions, member allocation and guest releases.</p>
          </div>
          <Button type="button" size="sm" onClick={() => setCreateOpen(true)}>
            <Plus className="mr-1.5 h-4 w-4" />
            Create Session
          </Button>
        </div>

        {/* KPIs */}
        <div className="grid grid-cols-2 gap-4 lg:grid-cols-5">
          {summary ? (
            <>
              <Kpi icon={CalendarClock} label="Total Sessions" value={String(summary.totalSessions)} accent="#8B5CF6" />
              <Kpi icon={CalendarCheck2} label="Active Sessions" value={String(summary.activeSessions)} accent="#00D084" />
              <Kpi icon={CalendarDays} label="Today's Sessions" value={String(summary.todaysSessions)} accent="#5B6CFF" />
              <Kpi icon={DoorOpen} label="Guest Slots Released" value={String(summary.guestSlotsReleased)} accent="#FFB020" />
              <Kpi icon={Gauge} label="Utilization" value={`${summary.avgUtilizationPct}%`} accent="#FF4D67" />
            </>
          ) : (
            Array.from({ length: 5 }).map((_, i) => <Skeleton key={i} className="h-24 rounded-xl" />)
          )}
        </div>

        {/* Filters */}
        <div className="flex flex-wrap items-center gap-2">
          <Input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Search sessions by name or court" className="h-9 w-full max-w-xs" />
          <select aria-label="Sport" value={sportId} onChange={(e) => { setSportId(e.target.value); setCourtId(""); }} className={selectCls}>
            <option value="">All Sports</option>
            {facilitySports.map((fs) => {
              const s = sports.find((sp) => sp.id === fs.sportId);
              return <option key={fs.id} value={fs.id}>{fs.customSportName ?? s?.name ?? "Sport"}</option>;
            })}
          </select>
          <select aria-label="Court" value={courtId} onChange={(e) => setCourtId(e.target.value)} className={selectCls}>
            <option value="">All Courts</option>
            {courtsForSport.map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}
          </select>
          <select aria-label="Status" value={status} onChange={(e) => setStatus(e.target.value as MembershipSessionStatus | "")} className={selectCls}>
            {STATUS_OPTIONS.map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
          </select>
          <select aria-label="Day" value={day} onChange={(e) => setDay(e.target.value)} className={selectCls}>
            {DAY_OPTIONS.map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
          </select>
        </div>

        {/* Table */}
        <Card className="overflow-hidden p-0">
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="border-b border-border text-left text-xs text-muted-foreground">
                <tr>
                  <th className="px-4 py-3 font-medium">Session</th>
                  <th className="px-4 py-3 font-medium">Court</th>
                  <th className="px-4 py-3 font-medium">Schedule</th>
                  <th className="px-4 py-3 font-medium">Capacity</th>
                  <th className="px-4 py-3 font-medium">Members</th>
                  <th className="px-4 py-3 font-medium">Guest</th>
                  <th className="px-4 py-3 font-medium">Utilization</th>
                  <th className="px-4 py-3 font-medium">Status</th>
                  <th className="px-4 py-3 text-right font-medium">Actions</th>
                </tr>
              </thead>
              <tbody>
                {rows === null ? (
                  Array.from({ length: 6 }).map((_, i) => (
                    <tr key={i} className="border-b border-border/60">
                      <td colSpan={9} className="px-4 py-3"><Skeleton className="h-8 w-full" /></td>
                    </tr>
                  ))
                ) : rows.length === 0 ? (
                  <tr>
                    <td colSpan={9} className="px-4 py-10 text-center text-sm text-muted-foreground">No sessions match these filters.</td>
                  </tr>
                ) : (
                  rows.map((r) => (
                    <tr key={r.batchId} className="border-b border-border/60 last:border-b-0">
                      <td className="px-4 py-3">
                        <p className="font-medium text-foreground">{r.name}</p>
                        <p className="text-xs text-muted-foreground">{r.sportName}</p>
                      </td>
                      <td className="px-4 py-3 text-muted-foreground">{r.courtName}</td>
                      <td className="px-4 py-3 text-xs text-muted-foreground">
                        {formatSlot(r.daysOfWeek, r.startTime, r.endTime)}
                      </td>
                      <td className="px-4 py-3 text-muted-foreground">{r.capacity}</td>
                      <td className="px-4 py-3">
                        {r.rosterCount} <span className="text-xs text-muted-foreground">/ {r.capacity}</span>
                      </td>
                      <td className="px-4 py-3 text-xs text-muted-foreground">
                        {r.guestBookedToday} / {r.releasedToday}
                      </td>
                      <td className="px-4 py-3">
                        <div className="flex items-center gap-2">
                          <div className="h-1.5 w-16 overflow-hidden rounded-full bg-secondary">
                            <div
                              className={cn("h-full rounded-full", r.utilizationPct >= 100 ? "bg-destructive" : r.utilizationPct >= 70 ? "bg-warning" : "bg-success")}
                              style={{ width: `${Math.min(100, r.utilizationPct)}%` }}
                            />
                          </div>
                          <span className="text-xs text-muted-foreground">{r.utilizationPct}%</span>
                        </div>
                      </td>
                      <td className="px-4 py-3">{statusBadge(r.status)}</td>
                      <td className="px-4 py-3 text-right">
                        <div className="flex items-center justify-end gap-1">
                          <Button type="button" variant="outline" size="sm" onClick={() => setSelected(r.batchId)}>
                            View
                          </Button>
                          <DropdownMenu>
                            <DropdownMenuTrigger asChild>
                              <Button type="button" variant="ghost" size="icon" aria-label="More actions">
                                <MoreVertical className="h-4 w-4" />
                              </Button>
                            </DropdownMenuTrigger>
                            <DropdownMenuContent align="end">
                              <DropdownMenuItem onClick={() => setSelected(r.batchId)}>Manage members</DropdownMenuItem>
                              <DropdownMenuItem
                                onClick={async () => {
                                  await getMembershipSessionService().duplicateSession(r.batchId);
                                  reload();
                                }}
                              >
                                Duplicate
                              </DropdownMenuItem>
                            </DropdownMenuContent>
                          </DropdownMenu>
                        </div>
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
          <div className="flex flex-wrap items-center justify-between gap-2 border-t border-border px-4 py-3 text-xs text-muted-foreground">
            <span>{totalCount === 0 ? "No sessions" : `Showing ${(page - 1) * PER_PAGE + 1} to ${Math.min(page * PER_PAGE, totalCount)} of ${totalCount} sessions`}</span>
            <div className="flex items-center gap-1">
              <Button type="button" variant="outline" size="sm" disabled={page <= 1} onClick={() => setPage((p) => p - 1)}>Previous</Button>
              <span className="px-2">Page {page} / {totalPages}</span>
              <Button type="button" variant="outline" size="sm" disabled={page >= totalPages} onClick={() => setPage((p) => p + 1)}>Next</Button>
            </div>
          </div>
        </Card>

        {/* Guest booking link */}
        <Card className="p-4">
          <p className="flex items-center gap-2 text-sm font-semibold"><Link2 className="h-4 w-4" /> Guest Booking Link</p>
          <p className="text-xs text-muted-foreground">Share this link with players so they can book released slots.</p>
          <div className="mt-2 flex flex-wrap items-center gap-2">
            <Input readOnly value={joinUrl} className="h-9 max-w-md text-xs" />
            <Button type="button" variant="outline" size="sm" onClick={() => navigator.clipboard.writeText(joinUrl)}>Copy link</Button>
          </div>
        </Card>
      </div>

      {selected && (
        <>
          <div className="fixed inset-0 z-40 bg-black/40 xl:hidden" onClick={() => setSelected(null)} />
          <div className="fixed inset-y-0 right-0 z-50 w-full max-w-md border-l border-border shadow-xl xl:static xl:z-0 xl:w-[400px] xl:shrink-0 xl:rounded-xl xl:border xl:shadow-none">
            <SessionDetailDrawer batchId={selected} onClose={() => setSelected(null)} onChanged={reload} />
          </div>
        </>
      )}

      {facilityId && (
        <CreateSessionDialog open={createOpen} onOpenChange={setCreateOpen} facilityId={facilityId} onCreated={reload} />
      )}
    </div>
  );
}

