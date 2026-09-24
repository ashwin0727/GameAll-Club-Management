"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { CalendarClock, CalendarDays, Clock, History, Info, MapPin, Pencil, Plus, Repeat2, Trash2 } from "lucide-react";
import { Card } from "@/components/ui/card";
import { assignedCourtNames, preferredTimeRanges, type MemberScheduleSummary } from "@/features/memberships/member-schedule";
import { formatClock12 } from "@/features/memberships/components/member-schedule-grid";
import { useMembershipDetailFor } from "@/features/memberships/hooks/use-member-schedule";
import { cn } from "@/lib/utils";

function initials(name: string): string {
  return name.split(" ").filter(Boolean).slice(0, 2).map((p) => p[0]!.toUpperCase()).join("");
}

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

/** "30 Sep 2026" — reads the date-only ISO string as a local calendar date, not a UTC instant,
 *  so a plan ending "2026-09-30" never displays as the 29th in a timezone behind UTC. */
function formatValidTill(iso: string): string {
  const [y, m, d] = iso.split("-").map(Number);
  return `${d} ${MONTHS[(m ?? 1) - 1]} ${y}`;
}

/** "Morning" for anything starting before noon, "Evening" otherwise — matching the design's
 *  "Morning (7 AM - 8 AM), Evening (6 PM - 7 PM)" framing without inventing more precise bands. */
function timeOfDayLabel(startTime: string): string {
  const hour = Number(startTime.split(":")[0] ?? 0);
  return hour < 12 ? "Morning" : "Evening";
}

interface QuickAction {
  key: string;
  icon: React.ComponentType<{ className?: string }>;
  title: string;
  subtitle: string;
  tone: string;
}

const QUICK_ACTIONS: QuickAction[] = [
  { key: "add", icon: Plus, title: "Add Time Slot", subtitle: "Assign a new time slot for this member", tone: "bg-success/15 text-success" },
  { key: "edit", icon: Pencil, title: "Edit Schedule", subtitle: "Modify or reschedule existing slots", tone: "bg-blue-500/15 text-blue-600 dark:text-blue-400" },
  { key: "remove", icon: Trash2, title: "Remove Slot", subtitle: "Cancel a specific time slot", tone: "bg-destructive/15 text-destructive" },
  { key: "swap", icon: Repeat2, title: "Swap Slot", subtitle: "Move to a different time or court", tone: "bg-muted text-muted-foreground" },
  { key: "history", icon: History, title: "View History", subtitle: "See past schedule changes", tone: "bg-muted text-muted-foreground" },
];

/**
 * Member Details + Quick Actions, matching the design's right rail. Per-date slot edits (Add /
 * Remove / Swap) aren't possible yet — the schema only stores a recurring weekly pattern per
 * batch, not per-occurrence exceptions — so those three show a "coming soon" note rather than
 * pretend to work. Edit Schedule and View History are real: they open the member's existing
 * Edit Membership / Membership Detail pages.
 */
