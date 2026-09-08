"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { ChevronRight, Paperclip, Upload } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { maintenanceIcon } from "@/features/maintenance/icons";
import {
  PRIORITY_BADGE_CLASS,
  PRIORITY_LABEL,
  STATUS_BADGE_CLASS,
  STATUS_LABEL,
  STATUS_ORDER,
  formatDateTime,
  formatMoney,
} from "@/features/maintenance/status";
import type { MaintenanceStatus, MaintenanceTicketDetail } from "@/features/maintenance/types";
import { ScheduleDialog } from "@/features/maintenance/components/schedule-dialog";
import { AssignDialog } from "@/features/maintenance/components/assign-dialog";
import { CostDialog } from "@/features/maintenance/components/cost-dialog";
import { getMaintenanceService } from "@/services/maintenance";
import { ServiceError } from "@/services/shared/service-error";

export function TicketDetailPage({ ticketId }: { ticketId: string }) {
  const [ticket, setTicket] = useState<MaintenanceTicketDetail | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [scheduleOpen, setScheduleOpen] = useState(false);
  const [assignOpen, setAssignOpen] = useState(false);
  const [costOpen, setCostOpen] = useState(false);
  const [noteText, setNoteText] = useState("");

  const load = useCallback(async () => {
    setError(null);
    try {
      const detail = await getMaintenanceService().getTicketDetail(ticketId);
      setTicket(detail);
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Unable to load this ticket.");
    }
  }, [ticketId]);

  useEffect(() => {
    void load();
  }, [load]);

  async function run(action: string, fn: () => Promise<void>) {
    setBusy(action);
    setError(null);
    try {
      await fn();
      await load();
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Unable to complete this action.");
    } finally {
      setBusy(null);
    }
  }

  async function handleUpload(files: FileList | null) {
    if (!files || files.length === 0 || !ticket) return;
    setBusy("upload");
    setError(null);
    try {
      for (const file of Array.from(files).slice(0, 5)) {
        await getMaintenanceService().uploadAttachment(ticket.facilityId, ticket.id, file);
      }
      await load();
    } catch (e) {
      setError(e instanceof ServiceError ? e.message : "Unable to upload this file.");
    } finally {
      setBusy(null);
    }
  }

  if (error && !ticket) return <p className="text-sm text-destructive">{error}</p>;
  if (!ticket) return <Skeleton className="h-96 w-full rounded-xl" />;

  const CategoryIcon = maintenanceIcon(ticket.category.icon);
  const stepIndex = STATUS_ORDER.indexOf(ticket.status);

  return (
    <div className="space-y-4">
      <nav aria-label="Breadcrumb" className="flex items-center gap-1 text-xs text-muted-foreground">
        <Link href="/maintenance/tickets" className="hover:text-foreground">
          Maintenance Tickets
        </Link>
        <ChevronRight className="h-3 w-3" aria-hidden />
        <span className="text-foreground">{ticket.code}</span>
      </nav>

      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="flex items-start gap-3">
          <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-primary/15 text-primary">
            <CategoryIcon className="h-5 w-5" aria-hidden />
          </span>
          <div>
            <h1 className="text-xl font-semibold">
              {ticket.code} <span className="font-normal text-muted-foreground">— {ticket.title}</span>
            </h1>
            <p className="text-sm text-muted-foreground">
              {ticket.court.name} · {ticket.sportName ?? "—"} · {ticket.category.name}
            </p>
          </div>
        </div>
        <div className="flex items-center gap-2">
          <Badge className={PRIORITY_BADGE_CLASS[ticket.priority]}>{PRIORITY_LABEL[ticket.priority]}</Badge>
          <Badge className={STATUS_BADGE_CLASS[ticket.status]}>{STATUS_LABEL[ticket.status]}</Badge>
        </div>
      </div>

      {error && <p className="text-sm text-destructive">{error}</p>}

      <div className="grid gap-4 lg:grid-cols-[1fr_320px]">
        <div className="space-y-4">
          <Card className="space-y-3 p-4">
            <h2 className="text-sm font-semibold">Issue Information</h2>
            <div className="grid gap-x-4 gap-y-2 text-sm sm:grid-cols-2">
              <InfoRow label="Reported By" value={ticket.reportedBy.name} />
              <InfoRow label="Reported On" value={formatDateTime(ticket.reportedAt)} />
              <InfoRow label="Assigned To" value={ticket.assignedTo?.name ?? "Unassigned"} />
              <InfoRow label="Status" value={STATUS_LABEL[ticket.status]} />
            </div>
            <div>
              <p className="text-xs text-muted-foreground">Description</p>
              <p className="mt-1 whitespace-pre-wrap text-sm">{ticket.description}</p>
            </div>
            {ticket.notes && (
              <div>
                <p className="text-xs text-muted-foreground">Additional Notes</p>
                <p className="mt-1 whitespace-pre-wrap text-sm">{ticket.notes}</p>
              </div>
            )}
          </Card>

          <Card className="space-y-3 p-4">
            <h2 className="text-sm font-semibold">Schedule</h2>
            <div className="grid gap-x-4 gap-y-2 text-sm sm:grid-cols-2">
              <InfoRow label="Scheduled Start" value={formatDateTime(ticket.scheduledStart)} />
              <InfoRow label="Scheduled End" value={formatDateTime(ticket.scheduledEnd)} />
              <InfoRow label="Actual Start" value={formatDateTime(ticket.actualStart)} />
              <InfoRow label="Actual End" value={formatDateTime(ticket.actualEnd)} />
            </div>
          </Card>

          {(ticket.affectedBookings.length > 0 || ticket.affectedSessions.length > 0) && (
            <Card className="space-y-3 p-4">
              <h2 className="text-sm font-semibold">Affected Bookings</h2>
              {ticket.affectedBookings.length === 0 ? (
                <p className="text-sm text-muted-foreground">No ad-hoc bookings overlap this schedule.</p>
              ) : (
                <div className="overflow-x-auto">
                  <table className="w-full text-sm">
                    <thead className="text-left text-xs text-muted-foreground">
                      <tr>
                        <th className="py-1.5 pr-3 font-medium">Customer</th>
                        <th className="py-1.5 pr-3 font-medium">Time</th>
                        <th className="py-1.5 pr-3 font-medium">Status</th>
                        <th className="py-1.5 pr-3 font-medium">Payment</th>
                      </tr>
                    </thead>
                    <tbody>
                      {ticket.affectedBookings.map((b) => (
                        <tr key={b.bookingId} className="border-t border-border">
                          <td className="py-1.5 pr-3">{b.customerType === "GUEST" ? b.guestName ?? "Guest" : "Member"}</td>
                          <td className="py-1.5 pr-3">
                            {formatDateTime(b.startTime)} – {new Date(b.endTime).toLocaleTimeString("en-IN", { hour: "numeric", minute: "2-digit" })}
                          </td>
                          <td className="py-1.5 pr-3 capitalize">{b.status}</td>
                          <td className="py-1.5 pr-3">{b.paymentStatus}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                  <p className="mt-2 text-xs text-muted-foreground">
                    Reschedule, cancel or refund these from the Bookings page — Maintenance never changes a booking automatically.
                  </p>
                </div>
              )}
              {ticket.affectedSessions.length > 0 && (
                <div className="pt-2">
                  <p className="text-xs font-medium text-muted-foreground">Membership sessions also affected</p>
                  <ul className="mt-1 space-y-1 text-sm">
                    {ticket.affectedSessions.map((s, i) => (
                      <li key={`${s.batchId}-${i}`}>
                        {s.batchName} · {s.memberBookedCount} member(s), {s.guestBookedCount} guest(s) booked
                      </li>
                    ))}
                  </ul>
                </div>
              )}
            </Card>
          )}

          <Card className="space-y-3 p-4">
            <div className="flex items-center justify-between">
              <h2 className="text-sm font-semibold">Attachments</h2>
              <label className="flex cursor-pointer items-center gap-1.5 text-xs text-primary">
                <Upload className="h-3.5 w-3.5" /> Add Photo
                <input type="file" accept="image/*,application/pdf" multiple hidden onChange={(e) => void handleUpload(e.target.files)} disabled={busy === "upload"} />
              </label>
            </div>
            {ticket.attachments.length === 0 ? (
              <p className="text-sm text-muted-foreground">No attachments yet.</p>
            ) : (
              <ul className="flex flex-wrap gap-2">
                {ticket.attachments.map((a) => (
                  <li key={a.id} className="flex items-center gap-1.5 rounded-md border border-border px-2.5 py-1.5 text-xs">
                    <Paperclip className="h-3 w-3 text-muted-foreground" /> {a.fileName}
                  </li>
                ))}
              </ul>
            )}
          </Card>

          <Card className="space-y-3 p-4">
            <h2 className="text-sm font-semibold">Notes / Activity</h2>
            <form
              className="flex gap-2"
              onSubmit={(e) => {
                e.preventDefault();
                if (!noteText.trim()) return;
                void run("note", async () => {
                  await getMaintenanceService().addNote(ticket.id, noteText.trim());
                  setNoteText("");
                });
              }}
            >
              <input
                value={noteText}
                onChange={(e) => setNoteText(e.target.value)}
                placeholder="Add a note…"
                className="h-9 flex-1 rounded-md border border-input bg-background px-2.5 text-sm"
              />
              <Button type="submit" size="sm" disabled={busy === "note"}>
                Add
              </Button>
            </form>
            <ol className="space-y-2 border-l border-border pl-3">
              {ticket.activity.map((e) => (
                <li key={e.id} className="text-sm">
                  <p>
                    <span className="font-medium">{activityLabel(e.eventType)}</span>
                    {e.note ? <span className="text-muted-foreground"> — {e.note}</span> : null}
                  </p>
                  <p className="text-[11px] text-muted-foreground">
                    {formatDateTime(e.createdAt)} {e.actorName ? `· ${e.actorName}` : ""}
                  </p>
                </li>
              ))}
            </ol>
          </Card>
        </div>

        <div className="space-y-4">
          <Card className="space-y-3 p-4">
            <h2 className="text-sm font-semibold">Status Workflow</h2>
            <ol className="space-y-2">
              {STATUS_ORDER.map((s, i) => (
                <li key={s} className="flex items-center gap-2 text-xs">
                  <span className={`h-2 w-2 rounded-full ${i <= stepIndex ? "bg-primary" : "bg-border"}`} />
                  <span className={i <= stepIndex ? "font-medium text-foreground" : "text-muted-foreground"}>{STATUS_LABEL[s]}</span>
                </li>
              ))}
            </ol>
          </Card>

          <Card className="space-y-2 p-4">
            <h2 className="text-sm font-semibold">Quick Actions</h2>
            <TicketActions
              status={ticket.status}
              busy={busy}
              onAssign={() => setAssignOpen(true)}
              onSchedule={() => setScheduleOpen(true)}
              onStart={() => void run("start", () => getMaintenanceService().startMaintenance(ticket.id))}
              onCost={() => setCostOpen(true)}
              onResolve={() => void run("resolve", () => getMaintenanceService().resolveTicket(ticket.id))}
              onReopen={() => void run("reopen", () => getMaintenanceService().reopenTicket(ticket.id))}
              onClose={() => void run("close", () => getMaintenanceService().closeTicket(ticket.id))}
            />
          </Card>

          <Card className="space-y-2 p-4">
            <div className="flex items-center justify-between">
              <h2 className="text-sm font-semibold">Cost</h2>
              <Button variant="ghost" size="sm" onClick={() => setCostOpen(true)}>
                Edit
              </Button>
            </div>
            <InfoRow label="Estimated" value={formatMoney(ticket.estimatedCostMinor, ticket.currency)} />
            <InfoRow label="Actual" value={formatMoney(ticket.actualCostMinor, ticket.currency)} />
            {ticket.expenseId && <p className="text-[11px] text-muted-foreground">Posted to Finance → Expenses.</p>}
          </Card>

          {ticket.activeBlock && (
            <Card className="space-y-1 p-4 text-sm">
              <h2 className="text-sm font-semibold">Court Block</h2>
              <p className="text-muted-foreground">
                {formatDateTime(ticket.activeBlock.startTime)} → {formatDateTime(ticket.activeBlock.endTime)}
              </p>
            </Card>
          )}
        </div>
      </div>

      <ScheduleDialog open={scheduleOpen} onOpenChange={setScheduleOpen} ticketId={ticket.id} courtId={ticket.court.id} onScheduled={() => void load()} />
      <AssignDialog open={assignOpen} onOpenChange={setAssignOpen} ticketId={ticket.id} facilityId={ticket.facilityId} onAssigned={() => void load()} />
      <CostDialog open={costOpen} onOpenChange={setCostOpen} ticketId={ticket.id} currency={ticket.currency} onSaved={() => void load()} />
    </div>
  );
}

function InfoRow({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <p className="text-xs text-muted-foreground">{label}</p>
      <p className="font-medium">{value}</p>
    </div>
  );
}

function activityLabel(eventType: string): string {
  return eventType
    .toLowerCase()
    .split("_")
    .map((w) => w[0]?.toUpperCase() + w.slice(1))
    .join(" ");
}

function TicketActions({
  status,
  busy,
  onAssign,
  onSchedule,
  onStart,
  onCost,
  onResolve,
  onReopen,
  onClose,
}: {
  status: MaintenanceStatus;
  busy: string | null;
  onAssign: () => void;
  onSchedule: () => void;
  onStart: () => void;
  onCost: () => void;
  onResolve: () => void;
  onReopen: () => void;
  onClose: () => void;
}) {
  const buttons: { label: string; onClick: () => void; key: string }[] = [];

  if (status === "REPORTED" || status === "ASSIGNED") {
    buttons.push({ label: "Assign to Staff", onClick: onAssign, key: "assign" });
    buttons.push({ label: "Schedule Maintenance", onClick: onSchedule, key: "schedule" });
  }
  if (status === "SCHEDULED") {
    buttons.push({ label: "Start Maintenance", onClick: onStart, key: "start" });
    buttons.push({ label: "Reschedule", onClick: onSchedule, key: "reschedule" });
  }
  if (status === "ASSIGNED") {
    buttons.push({ label: "Start Maintenance", onClick: onStart, key: "start-assigned" });
  }
  if (status === "IN_PROGRESS") {
    buttons.push({ label: "Add / Edit Cost", onClick: onCost, key: "cost" });
    buttons.push({ label: "Mark Resolved", onClick: onResolve, key: "resolve" });
  }
  if (status === "RESOLVED") {
    buttons.push({ label: "Reopen", onClick: onReopen, key: "reopen" });
    buttons.push({ label: "Close Ticket", onClick: onClose, key: "close" });
  }
  if (status !== "CLOSED" && status !== "RESOLVED") {
    buttons.push({ label: "Close Ticket", onClick: onClose, key: "close-early" });
  }

  return (
    <div className="grid gap-1.5">
      {buttons.map((b) => (
        <Button key={b.key} variant="outline" size="sm" className="justify-start" onClick={b.onClick} disabled={busy !== null}>
          {b.label}
        </Button>
      ))}
    </div>
  );
}
