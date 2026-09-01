"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import {
  ArrowLeft,
  CalendarDays,
  Clock,
  Copy,
  MapPin,
  MoreVertical,
  Pencil,
  Plus,
  Share2,
  ShieldCheck,
  Trash2,
  Users,
} from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { cn } from "@/lib/utils";
import { getMembershipService } from "@/services/memberships";
import { getMembershipSessionService } from "@/services/membership-sessions";
import { ServiceError } from "@/services/shared/service-error";
import { formatClock } from "@/features/memberships/slot-format";
import { CapacityDonut } from "@/features/membership-sessions/components/capacity-donut";
import type {
  MembershipSessionActivity,
  MembershipSessionDetail,
  MembershipSessionMemberRow,
} from "@/features/membership-sessions/types";
import type { Member } from "@/features/members/types";

const DAY_ABBR = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

function fmtDate(iso: string): string {
  return new Date(iso).toLocaleDateString("en-IN", { day: "2-digit", month: "short", year: "numeric" });
}
function fmtDateTime(iso: string): string {
  return new Date(iso).toLocaleString("en-IN", { day: "2-digit", month: "short", year: "numeric", hour: "numeric", minute: "2-digit", hour12: true });
}
function durationLabel(start: string, end: string): string {
  const [sh = 0, sm = 0] = start.split(":").map(Number);
  const [eh = 0, em = 0] = end.split(":").map(Number);
  const mins = eh * 60 + em - (sh * 60 + sm);
  const h = Math.floor(mins / 60);
  const m = mins % 60;
  return [h ? `${h} Hour${h > 1 ? "s" : ""}` : null, m ? `${m} Min` : null].filter(Boolean).join(" ") || "—";
}
function todayIso(): string {
  return new Date().toISOString().slice(0, 10);
}

function Meta({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div className="min-w-0">
      <p className="text-xs text-muted-foreground">{label}</p>
      <p className="truncate text-sm font-medium text-foreground">{value}</p>
    </div>
  );
}

function Row({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div className="flex items-start justify-between gap-4 py-2 text-sm">
      <span className="text-muted-foreground">{label}</span>
      <span className="text-right font-medium text-foreground">{value}</span>
    </div>
  );
}

