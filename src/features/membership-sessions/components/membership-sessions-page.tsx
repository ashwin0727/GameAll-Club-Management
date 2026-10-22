"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { Link2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { cn } from "@/lib/utils";
import { useFacility } from "@/features/facility/hooks/use-facility";
import { useSportFilter } from "@/features/facility/hooks/use-sport-filter";
import { getMembershipSessionService } from "@/services/membership-sessions";
import { getPlayingAreasService } from "@/services/playing-areas";
import { formatSlot } from "@/features/memberships/slot-format";
import type {
  MembershipSessionListRow,
  MembershipSessionStatus,
} from "@/features/membership-sessions/types";
import type { PlayingArea } from "@/features/courts-setup/types";
import { DropdownSelect } from "@/components/shared/dropdown-select";

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

function statusBadge(s: MembershipSessionStatus) {
  if (s === "active") return <Badge variant="success">Active</Badge>;
  if (s === "full") return <Badge variant="destructive">Full</Badge>;
  return <Badge variant="secondary">Paused</Badge>;
}

export function MembershipSessionsPage() {
  const router = useRouter();
  const { data: facility } = useFacility();
  const facilityId = facility?.id ?? null;
  // The sports ticked in the top bar (null = All Sports): every card and row below is for those sports.
  const sportFilter = useSportFilter(facilityId);
  const sportIds = useMemo(() => (sportFilter.sportSet ? [...sportFilter.sportSet] : null), [sportFilter.sportSet]);
  const sportKey = sportIds ? sportIds.join("|") : "all";
  const [rows, setRows] = useState<MembershipSessionListRow[] | null>(null);
  const [totalCount, setTotalCount] = useState(0);

  const [search, setSearch] = useState("");
  const [debounced, setDebounced] = useState("");
  const [courtId, setCourtId] = useState("");
  const [status, setStatus] = useState<MembershipSessionStatus | "">("");
  const [day, setDay] = useState("");
  const [page, setPage] = useState(1);

  const [areas, setAreas] = useState<PlayingArea[]>([]);

  const openDetail = useCallback((batchId: string) => router.push(`/membership-sessions/${batchId}`), [router]);

  useEffect(() => {
    if (!facilityId) return;
    let cancelled = false;
    (async () => {
      const pa = await getPlayingAreasService().getPlayingAreas(facilityId);
      if (cancelled) return;
      setAreas(pa.filter((a) => !a.archived));
    })();
    return () => {
      cancelled = true;
    };
  }, [facilityId]);

  useEffect(() => {
    const t = setTimeout(() => setDebounced(search), 300);
    return () => clearTimeout(t);
  }, [search]);

  useEffect(() => {
    setPage(1);
  }, [debounced, sportKey, courtId, status, day]);
  useEffect(() => {
    setCourtId("");
  }, [sportKey]);

  const reload = useCallback(async () => {
    if (!facilityId || !sportFilter.ready) return;
    setRows(null);
    const svc = getMembershipSessionService();
    const list = await svc.listSessionsAdmin(facilityId, {
        search: debounced || undefined,
        facilitySportIds: sportIds,
        courtId: courtId || undefined,
        status: status || undefined,
        day: day === "" ? undefined : Number(day),
        page,
        perPage: PER_PAGE,
    });
    setRows(list.rows);
    setTotalCount(list.totalCount);
  }, [facilityId, sportFilter.ready, debounced, sportIds, courtId, status, day, page]);

  useEffect(() => {
    reload();
  }, [reload]);

  const totalPages = Math.max(1, Math.ceil(totalCount / PER_PAGE));
  const courtsForSport = useMemo(
    () => (sportFilter.sportSet ? areas.filter((a) => sportFilter.sportSet!.has(a.facilitySportId)) : areas),
    [areas, sportFilter.sportSet],
  );
  const joinUrl = facilityId ? `${typeof window !== "undefined" ? window.location.origin : ""}/join/${facilityId}` : "";

  if (!facilityId) return <Skeleton className="h-96 w-full rounded-xl" />;

  return (
    <div>
      <div className="min-w-0 space-y-6">
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div>
            <h1 className="text-xl font-semibold">Membership Sessions</h1>
            <p className="text-sm text-muted-foreground">Manage membership court sessions, member allocation and guest releases.</p>
          </div>
        </div>

        {/* Filters */}
        <div className="flex flex-wrap items-center gap-2">
          <Input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Search sessions by name or court" className="h-9 w-full max-w-xs" />
          <DropdownSelect aria-label="Court" value={courtId} onChange={(e) => setCourtId(e.target.value)} className={selectCls}>
            <option value="">All Courts</option>
            {courtsForSport.map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}
          </DropdownSelect>
          <DropdownSelect aria-label="Status" value={status} onChange={(e) => setStatus(e.target.value as MembershipSessionStatus | "")} className={selectCls}>
            {STATUS_OPTIONS.map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
          </DropdownSelect>
          <DropdownSelect aria-label="Day" value={day} onChange={(e) => setDay(e.target.value)} className={selectCls}>
            {DAY_OPTIONS.map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
          </DropdownSelect>
        </div>

        {/* Table */}
        <Card className="stat-enter overflow-hidden p-0" style={{ "--stat-delay": "360ms" } as React.CSSProperties}>
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
                              className={cn("bar-grow h-full rounded-full", r.utilizationPct >= 100 ? "bg-destructive" : r.utilizationPct >= 70 ? "bg-warning" : "bg-success")}
                              style={{ width: `${Math.min(100, r.utilizationPct)}%`, "--bar-delay": "320ms" } as React.CSSProperties}
                            />
                          </div>
                          <span className="text-xs text-muted-foreground">{r.utilizationPct}%</span>
                        </div>
                      </td>
                      <td className="px-4 py-3">{statusBadge(r.status)}</td>
                      <td className="px-4 py-3 text-right">
                        <div className="flex items-center justify-end gap-1">
                          <Button type="button" variant="outline" size="sm" onClick={() => openDetail(r.batchId)}>
                            View
                          </Button>
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
        <Card className="stat-enter p-4" style={{ "--stat-delay": "420ms" } as React.CSSProperties}>
          <p className="flex items-center gap-2 text-sm font-semibold"><Link2 className="h-4 w-4" /> Guest Booking Link</p>
          <p className="text-xs text-muted-foreground">Share this link with players so they can book released slots.</p>
          <div className="mt-2 flex flex-wrap items-center gap-2">
            <Input readOnly value={joinUrl} className="h-9 max-w-md text-xs" />
            <Button type="button" variant="outline" size="sm" onClick={() => navigator.clipboard.writeText(joinUrl)}>Copy Link</Button>
          </div>
        </Card>
      </div>

    </div>
  );
}

