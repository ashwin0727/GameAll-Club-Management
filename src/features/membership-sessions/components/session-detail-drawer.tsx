"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { X, Calendar, Clock, MapPin, Users, ShieldCheck, UserPlus, CalendarOff, Copy } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { getMembershipService } from "@/services/memberships";
import { getMembershipSessionService } from "@/services/membership-sessions";
import { ServiceError } from "@/services/shared/service-error";
import { formatSlot, formatClock } from "@/features/memberships/slot-format";
import { CapacityDonut } from "@/features/membership-sessions/components/capacity-donut";
import type {
  MembershipSessionDetail,
  MembershipSessionOccurrence,
  MembershipSessionBookingRow,
  MembershipSessionActivity,
} from "@/features/membership-sessions/types";
import type { MembershipBatchMember } from "@/features/membership-sessions/types";
import type { Member } from "@/features/members/types";

const TABS = ["Overview", "Members", "Occurrences", "Bookings", "Activity"] as const;
type Tab = (typeof TABS)[number];

function fmtDate(iso: string): string {
  return new Date(iso).toLocaleDateString("en-IN", { weekday: "short", day: "2-digit", month: "short", year: "numeric" });
}
function fmtShort(iso: string): string {
  return new Date(iso).toLocaleDateString("en-IN", { day: "2-digit", month: "short" });
}
function fmtDateTime(iso: string): string {
  return new Date(iso).toLocaleString("en-IN", { day: "2-digit", month: "short", hour: "numeric", minute: "2-digit", hour12: true });
}

export function SessionDetailDrawer({
  batchId,
  onClose,
  onChanged,
}: {
  batchId: string;
  onClose: () => void;
  onChanged: () => void;
}) {
  const [tab, setTab] = useState<Tab>("Overview");
  const [detail, setDetail] = useState<MembershipSessionDetail | null>(null);
  const [loading, setLoading] = useState(true);

  const load = useCallback(() => {
    setLoading(true);
    getMembershipSessionService()
      .getSessionDetail(batchId)
      .then((d) => setDetail(d))
      .catch(() => setDetail(null))
      .finally(() => setLoading(false));
  }, [batchId]);

  useEffect(() => {
    setTab("Overview");
    load();
  }, [load]);

  function refresh() {
    load();
    onChanged();
  }

  return (
    <div className="flex h-full w-full flex-col bg-card">
      <div className="flex items-start justify-between gap-2 border-b border-border p-4">
        <div className="min-w-0">
          {loading || !detail ? (
            <Skeleton className="h-6 w-48" />
          ) : (
            <>
              <div className="flex flex-wrap items-center gap-2">
                <h2 className="truncate text-base font-semibold">{detail.name}</h2>
                <Badge variant={detail.isActive ? "success" : "secondary"}>{detail.isActive ? "Active" : "Paused"}</Badge>
              </div>
              <p className="truncate text-xs text-muted-foreground">
                {detail.sportName} · {detail.courtName} · {formatClock(detail.startTime)}–{formatClock(detail.endTime)}
              </p>
            </>
          )}
        </div>
        <button type="button" onClick={onClose} aria-label="Close" className="rounded p-1 hover:bg-accent">
          <X className="h-4 w-4" />
        </button>
      </div>

      <div className="flex gap-1 border-b border-border px-3">
        {TABS.map((t) => (
          <button
            key={t}
            type="button"
            onClick={() => setTab(t)}
            className={`border-b-2 px-2 py-2 text-sm ${
              tab === t ? "border-primary font-medium text-foreground" : "border-transparent text-muted-foreground"
            }`}
          >
            {t}
          </button>
        ))}
      </div>

      <div className="flex-1 overflow-y-auto p-4">
        {loading || !detail ? (
          <Skeleton className="h-64 w-full rounded-lg" />
        ) : tab === "Overview" ? (
          <OverviewTab detail={detail} onChanged={refresh} onGoToMembers={() => setTab("Members")} />
        ) : tab === "Members" ? (
          <MembersTab batchId={batchId} facilityId={detail.facilityId} onChanged={refresh} />
        ) : tab === "Occurrences" ? (
          <OccurrencesTab batchId={batchId} onChanged={refresh} />
        ) : tab === "Bookings" ? (
          <BookingsTab batchId={batchId} />
        ) : (
          <ActivityTab batchId={batchId} />
        )}
      </div>
    </div>
  );
}