export function SessionDetailPage({ batchId }: { batchId: string }) {
  const router = useRouter();
  const [detail, setDetail] = useState<MembershipSessionDetail | null>(null);
  const [members, setMembers] = useState<MembershipSessionMemberRow[] | null>(null);
  const [activity, setActivity] = useState<MembershipSessionActivity[] | null>(null);
  const [loading, setLoading] = useState(true);
  const [notFound, setNotFound] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  const [editOpen, setEditOpen] = useState(false);
  const [releaseOpen, setReleaseOpen] = useState(false);
  const [notesEditing, setNotesEditing] = useState(false);

  const load = useCallback(async () => {
    const svc = getMembershipSessionService();
    try {
      const [d, m, a] = await Promise.all([
        svc.getSessionDetail(batchId),
        svc.getSessionMembers(batchId),
        svc.listSessionActivity(batchId),
      ]);
      setDetail(d);
      setMembers(m);
      setActivity(a);
    } catch {
      setNotFound(true);
    } finally {
      setLoading(false);
    }
  }, [batchId]);

  useEffect(() => {
    load();
  }, [load]);

  const joinUrl = useMemo(() => {
    if (!detail) return "";
    const origin = typeof window !== "undefined" ? window.location.origin : "";
    return `${origin}/join/${detail.facilityId}?session=${detail.batchId}`;
  }, [detail]);

  async function duplicate() {
    try {
      await getMembershipSessionService().duplicateSession(batchId);
      router.push("/membership-sessions");
    } catch (e) {
      setErr(e instanceof ServiceError ? e.message : "Unable to duplicate.");
    }
  }
  async function blockToday() {
    try {
      await getMembershipSessionService().blockDate(batchId, todayIso());
      await load();
    } catch (e) {
      setErr(e instanceof ServiceError ? e.message : "Unable to block today.");
    }
  }
  async function toggleActive() {
    if (!detail) return;
    try {
      await getMembershipSessionService().updateBatch(batchId, { isActive: !detail.isActive });
      await load();
    } catch (e) {
      setErr(e instanceof ServiceError ? e.message : "Unable to update.");
    }
  }

  if (loading) return <Skeleton className="h-[70vh] w-full rounded-xl" />;
  if (notFound || !detail) {
    return (
      <div className="space-y-4">
        <Link href="/membership-sessions" className="inline-flex items-center gap-1 text-sm text-muted-foreground hover:text-foreground">
          <ArrowLeft className="h-4 w-4" /> Membership Sessions
        </Link>
        <Card className="p-10 text-center text-sm text-muted-foreground">This session could not be found.</Card>
      </div>
    );
  }

  const utilization = detail.capacity > 0 ? Math.round((detail.rosterCount / detail.capacity) * 100) : 0;
  const availableToBook = Math.max(0, detail.releasedToday - detail.guestsBookedToday);

  return (
    <div className="space-y-5">
      {/* Breadcrumb + header */}
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0">
          <button
            type="button"
            onClick={() => router.push("/membership-sessions")}
            className="mb-1 inline-flex items-center gap-1.5 text-sm text-muted-foreground hover:text-foreground"
          >
            <ArrowLeft className="h-4 w-4" /> Membership Session Details
          </button>
          <p className="text-xs text-muted-foreground">
            <Link href="/memberships" className="hover:text-foreground">Memberships</Link>
            {" / "}
            <Link href="/membership-sessions" className="hover:text-foreground">Membership Sessions</Link>
            {" / "}
            <span className="text-foreground">{detail.name}</span>
          </p>
        </div>
        <div className="flex items-center gap-2">
          <Button type="button" variant="outline" size="sm" onClick={() => setEditOpen(true)}>
            <Pencil className="mr-1.5 h-4 w-4" /> Edit Session
          </Button>
          <Button type="button" size="sm" onClick={() => setReleaseOpen(true)}>
            <Users className="mr-1.5 h-4 w-4" /> Release Guest Slots
          </Button>
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button type="button" variant="ghost" size="icon" aria-label="More actions">
                <MoreVertical className="h-4 w-4" />
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end">
              <DropdownMenuItem onClick={blockToday}>Block today&apos;s occurrence</DropdownMenuItem>
              <DropdownMenuItem onClick={duplicate}>Duplicate session</DropdownMenuItem>
              <DropdownMenuItem onClick={toggleActive}>{detail.isActive ? "Pause session" : "Activate session"}</DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        </div>
      </div>

      {err && <p className="text-sm text-destructive">{err}</p>}

      {/* Hero */}
      <Card className="p-5">
        <div className="flex flex-wrap items-start gap-4">
          <span className="flex h-12 w-12 shrink-0 items-center justify-center rounded-xl bg-primary/10 text-primary">
            <CalendarDays className="h-6 w-6" />
          </span>
          <div className="min-w-0 flex-1">
            <div className="flex flex-wrap items-center gap-2">
              <h1 className="text-lg font-semibold text-foreground">{detail.name}</h1>
              <Badge variant={detail.isActive ? "success" : "secondary"}>{detail.isActive ? "Active" : "Paused"}</Badge>
            </div>
            {detail.notes && <p className="mt-0.5 text-sm text-muted-foreground">{detail.notes}</p>}
          </div>
        </div>
        <div className="mt-5 grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-6">
          <Meta label="Session ID" value={`SES${detail.batchId.slice(0, 3).toUpperCase()}`} />
          <Meta label="Created By" value={detail.createdByName ?? "—"} />
          <Meta label="Last Updated" value={fmtDate(detail.updatedAt)} />
          <Meta label="Sport" value={detail.sportName} />
          <Meta label="Court" value={detail.courtName} />
          <Meta label="Session Type" value="Membership Protected" />
          <Meta label="Capacity" value={`${detail.capacity} Players`} />
          <Meta label="Guest Release" value="Allowed" />
          <Meta label="Status" value={detail.isActive ? "Active" : "Paused"} />
        </div>
      </Card>

      <div className="grid gap-5 lg:grid-cols-3">
        {/* Left / main column */}
        <div className="space-y-5 lg:col-span-2">
          <div className="grid gap-5 sm:grid-cols-2">
            {/* Schedule */}
            <Card className="p-5">
              <p className="mb-3 flex items-center gap-2 text-sm font-semibold">
                <CalendarDays className="h-4 w-4" /> Schedule Information
              </p>
              <p className="text-xs text-muted-foreground">Days</p>
              <div className="mt-1 flex flex-wrap gap-1.5">
                {[...detail.daysOfWeek].sort((a, b) => a - b).map((d) => (
                  <span key={d} className="rounded bg-secondary px-2 py-0.5 text-xs font-medium">{DAY_ABBR[d]}</span>
                ))}
              </div>
              <div className="mt-3 grid grid-cols-2 gap-3">
                <Meta label="Time" value={`${formatClock(detail.startTime)} – ${formatClock(detail.endTime)}`} />
                <Meta label="Start Date" value={fmtDate(detail.createdAt)} />
                <Meta label="End Date" value="No Expiry" />
                <Meta label="Duration" value={durationLabel(detail.startTime, detail.endTime)} />
                <Meta label="Recurrence" value="Every Week" />
              </div>
            </Card>

            {/* Capacity & Utilization */}
            <Card className="p-5">
              <p className="mb-3 flex items-center gap-2 text-sm font-semibold">
                <Users className="h-4 w-4" /> Capacity &amp; Utilization (Today)
              </p>
              <CapacityDonut
                capacity={detail.capacity}
                members={detail.rosterCount}
                guestsBooked={detail.guestsBookedToday}
                availableToRelease={detail.availableToRelease}
              />
              <div className="mt-4">
                <div className="flex items-center justify-between text-xs text-muted-foreground">
                  <span>Utilization</span>
                  <span>{utilization}%</span>
                </div>
                <div className="mt-1 h-2 w-full overflow-hidden rounded-full bg-secondary">
                  <div
                    className={cn("h-full rounded-full", utilization >= 100 ? "bg-destructive" : utilization >= 70 ? "bg-warning" : "bg-success")}
                    style={{ width: `${Math.min(100, utilization)}%` }}
                  />
                </div>
              </div>
            </Card>
          </div>

          {/* Members Assigned */}
          <Card className="p-0">
            <div className="flex items-center justify-between p-4">
              <p className="flex items-center gap-2 text-sm font-semibold">
                <Users className="h-4 w-4" /> Members Assigned{" "}
                <span className="text-muted-foreground">({members?.length ?? 0} / {detail.capacity})</span>
              </p>
              <AddMemberButton
                batchId={batchId}
                facilityId={detail.facilityId}
                onAdded={load}
                disabled={(members?.length ?? 0) >= detail.capacity}
              />
            </div>
            <div className="overflow-x-auto border-t border-border">
              <table className="w-full text-sm">
                <thead className="text-left text-xs text-muted-foreground">
                  <tr>
                    <th className="px-4 py-2 font-medium">Member</th>
                    <th className="px-4 py-2 font-medium">Phone</th>
                    <th className="px-4 py-2 font-medium">Status</th>
                    <th className="px-4 py-2 font-medium">Added On</th>
                    <th className="px-4 py-2" />
                  </tr>
                </thead>
                <tbody>
                  {members === null ? (
                    <tr><td colSpan={5} className="px-4 py-4"><Skeleton className="h-8 w-full" /></td></tr>
                  ) : members.length === 0 ? (
                    <tr><td colSpan={5} className="px-4 py-6 text-center text-muted-foreground">No members assigned yet.</td></tr>
                  ) : (
                    members.map((m) => (
                      <tr key={m.id} className="border-t border-border/60">
                        <td className="px-4 py-2.5 font-medium text-foreground">{m.fullName}</td>
                        <td className="px-4 py-2.5 text-muted-foreground">{m.phone}</td>
                        <td className="px-4 py-2.5">
                          <Badge variant={m.status === "ACTIVE" ? "success" : "secondary"}>
                            {m.status === "ACTIVE" ? "Active" : "Inactive"}
                          </Badge>
                        </td>
                        <td className="px-4 py-2.5 text-muted-foreground">{fmtDate(m.addedOn)}</td>
                        <td className="px-4 py-2.5 text-right">
                          <DropdownMenu>
                            <DropdownMenuTrigger asChild>
                              <Button type="button" variant="ghost" size="icon" aria-label="Member actions">
                                <MoreVertical className="h-4 w-4" />
                              </Button>
                            </DropdownMenuTrigger>
                            <DropdownMenuContent align="end">
                              <DropdownMenuItem
                                onClick={async () => {
                                  await getMembershipSessionService().removeBatchMember(batchId, m.memberId);
                                  await load();
                                }}
                              >
                                <Trash2 className="mr-2 h-4 w-4" /> Remove from session
                              </DropdownMenuItem>
                            </DropdownMenuContent>
                          </DropdownMenu>
                        </td>
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </div>
          </Card>

          {/* Guest Slots (Today) */}
          <Card className="p-5">
            <p className="mb-3 flex items-center gap-2 text-sm font-semibold">
              <ShieldCheck className="h-4 w-4" /> Guest Slots (Today)
            </p>
            <div className="grid grid-cols-2 gap-3 sm:grid-cols-5">
              <GuestTile label="Total Capacity" value={detail.capacity} />
              <GuestTile label="Members Assigned" value={detail.rosterCount} />
              <GuestTile label="Guest Released" value={detail.releasedToday} />
              <GuestTile label="Guests Booked" value={detail.guestsBookedToday} />
              <GuestTile label="Available to Book" value={availableToBook} highlight />
            </div>
            <p className="mt-3 text-xs text-muted-foreground">
              Guest slots are released by the owner and available for booking on a first-come first-serve basis.
            </p>
          </Card>

          {/* Session Notes */}
          <Card className="p-5">
            <div className="flex items-center justify-between">
              <p className="text-sm font-semibold">Session Notes</p>
              {!notesEditing && (
                <Button type="button" variant="outline" size="sm" onClick={() => setNotesEditing(true)}>
                  <Pencil className="mr-1.5 h-4 w-4" /> Edit
                </Button>
              )}
            </div>
            {notesEditing ? (
              <NotesEditor
                batchId={batchId}
                initial={detail.notes ?? ""}
                onDone={async () => {
                  setNotesEditing(false);
                  await load();
                }}
                onCancel={() => setNotesEditing(false)}
              />
            ) : (
              <p className="mt-2 text-sm text-muted-foreground">{detail.notes || "No notes for this session yet."}</p>
            )}
          </Card>

          {/* Session Link */}
          <Card className="p-5">
            <p className="text-sm font-semibold">Session Link</p>
            <p className="text-xs text-muted-foreground">Share this link to allow members to register for this session.</p>
            <div className="mt-2 flex flex-wrap items-center gap-2">
              <Input readOnly value={joinUrl} className="h-9 max-w-md text-xs" />
              <Button type="button" variant="outline" size="sm" onClick={() => navigator.clipboard.writeText(joinUrl)}>
                <Copy className="mr-1.5 h-4 w-4" /> Copy
              </Button>
              <Button
                type="button"
                variant="outline"
                size="sm"
                onClick={() => {
                  const nav = navigator as Navigator & { share?: (d: ShareData) => Promise<void> };
                  if (typeof nav.share === "function") void nav.share({ url: joinUrl, title: detail.name });
                  else void navigator.clipboard.writeText(joinUrl);
                }}
              >
                <Share2 className="mr-1.5 h-4 w-4" /> Share Link
              </Button>
            </div>
          </Card>
        </div>

        {/* Right sidebar */}
        <div className="space-y-5">
          <Card className="p-5">
            <p className="mb-2 flex items-center gap-2 text-sm font-semibold">
              <MapPin className="h-4 w-4" /> Session Details
            </p>
            <div className="divide-y divide-border/60">
              <Row label="Facility" value={detail.facilityName ?? "—"} />
              <Row label="Address" value={detail.facilityAddress ?? "—"} />
              <Row label="Session Type" value="Membership Protected" />
              <Row label="Guest Release" value="Allowed" />
              <Row label="Payment Type" value="Included in Membership" />
              <Row label="Created By" value={detail.createdByName ?? "—"} />
              <Row label="Created On" value={fmtDateTime(detail.createdAt)} />
              <Row label="Last Updated" value={fmtDateTime(detail.updatedAt)} />
            </div>
          </Card>

          <Card className="p-5">
            <p className="mb-3 flex items-center gap-2 text-sm font-semibold">
              <Clock className="h-4 w-4" /> Activity Timeline
            </p>
            {activity === null ? (
              <Skeleton className="h-40 w-full rounded-lg" />
            ) : activity.length === 0 ? (
              <p className="text-sm text-muted-foreground">No activity yet.</p>
            ) : (
              <ol className="space-y-4">
                {activity.map((a, i) => (
                  <li key={i} className="flex gap-3 text-sm">
                    <span className="mt-1.5 h-2 w-2 shrink-0 rounded-full bg-primary" />
                    <div className="min-w-0">
                      <p className="text-foreground">{a.detail}</p>
                      <p className="text-xs text-muted-foreground">
                        {a.actor ? `${a.actor} · ` : ""}
                        {fmtDateTime(a.at)}
                      </p>
                    </div>
                  </li>
                ))}
              </ol>
            )}
          </Card>
        </div>
      </div>

      {editOpen && (
        <EditSessionDialog
          detail={detail}
          onClose={() => setEditOpen(false)}
          onSaved={async () => {
            setEditOpen(false);
            await load();
          }}
        />
      )}
      {releaseOpen && (
        <ReleaseGuestSlotsDialog
          detail={detail}
          onClose={() => setReleaseOpen(false)}
          onDone={async () => {
            setReleaseOpen(false);
            await load();
          }}
        />
      )}
    </div>
  );
}

function GuestTile({ label, value, highlight }: { label: string; value: number; highlight?: boolean }) {
  return (
    <div className={cn("rounded-lg border p-3 text-center", highlight ? "border-primary bg-primary/5" : "border-border")}>
      <p className="text-lg font-semibold text-foreground">{value}</p>
      <p className="text-xs text-muted-foreground">{label}</p>
    </div>
  );
}

function AddMemberButton({
  batchId,
  facilityId,
  onAdded,
  disabled,
}: {
  batchId: string;
  facilityId: string;
  onAdded: () => void;
  disabled?: boolean;
}) {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<Pick<Member, "id" | "fullName" | "phone">[]>([]);
  const [error, setError] = useState<string | null>(null);

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

  async function add(memberId: string) {
    setError(null);
    try {
      await getMembershipSessionService().assignBatchMember(batchId, memberId);
      setOpen(false);
      setQuery("");
      setResults([]);
      onAdded();
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Unable to add member.");
    }
  }

  return (
    <>
      <Button type="button" size="sm" variant="outline" disabled={disabled} onClick={() => setOpen(true)}>
        <Plus className="mr-1.5 h-4 w-4" /> Add Member
      </Button>
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Add member to session</DialogTitle>
          </DialogHeader>
          <Input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Search a member by name or phone…" autoFocus />
          {error && <p className="text-sm text-destructive">{error}</p>}
          <div className="max-h-56 space-y-1 overflow-y-auto">
            {results.map((r) => (
              <button
                key={r.id}
                type="button"
                onClick={() => add(r.id)}
                className="flex w-full items-center justify-between rounded px-2 py-2 text-left text-sm hover:bg-accent"
              >
                <span>{r.fullName}</span>
                <span className="text-xs text-muted-foreground">{r.phone}</span>
              </button>
            ))}
            {query.trim().length >= 2 && results.length === 0 && (
              <p className="px-2 py-2 text-sm text-muted-foreground">No members found.</p>
            )}
          </div>
        </DialogContent>
      </Dialog>
    </>
  );
}

function NotesEditor({
  batchId,
  initial,
  onDone,
  onCancel,
}: {
  batchId: string;
  initial: string;
  onDone: () => void;
  onCancel: () => void;
}) {
  const [value, setValue] = useState(initial);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function save() {
    setSaving(true);
    setError(null);
    try {
      await getMembershipSessionService().setSessionNotes(batchId, value);
      onDone();
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Unable to save notes.");
      setSaving(false);
    }
  }

  return (
    <div className="mt-2 space-y-2">
      <textarea
        value={value}
        onChange={(e) => setValue(e.target.value)}
        rows={3}
        className="w-full rounded-md border border-input bg-secondary/60 p-2 text-sm"
        placeholder="e.g. Please be on time. Carry your own shuttlecocks."
      />
      {error && <p className="text-sm text-destructive">{error}</p>}
      <div className="flex gap-2">
        <Button type="button" size="sm" onClick={save} disabled={saving}>
          {saving ? "Saving…" : "Save"}
        </Button>
        <Button type="button" size="sm" variant="outline" onClick={onCancel}>
          Cancel
        </Button>
      </div>
    </div>
  );
}

const DAYS = [
  { value: 1, label: "Mon" },
  { value: 2, label: "Tue" },
  { value: 3, label: "Wed" },
  { value: 4, label: "Thu" },
  { value: 5, label: "Fri" },
  { value: 6, label: "Sat" },
  { value: 0, label: "Sun" },
];

function EditSessionDialog({
  detail,
  onClose,
  onSaved,
}: {
  detail: MembershipSessionDetail;
  onClose: () => void;
  onSaved: () => void;
}) {
  const [name, setName] = useState(detail.name);
  const [days, setDays] = useState<number[]>(detail.daysOfWeek);
  const [startTime, setStartTime] = useState(detail.startTime.slice(0, 5));
  const [endTime, setEndTime] = useState(detail.endTime.slice(0, 5));
  const [capacity, setCapacity] = useState(String(detail.capacity));
  const [isActive, setIsActive] = useState(detail.isActive);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function save() {
    const cap = Number(capacity);
    if (name.trim().length < 2) return setError("Enter a session name.");
    if (days.length === 0) return setError("Select at least one day.");
    if (!Number.isInteger(cap) || cap <= 0) return setError("Enter a valid capacity.");
    if (endTime <= startTime) return setError("End time must be after start time.");
    setSaving(true);
    setError(null);
    try {
      await getMembershipSessionService().updateBatch(detail.batchId, {
        name: name.trim(),
        daysOfWeek: days,
        startTime,
        endTime,
        capacity: cap,
        isActive,
      });
      onSaved();
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Unable to save.");
      setSaving(false);
    }
  }

  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Edit Session</DialogTitle>
        </DialogHeader>
        <div className="space-y-3">
          <div className="space-y-1.5">
            <label className="text-sm font-medium">Session name</label>
            <Input value={name} onChange={(e) => setName(e.target.value)} />
          </div>
          <div className="space-y-1.5">
            <label className="text-sm font-medium">Days</label>
            <div className="flex flex-wrap gap-2">
              {DAYS.map((d) => (
                <button
                  key={d.value}
                  type="button"
                  onClick={() => setDays((p) => (p.includes(d.value) ? p.filter((x) => x !== d.value) : [...p, d.value]))}
                  className={cn(
                    "h-8 rounded-md border px-2 text-xs font-medium",
                    days.includes(d.value) ? "border-primary bg-primary text-primary-foreground" : "border-input bg-secondary/60",
                  )}
                >
                  {d.label}
                </button>
              ))}
            </div>
          </div>
          <div className="grid grid-cols-3 gap-2">
            <div className="space-y-1.5">
              <label className="text-sm font-medium">From</label>
              <input type="time" value={startTime} onChange={(e) => setStartTime(e.target.value)} className="h-10 w-full rounded-md border border-input bg-secondary/60 px-2 text-sm" />
            </div>
            <div className="space-y-1.5">
              <label className="text-sm font-medium">To</label>
              <input type="time" value={endTime} onChange={(e) => setEndTime(e.target.value)} className="h-10 w-full rounded-md border border-input bg-secondary/60 px-2 text-sm" />
            </div>
            <div className="space-y-1.5">
              <label className="text-sm font-medium">Capacity</label>
              <Input value={capacity} onChange={(e) => setCapacity(e.target.value)} inputMode="numeric" />
            </div>
          </div>
          <label className="flex items-center gap-2 text-sm">
            <input type="checkbox" checked={isActive} onChange={(e) => setIsActive(e.target.checked)} />
            Session is active
          </label>
          {error && <p className="text-sm text-destructive">{error}</p>}
        </div>
        <DialogFooter>
          <Button type="button" variant="outline" onClick={onClose}>Cancel</Button>
          <Button type="button" onClick={save} disabled={saving}>{saving ? "Saving…" : "Save changes"}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function ReleaseGuestSlotsDialog({
  detail,
  onClose,
  onDone,
}: {
  detail: MembershipSessionDetail;
  onClose: () => void;
  onDone: () => void;
}) {
  const maxRelease = detail.availableToRelease;
  const [count, setCount] = useState("1");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function release() {
    const n = Number(count);
    if (!Number.isInteger(n) || n <= 0) return setError("Enter a valid number of slots.");
    if (n > maxRelease) return setError(`Only ${maxRelease} slot(s) can be released today.`);
    setBusy(true);
    setError(null);
    try {
      const svc = getMembershipSessionService();
      const sessionId = await svc.getOrCreateSession(detail.batchId, todayIso());
      await svc.releaseCapacity(sessionId, n);
      onDone();
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Unable to release slots.");
      setBusy(false);
    }
  }

  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Release guest slots for today</DialogTitle>
        </DialogHeader>
        {detail.runsToday ? (
          <div className="space-y-3">
            <p className="text-sm text-muted-foreground">
              Up to <span className="font-medium text-foreground">{maxRelease}</span> unused slot(s) can be released for guest booking today.
            </p>
            <div className="space-y-1.5">
              <label className="text-sm font-medium">Slots to release</label>
              <Input value={count} onChange={(e) => setCount(e.target.value)} inputMode="numeric" />
            </div>
            {error && <p className="text-sm text-destructive">{error}</p>}
          </div>
        ) : (
          <p className="text-sm text-muted-foreground">This session is not scheduled to run today.</p>
        )}
        <DialogFooter>
          <Button type="button" variant="outline" onClick={onClose}>Cancel</Button>
          <Button type="button" onClick={release} disabled={busy || !detail.runsToday || maxRelease === 0}>
            {busy ? "Releasing…" : "Release"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}