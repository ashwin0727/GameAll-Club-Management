import { formatClock, formatSlot } from "@/features/memberships/slot-format";
import type { MembershipListRow } from "@/features/memberships/types";
import type { EnrollmentRow } from "@/features/coaching/types";
import { formatCurrency } from "@/features/pricing/money";
import { bookingReference, type BookingRow } from "@/features/bookings/list-utils";

const DAY_ABBR = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const DAY_MS = 86_400_000;
const AVG_MONTH_DAYS = 30.4375;

/** "2026-09-01" → local midnight (a bare `new Date("2026-09-01")` would be UTC and can slip a day). */
export function parseLocalDate(iso: string): Date {
  const [y, m, d] = iso.slice(0, 10).split("-").map(Number);
  return new Date(y!, (m ?? 1) - 1, d ?? 1);
}

/**
 * How many months a membership covers: its paid period from start to end,
 * rounded to whole months and never below one. A monthly membership (1 Sep →
 * 30 Sep) is 1; a quarterly one (1 Sep → 30 Nov) is 3.
 */
export function monthsBetween(startIso: string, endIso: string): number {
  const days = (parseLocalDate(endIso).getTime() - parseLocalDate(startIso).getTime()) / DAY_MS;
  return Math.max(1, Math.round(days / AVG_MONTH_DAYS));
}

export function formatMonths(months: number): string {
  return `${months} ${months === 1 ? "Month" : "Months"}`;
}

/** [1,2,3,4,5] → "Weekdays", [0,6] → "Weekends", [1,3,5] → "Mon · Wed · Fri", all seven → "Every day". */
export function daysPattern(days: number[]): string {
  const set = [...new Set(days)].sort((a, b) => a - b);
  if (set.length === 0) return "";
  if (set.length === 7) return "Every day";
  if (set.length === 5 && [1, 2, 3, 4, 5].every((d) => set.includes(d))) return "Weekdays";
  if (set.length === 2 && set.includes(0) && set.includes(6)) return "Weekends";
  return set.map((d) => DAY_ABBR[d]).join(" · ");
}

/** 720 → "12 hrs", 90 → "1.5 hrs", 60 → "1 hr". */
export function hoursLabel(minutes: number): string {
  const h = Math.round((minutes / 60) * 10) / 10;
  return `${h} ${h === 1 ? "hr" : "hrs"}`;
}

const joinParts = (parts: (string | null | undefined | false)[]) => parts.filter(Boolean).join(" · ");

/**
 * A membership as a table row. Its duration is how many months it covers
 * ("1 Month", "3 Months") and its amount is the total for that period — the
 * monthly price times those months — with the monthly figure noted underneath
 * when it covers more than one.
 */
export function membershipToRow(m: MembershipListRow, courts: { id: string; name: string }[]): BookingRow {
  const months = monthsBetween(m.startDate, m.endDate);
  const start = parseLocalDate(m.startDate);
  const monthlyMinor = Math.round(m.monthlyPriceInr * 100);
  const court = m.slot?.courtName ? courts.find((c) => c.name.toLowerCase() === m.slot!.courtName!.toLowerCase()) : undefined;

  const status: BookingRow["status"] = m.status === "active" ? "confirmed" : m.status === "payment_incomplete" ? "pending" : "cancelled";
  const statusLabel = m.status === "active" ? "Active" : m.status === "payment_incomplete" ? "Payment pending" : "Inactive";

  return {
    id: `membership-${m.membershipId}`,
    booking: null,
    kind: "MEMBERSHIP",
    customerName: m.memberName,
    customerPhone: m.memberPhone,
    courtId: court?.id ?? "",
    courtIds: court ? [court.id] : [],
    courtLabel: court ? null : (m.slot?.courtName ?? null),
    start,
    end: parseLocalDate(m.endDate),
    timeLabel: m.slot?.startTime && m.slot.endTime
      ? joinParts([daysPattern(m.slot.daysOfWeek), `${formatClock(m.slot.startTime)} – ${formatClock(m.slot.endTime)}`])
      : m.slot
        ? formatSlot(m.slot.daysOfWeek, m.slot.startTime, m.slot.endTime)
        : `Plan: ${m.planName}`,
    durationMin: months * 30 * 24 * 60,
    durationLabel: formatMonths(months),
    durationSub: m.planName,
    amountMinor: monthlyMinor * months,
    amountSub: months > 1 ? `${formatCurrency(monthlyMinor, "INR")} / month` : null,
    // An active membership has its payment in; a pending or inactive one does not.
    collectedMinor: status === "confirmed" ? monthlyMinor * months : 0,
    currency: "INR",
    status,
    statusLabel,
    reference: bookingReference(m.membershipId, "MEMBERSHIP"),
    href: `/memberships/${m.membershipId}`,
  };
}

/** What the coaching program's own schedule says, gathered once per program. */
export interface ProgramSchedule {
  /** Length of one session, in minutes. */
  sessionMinutes: number | null;
  /** Days of the week its sessions run (0 = Sun). */
  days: number[];
  courtIds: string[];
}

/**
 * A coaching enrolment as a table row. Its duration is the number of sessions,
 * with the total hours and the weekday / weekend pattern underneath; its amount
 * is the fee, with what has been paid so far noted underneath.
 */
export function enrollmentToRow(e: EnrollmentRow, schedule: ProgramSchedule | undefined): BookingRow {
  const perSession = schedule?.sessionMinutes ?? null;
  const totalMinutes = e.sessionsTotal != null && perSession != null ? e.sessionsTotal * perSession : null;
  const pattern = daysPattern(schedule?.days ?? []);

  const paymentNote =
    e.paymentStatus === "INCLUDED"
      ? "Included in membership"
      : e.paymentStatus === "PAID"
        ? "Paid in full"
        : e.paymentStatus === "PARTIAL"
          ? `Paid ${formatCurrency(e.paidMinor, "INR")}`
          : "Payment pending";

  const status: BookingRow["status"] =
    e.status === "ACTIVE" ? "confirmed" : e.status === "PAUSED" ? "pending" : e.status === "COMPLETED" ? "completed" : "cancelled";
  const statusLabel = e.status === "ACTIVE" ? "Active" : e.status === "PAUSED" ? "Paused" : e.status === "COMPLETED" ? "Completed" : "Cancelled";

  return {
    id: `coaching-${e.id}`,
    booking: null,
    kind: "COACHING",
    customerName: e.studentName,
    customerPhone: e.studentPhone,
    courtId: schedule?.courtIds[0] ?? "",
    courtIds: schedule?.courtIds ?? [],
    courtLabel: null,
    start: parseLocalDate(e.startDate),
    end: e.endDate ? parseLocalDate(e.endDate) : parseLocalDate(e.startDate),
    timeLabel: joinParts([e.programName, e.coachName ? `Coach ${e.coachName}` : null]),
    durationMin: totalMinutes ?? (e.sessionsTotal ?? 0) * 60,
    durationLabel: e.sessionsTotal != null ? `${e.sessionsTotal} ${e.sessionsTotal === 1 ? "Session" : "Sessions"}` : "Ongoing",
    durationSub: joinParts([totalMinutes != null && hoursLabel(totalMinutes), pattern]) || null,
    amountMinor: e.priceMinor,
    amountSub: paymentNote,
    collectedMinor: e.status === "CANCELLED" ? 0 : e.paidMinor,
    currency: "INR",
    status,
    statusLabel,
    reference: bookingReference(e.id, "COACHING"),
    href: `/coaching/enrollments/${e.id}`,
  };
}
