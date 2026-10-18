import { addMonths, differenceInCalendarDays, format, parseISO } from "date-fns";
import type { EnrollmentBilling } from "@/features/coaching/types";

/**
 * The dates a monthly program charges the student: the start date, then the same day of each following
 * month (14 Oct → 14 Nov → 14 Dec …). Month ends clamp the way Razorpay does (31 Jan → 28 Feb → 31 Mar).
 *
 * The real schedule follows the day the student approves the mandate; this is what it is expected to be
 * if they approve on the start date.
 */
export function chargeDates(startIso: string, cycles: number): string[] {
  const start = parseISO(startIso);
  return Array.from({ length: Math.max(1, cycles) }, (_, i) => format(addMonths(start, i), "yyyy-MM-dd"));
}

/** How long the program runs, from its own start and end dates: "24 weeks · 6 months". Null without both dates. */
export function programLengthLabel(startIso: string | null | undefined, endIso: string | null | undefined): string | null {
  if (!startIso || !endIso) return null;
  const days = differenceInCalendarDays(parseISO(endIso), parseISO(startIso)) + 1;
  if (days <= 0) return null;
  const weeks = Math.max(1, Math.round(days / 7));
  const months = Math.max(1, Math.round(days / 30.4));
  return `${weeks} ${weeks === 1 ? "week" : "weeks"} · ${months} ${months === 1 ? "month" : "months"}`;
}

/** What one session works out to: the total fee spread over the program's sessions. Null when either is unknown. */
export function perSessionMinor(totalMinor: number, sessionCount: number | null | undefined): number | null {
  if (!sessionCount || sessionCount <= 0 || totalMinor <= 0) return null;
  return Math.round(totalMinor / sessionCount);
}

/** The date the next AutoPay charge is due — only while the subscription is actually charging. */
export function nextPaymentDate(billing: Pick<EnrollmentBilling, "kind" | "status" | "currentEnd"> | null | undefined): string | null {
  if (!billing || billing.kind !== "SUBSCRIPTION") return null;
  if (billing.status !== "ACTIVE" && billing.status !== "PENDING") return null;
  return billing.currentEnd;
}

/** Charges still to come: the plan's total minus those already collected (never below zero). */
export function chargesLeft(billing: Pick<EnrollmentBilling, "totalCycles" | "chargeCount">): number {
  return Math.max(billing.totalCycles - billing.chargeCount, 0);
}

/**
 * The charges still to come, one row each, all "not paid yet": the next payment date then the same day of
 * each following month, capped at what is left on the plan. Collected charges are not here — they are the
 * rows of the payments list, so a student's paid and upcoming charges never overwrite each other.
 */
export function upcomingCharges(
  billing: Pick<EnrollmentBilling, "kind" | "status" | "currentEnd" | "totalCycles" | "chargeCount"> | null | undefined,
  limit = 3,
): string[] {
  const next = nextPaymentDate(billing);
  if (!billing || !next) return [];
  const count = Math.min(chargesLeft(billing), limit);
  return count > 0 ? chargeDates(next, count) : [];
}

/**
 * A program's real total sessions: sessions per week × the weeks it runs. Falls back to the older "sessions per
 * package" count only when that can't be worked out (no weekly cadence, or no start/end date). Null when neither is
 * known. The same rule the Programs list and Program Details page use.
 */
export function programTotalSessions(p: {
  sessionsPerWeek?: number | null;
  startDate?: string | null;
  endDate?: string | null;
  sessionCount?: number | null;
}): number | null {
  if (p.sessionsPerWeek && p.startDate && p.endDate) {
    const weeks = Math.max(1, Math.round((new Date(p.endDate).getTime() - new Date(p.startDate).getTime()) / (7 * 86_400_000)));
    return p.sessionsPerWeek * weeks;
  }
  return p.sessionCount ?? null;
}