function Meta({ icon: Icon, label, value }: { icon: React.ComponentType<{ className?: string }>; label: string; value: React.ReactNode }) {
  return (
    <div className="flex items-start gap-2">
      <Icon className="mt-0.5 h-4 w-4 shrink-0 text-muted-foreground" />
      <div className="min-w-0">
        <p className="text-xs text-muted-foreground">{label}</p>
        <p className="text-sm font-medium text-foreground">{value}</p>
      </div>
    </div>
  );
}

function OverviewTab({
  detail,
  onChanged,
  onGoToMembers,
}: {
  detail: MembershipSessionDetail;
  onChanged: () => void;
  onGoToMembers: () => void;
}) {
  const [busy, setBusy] = useState<string | null>(null);
  const [err, setErr] = useState<string | null>(null);

  async function duplicate() {
    setBusy("dup");
    setErr(null);
    try {
      await getMembershipSessionService().duplicateSession(detail.batchId);
      onChanged();
    } catch (e) {
      setErr(e instanceof ServiceError ? e.message : "Unable to duplicate.");
    } finally {
      setBusy(null);
    }
  }

  async function blockToday() {
    setBusy("block");
    setErr(null);
    try {
      const today = new Date().toISOString().slice(0, 10);
      await getMembershipSessionService().blockDate(detail.batchId, today);
      onChanged();
    } catch (e) {
      setErr(e instanceof ServiceError ? e.message : "Unable to block.");
    } finally {
      setBusy(null);
    }
  }

  return (
    <div className="space-y-5">
      <div className="grid grid-cols-2 gap-4">
        <Meta icon={ShieldCheck} label="Session Type" value="Membership Protected" />
        <Meta icon={Calendar} label="Plan" value={detail.planName ?? "—"} />
        <Meta icon={MapPin} label="Court" value={detail.courtName} />
        <Meta icon={Calendar} label="Schedule" value={formatSlot(detail.daysOfWeek, detail.startTime, detail.endTime)} />
        <Meta icon={Clock} label="Duration" value={`${formatClock(detail.startTime)} – ${formatClock(detail.endTime)}`} />
        <Meta icon={Users} label="Capacity" value={`${detail.capacity} players`} />
        <Meta icon={Calendar} label="Created" value={fmtDate(detail.createdAt)} />
        <Meta icon={Clock} label="Last Updated" value={fmtDateTime(detail.updatedAt)} />
      </div>

      <div className="rounded-lg border border-border p-4">
        <p className="mb-3 text-sm font-semibold">Capacity Overview</p>
        <CapacityDonut
          capacity={detail.capacity}
          members={detail.rosterCount}
          guestsBooked={detail.guestsBookedToday}
          availableToRelease={detail.availableToRelease}
        />
      </div>

      <div className="grid gap-3 sm:grid-cols-2">
        <div className="rounded-lg border border-border p-3">
          <p className="text-xs font-medium text-muted-foreground">Today&apos;s Occurrence</p>
          {detail.runsToday ? (
            <p className="mt-1 text-sm">
              {detail.rosterCount} / {detail.capacity} members · {detail.guestsBookedToday} guests booked · {detail.releasedToday} released
            </p>
          ) : (
            <p className="mt-1 text-sm text-muted-foreground">Not scheduled today.</p>
          )}
        </div>
        <div className="rounded-lg border border-border p-3">
          <p className="text-xs font-medium text-muted-foreground">Next Occurrence</p>
          <p className="mt-1 text-sm">{detail.nextOccurrenceDate ? fmtDate(detail.nextOccurrenceDate) : "—"}</p>
        </div>
      </div>

      {err && <p className="text-sm text-destructive">{err}</p>}
      <div>
        <p className="mb-2 text-sm font-semibold">Quick Actions</p>
        <div className="flex flex-wrap gap-2">
          <Button type="button" variant="outline" size="sm" onClick={onGoToMembers}>
            <UserPlus className="mr-1.5 h-4 w-4" />
            Add Member
          </Button>
          <Button type="button" variant="outline" size="sm" disabled={busy !== null} onClick={blockToday}>
            <CalendarOff className="mr-1.5 h-4 w-4" />
            {busy === "block" ? "Blocking…" : "Block Today"}
          </Button>
          <Button type="button" variant="outline" size="sm" disabled={busy !== null} onClick={duplicate}>
            <Copy className="mr-1.5 h-4 w-4" />
            {busy === "dup" ? "Duplicating…" : "Duplicate Session"}
          </Button>
        </div>
      </div>
    </div>
  );
}

