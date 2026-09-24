import { addDays, startOfDay, startOfWeek } from "@/features/bookings/calendar-events";
import type { MemberScheduleRow } from "@/features/memberships/types";

/** One member's recurring court slot — a non-adjacent playing member (two batches) has two of these. */
export interface MemberBatchSlot {
  batchId: string;
  batchName: string;
  courtId: string;
  courtName: string;
  daysOfWeek: number[];
  startTime: string; // "HH:MM" or "HH:MM:SS"
  endTime: string;
}

export interface MemberScheduleSummary {
  memberId: string;
  fullName: string;
  phone: string;
  status: string;
  /** For the "Edit Schedule" quick action — the membership their batch assignment(s) were made
   *  under. Null only for a legacy assignment made before that link existed. */
  membershipId: string | null;
  slots: MemberBatchSlot[];
}

/**
 * `list_member_schedules` returns one row per (member, batch) — this groups them into one entry
 * per member, each with their full list of slots, sorted by name for the Member List tab.
 */
export function groupMemberSchedules(rows: MemberScheduleRow[]): MemberScheduleSummary[] {
  const byMember = new Map<string, MemberScheduleSummary>();
  for (const row of rows) {
    let entry = byMember.get(row.memberId);
    if (!entry) {
      entry = {
        memberId: row.memberId,
        fullName: row.fullName,
        phone: row.phone,
        status: row.status,
        membershipId: row.membershipId,
        slots: [],
      };
      byMember.set(row.memberId, entry);
    }
    // Prefer any non-null membershipId — a member's batches almost always share one membership.
    if (!entry.membershipId && row.membershipId) entry.membershipId = row.membershipId;
    entry.slots.push({
      batchId: row.batchId,
      batchName: row.batchName,
      courtId: row.courtId,
      courtName: row.courtName,
      daysOfWeek: row.daysOfWeek,
      startTime: row.startTime,
      endTime: row.endTime,
    });
  }
  return [...byMember.values()].sort((a, b) => a.fullName.localeCompare(b.fullName));
}

/** Every distinct court a member plays on, in the order their slots list them. */
export function assignedCourtNames(slots: MemberBatchSlot[]): string[] {
  return [...new Set(slots.map((s) => s.courtName))];
}

/** Every distinct court id a member plays on — the default scope for the calendar. */
export function assignedCourtIds(slots: MemberBatchSlot[]): string[] {
  return [...new Set(slots.map((s) => s.courtId))];
}

/**
 * The days a member normally plays and the time window, condensed for the Member Details panel
 * ("Morning (7 AM - 8 AM), Evening (6 PM - 7 PM)" style) — kept simple here as one line per
 * distinct start/end pair; the component adds the morning/evening framing.
 */
export function preferredTimeRanges(slots: MemberBatchSlot[]): { startTime: string; endTime: string }[] {
  const seen = new Set<string>();
  const out: { startTime: string; endTime: string }[] = [];
  for (const s of slots) {
    const key = `${s.startTime}-${s.endTime}`;
    if (seen.has(key)) continue;
    seen.add(key);
    out.push({ startTime: s.startTime, endTime: s.endTime });
  }
  return out;
}

export type ScheduleBlockKind = "MEMBER" | "GUEST" | "MAINTENANCE" | "CLOSED";

export interface ScheduleBlock {
  kind: ScheduleBlockKind;
  /** "HH:MM", 24h clock. */
  startTime: string;
  endTime: string;
  title: string;
  subtitle: string;
  href?: string;
}

/** A guest booking or maintenance block on some court, already resolved to real Date instants. */
export interface OtherCourtEvent {
  courtId: string;
  start: Date;
  end: Date;
  kind: "GUEST" | "MAINTENANCE";
  title: string;
  subtitle: string;
  href?: string;
}

function clock(t: string): string {
  return t.slice(0, 5);
}

function timeOfDay(d: Date): string {
  return `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
}

/**
 * Everything to draw for one calendar day: the member's own recurring slot(s) that land on this
 * weekday, plus any guest bookings / maintenance blocks on the same court(s) that day — scoped
 * to `visibleCourtIds` (the member's own courts by default, narrowed further by the Court
 * filter). A closed day (no operating hours at all) overrides everything else, matching the
 * design's "Court Closed" column.
 */
export function blocksForDay(
  date: Date,
  memberSlots: MemberBatchSlot[],
  otherEvents: OtherCourtEvent[],
  visibleCourtIds: string[],
  isClosed: boolean,
): ScheduleBlock[] {
  if (isClosed) {
    return [{ kind: "CLOSED", startTime: "00:00", endTime: "24:00", title: "Court Closed", subtitle: "" }];
  }

  const weekday = date.getDay();
  const blocks: ScheduleBlock[] = [];

  for (const slot of memberSlots) {
    if (!slot.daysOfWeek.includes(weekday)) continue;
    if (!visibleCourtIds.includes(slot.courtId)) continue;
    blocks.push({
      kind: "MEMBER",
      startTime: clock(slot.startTime),
      endTime: clock(slot.endTime),
      title: "Member Slot",
      subtitle: slot.courtName,
    });
  }

  const dayStart = startOfDay(date);
  const dayEnd = addDays(dayStart, 1);
  for (const ev of otherEvents) {
    if (ev.start >= dayEnd || ev.end <= dayStart) continue;
    if (!visibleCourtIds.includes(ev.courtId)) continue;
    blocks.push({
      kind: ev.kind,
      startTime: timeOfDay(ev.start < dayStart ? dayStart : ev.start),
      endTime: timeOfDay(ev.end > dayEnd ? dayEnd : ev.end),
      title: ev.title,
      subtitle: ev.subtitle,
      href: ev.href,
    });
  }

  return blocks.sort((a, b) => a.startTime.localeCompare(b.startTime));
}

/** The 7 dates of the week containing `anchor`, Monday first, matching the design. */
export function weekDates(anchor: Date): Date[] {
  const start = startOfWeek(anchor);
  return Array.from({ length: 7 }, (_, i) => addDays(start, i));
}