export function MemberScheduleDetailsPanel({ member }: { member: MemberScheduleSummary }) {
  const router = useRouter();
  const [notice, setNotice] = useState<string | null>(null);
  const detailQuery = useMembershipDetailFor(member.membershipId);
  const detail = detailQuery.data;

  const courts = assignedCourtNames(member.slots);
  const ranges = preferredTimeRanges(member.slots);
  const preferredTime = ranges
    .map((r) => `${timeOfDayLabel(r.startTime)} (${formatClock12(r.startTime)} - ${formatClock12(r.endTime)})`)
    .join(", ");

  function onAction(key: string) {
    if (key === "edit") {
      if (member.membershipId) router.push(`/memberships/${member.membershipId}/edit`);
      else setNotice("This member has no linked membership to edit yet.");
      return;
    }
    if (key === "history") {
      if (member.membershipId) router.push(`/memberships/${member.membershipId}`);
      else setNotice("This member has no linked membership yet.");
      return;
    }
    setNotice("Per-slot editing is coming soon — for now, use Edit Schedule to change the member's whole weekly pattern.");
  }

  return (
    <div className="space-y-4">
      <Card className="space-y-3 rounded-xl p-4">
        <div className="flex items-center justify-between gap-2">
          <p className="text-sm font-bold text-black dark:text-foreground">Member Details</p>
          <button
            type="button"
            onClick={() => onAction("edit")}
            className="flex items-center gap-1 rounded-lg border border-input px-2 py-1 text-xs font-medium text-muted-foreground transition-colors hover:bg-accent"
          >
            <Pencil className="h-3 w-3" aria-hidden />
            Edit
          </button>
        </div>

        <div className="flex items-center gap-3">
          <span className="flex h-12 w-12 shrink-0 items-center justify-center rounded-full bg-muted text-sm font-semibold text-muted-foreground">
            {initials(member.fullName)}
          </span>
          <div className="min-w-0">
            <div className="flex flex-wrap items-center gap-1.5">
              <p className="truncate text-sm font-bold text-black dark:text-foreground">{member.fullName}</p>
              <span
                className={cn(
                  "whitespace-nowrap rounded-full px-1.5 py-0.5 text-[10px] font-semibold",
                  member.status === "ACTIVE" ? "bg-success/15 text-success" : "bg-muted-foreground/15 text-muted-foreground",
                )}
              >
                {member.status === "ACTIVE" ? "Active" : "Inactive"}
              </span>
            </div>
            <p className="truncate text-xs text-muted-foreground">
              {member.phone}
              {detail?.member.email ? ` | ${detail.member.email}` : ""}
            </p>
          </div>
        </div>

        <div className="space-y-2.5 border-t border-border pt-3 text-xs">
          <div className="flex items-start gap-2">
            <CalendarClock className="mt-0.5 h-3.5 w-3.5 shrink-0 text-muted-foreground" aria-hidden />
            <div>
              <p className="text-muted-foreground">Membership Plan</p>
              <p className="font-medium text-foreground">{detail?.membership.name ?? "—"}</p>
            </div>
          </div>
          <div className="flex items-start gap-2">
            <CalendarDays className="mt-0.5 h-3.5 w-3.5 shrink-0 text-muted-foreground" aria-hidden />
            <div>
              <p className="text-muted-foreground">Valid Till</p>
              <p className="font-medium text-foreground">{detail ? formatValidTill(detail.membership.endDate) : "—"}</p>
            </div>
          </div>
          <div className="flex items-start gap-2">
            <MapPin className="mt-0.5 h-3.5 w-3.5 shrink-0 text-muted-foreground" aria-hidden />
            <div>
              <p className="text-muted-foreground">Assigned Courts</p>
              <p className="font-medium text-foreground">{courts.length > 0 ? courts.join(", ") : "—"}</p>
            </div>
          </div>
          <div className="flex items-start gap-2">
            <Clock className="mt-0.5 h-3.5 w-3.5 shrink-0 text-muted-foreground" aria-hidden />
            <div>
              <p className="text-muted-foreground">Preferred Time</p>
              <p className="font-medium text-foreground">{preferredTime || "—"}</p>
            </div>
          </div>
        </div>
      </Card>

      <Card className="space-y-2 rounded-xl p-4">
        <p className="text-sm font-bold text-black dark:text-foreground">Quick Actions</p>
        <div className="space-y-1.5">
          {QUICK_ACTIONS.map((a) => (
            <button
              key={a.key}
              type="button"
              onClick={() => onAction(a.key)}
              className="flex w-full items-center gap-3 rounded-lg p-2 text-left transition-colors hover:bg-accent"
            >
              <span className={cn("flex h-9 w-9 shrink-0 items-center justify-center rounded-lg", a.tone)}>
                <a.icon className="h-4 w-4" aria-hidden />
              </span>
              <span className="min-w-0">
                <span className="block text-sm font-semibold text-foreground">{a.title}</span>
                <span className="block truncate text-xs text-muted-foreground">{a.subtitle}</span>
              </span>
            </button>
          ))}
        </div>

        {notice && (
          <div className="flex items-start gap-2 rounded-lg bg-blue-500/10 p-3 text-xs text-foreground/80">
            <Info className="mt-0.5 h-3.5 w-3.5 shrink-0 text-blue-600 dark:text-blue-400" aria-hidden />
            <p>{notice}</p>
          </div>
        )}
      </Card>
    </div>
  );
}