function MembersTab({ batchId, facilityId, onChanged }: { batchId: string; facilityId: string; onChanged: () => void }) {
  const [members, setMembers] = useState<MembershipBatchMember[] | null>(null);
  const [names, setNames] = useState<Record<string, string>>({});
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<Pick<Member, "id" | "fullName" | "phone">[]>([]);
  const [error, setError] = useState<string | null>(null);

  const reload = useCallback(async () => {
    const list = await getMembershipSessionService().getBatchMembers(batchId);
    setMembers(list);
  }, [batchId]);

  useEffect(() => {
    reload();
  }, [reload]);

  useEffect(() => {
    const q = query.trim();
    if (q.length < 2) {
      setResults([]);
      return;
    }
    let cancelled = false;
    const t = setTimeout(() => {
      getMembershipService()
        .searchMembers(facilityId, q)
        .then((r) => !cancelled && setResults(r))
        .catch(() => undefined);
    }, 250);
    return () => {
      cancelled = true;
      clearTimeout(t);
    };
  }, [query, facilityId]);

  async function add(memberId: string, name: string) {
    setError(null);
    try {
      await getMembershipSessionService().assignBatchMember(batchId, memberId);
      setNames((n) => ({ ...n, [memberId]: name }));
      setQuery("");
      setResults([]);
      await reload();
      onChanged();
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Unable to add member.");
    }
  }

  async function remove(memberId: string) {
    await getMembershipSessionService().removeBatchMember(batchId, memberId);
    await reload();
    onChanged();
  }

  return (
    <div className="space-y-3">
      <div className="relative">
        <Input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Search a member to add…" />
        {results.length > 0 && (
          <div className="mt-1 max-h-40 space-y-1 overflow-y-auto rounded-md border border-input p-1">
            {results.map((r) => (
              <button
                key={r.id}
                type="button"
                onClick={() => add(r.id, r.fullName)}
                className="flex w-full justify-between rounded px-2 py-1 text-left text-sm hover:bg-accent"
              >
                <span>{r.fullName}</span>
                <span className="text-xs text-muted-foreground">{r.phone}</span>
              </button>
            ))}
          </div>
        )}
      </div>
      {error && <p className="text-sm text-destructive">{error}</p>}
      {members === null ? (
        <Skeleton className="h-32 w-full rounded-lg" />
      ) : members.length === 0 ? (
        <p className="text-sm text-muted-foreground">No members enrolled yet.</p>
      ) : (
        <ul className="divide-y divide-border rounded-md border border-border">
          {members.map((m) => (
            <li key={m.id} className="flex items-center justify-between p-3 text-sm">
              <span>{names[m.memberId] ?? m.memberId.slice(0, 8)}</span>
              <button type="button" onClick={() => remove(m.memberId)} className="text-xs text-destructive">
                Remove
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

function OccurrencesTab({ batchId, onChanged }: { batchId: string; onChanged: () => void }) {
  const [rows, setRows] = useState<MembershipSessionOccurrence[] | null>(null);
  const load = useCallback(() => {
    getMembershipSessionService()
      .listOccurrences(batchId, 45)
      .then(setRows)
      .catch(() => setRows([]));
  }, [batchId]);
  useEffect(() => {
    load();
  }, [load]);

  async function toggle(o: MembershipSessionOccurrence) {
    if (o.isBlocked) await getMembershipSessionService().unblockDate(batchId, o.occurrenceDate);
    else await getMembershipSessionService().blockDate(batchId, o.occurrenceDate);
    load();
    onChanged();
  }

  if (rows === null) return <Skeleton className="h-64 w-full rounded-lg" />;
  return (
    <ul className="divide-y divide-border rounded-md border border-border text-sm">
      {rows.map((o) => (
        <li key={o.occurrenceDate} className="flex items-center justify-between p-3">
          <div>
            <p className={o.isBlocked ? "text-muted-foreground line-through" : ""}>{fmtDate(o.occurrenceDate)}</p>
            <p className="text-xs text-muted-foreground">
              {o.isBlocked
                ? o.blockReason || "Blocked"
                : `${o.memberCount} members · ${o.guestCount} guests${o.releasedCapacity ? ` · ${o.releasedCapacity} released` : ""}`}
            </p>
          </div>
          <button type="button" onClick={() => toggle(o)} className="text-xs text-primary">
            {o.isBlocked ? "Unblock" : "Block"}
          </button>
        </li>
      ))}
    </ul>
  );
}

function BookingsTab({ batchId }: { batchId: string }) {
  const [rows, setRows] = useState<MembershipSessionBookingRow[] | null>(null);
  useEffect(() => {
    getMembershipSessionService()
      .listSessionBookings(batchId)
      .then(setRows)
      .catch(() => setRows([]));
  }, [batchId]);

  if (rows === null) return <Skeleton className="h-64 w-full rounded-lg" />;
  if (rows.length === 0) return <p className="text-sm text-muted-foreground">No bookings yet.</p>;
  return (
    <ul className="divide-y divide-border rounded-md border border-border text-sm">
      {rows.map((b) => (
        <li key={b.bookingId} className="flex items-center justify-between p-3">
          <div>
            <p>{b.participantName}</p>
            <p className="text-xs text-muted-foreground">
              {fmtShort(b.sessionDate)} · {b.participantType === "GUEST" ? "Guest slot" : "Member"}
              {b.status === "CANCELLED" ? " · cancelled" : ""}
            </p>
          </div>
          {b.amountMinor != null && <span className="text-xs text-muted-foreground">₹{(b.amountMinor / 100).toLocaleString("en-IN")}</span>}
        </li>
      ))}
    </ul>
  );
}

function ActivityTab({ batchId }: { batchId: string }) {
  const [rows, setRows] = useState<MembershipSessionActivity[] | null>(null);
  useEffect(() => {
    getMembershipSessionService()
      .listSessionActivity(batchId)
      .then(setRows)
      .catch(() => setRows([]));
  }, [batchId]);

  const items = useMemo(() => rows ?? [], [rows]);
  if (rows === null) return <Skeleton className="h-64 w-full rounded-lg" />;
  if (items.length === 0) return <p className="text-sm text-muted-foreground">No activity yet.</p>;
  return (
    <ol className="space-y-3">
      {items.map((a, i) => (
        <li key={i} className="flex gap-3 text-sm">
          <span className="mt-1.5 h-2 w-2 shrink-0 rounded-full bg-success" />
          <div>
            <p>{a.detail}</p>
            <p className="text-xs text-muted-foreground">
              {a.actor ? `${a.actor} · ` : ""}
              {fmtDateTime(a.at)}
            </p>
          </div>
        </li>
      ))}
    </ol>
  );
}