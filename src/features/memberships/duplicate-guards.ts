import type { MembershipListRow } from "@/features/memberships/types";

/** The part of a slot that makes two plans "the same": which court, which days, which hours. */
export interface SlotShape {
  courtId: string;
  daysOfWeek: number[];
  startTime: string;
  endTime: string;
}

const clock = (t: string) => t.slice(0, 5);

/** One slot as a comparable string — day order and a stray ":00" seconds suffix don't matter. */
export function slotSignature(s: SlotShape): string {
  const days = [...new Set(s.daysOfWeek)].sort((a, b) => a - b).join(",");
  return `${s.courtId}|${days}|${clock(s.startTime)}|${clock(s.endTime)}`;
}

/** A plan's whole slot set as one comparable string (order of slots doesn't matter). */
export function slotSetSignature(slots: SlotShape[]): string {
  return [...new Set(slots.map(slotSignature))].sort().join(";");
}

/**
 * The plan whose slots are exactly [draft] — same courts, same days, same hours — or null. Mon-Fri
 * 5-6 AM twice is a duplicate; Mon-Sun 5-6 AM next to it is a different plan and is allowed. A
 * draft with no slots never counts as a duplicate.
 */
export function findDuplicatePlan(
  draft: SlotShape[],
  plans: { id: string; name: string; slots: SlotShape[] }[],
  ignorePlanId?: string,
): { id: string; name: string } | null {
  if (draft.length === 0) return null;
  const wanted = slotSetSignature(draft);
  const match = plans.find((p) => p.id !== ignorePlanId && p.slots.length > 0 && slotSetSignature(p.slots) === wanted);
  return match ? { id: match.id, name: match.name } : null;
}

/** The comparable form of a phone number: digits only, last ten (so "+91 98765 43210" == "9876543210"). */
export function normalizePhone(phone: string): string {
  return phone.replace(/\D/g, "").slice(-10);
}

/**
 * The membership that already puts this person on this plan, or null. Same phone number = same
 * person. A lapsed (inactive) membership doesn't count, so someone can rejoin after theirs ends.
 */
export function findDuplicateMember(
  rows: MembershipListRow[],
  plan: { id: string; name: string },
  phone: string,
): MembershipListRow | null {
  const wanted = normalizePhone(phone);
  if (wanted.length < 7) return null;
  return (
    rows.find(
      (r) =>
        r.status !== "inactive" &&
        normalizePhone(r.memberPhone) === wanted &&
        (r.planId === plan.id || r.planName.trim().toLowerCase() === plan.name.trim().toLowerCase()),
    ) ?? null
  );
}

export const DUPLICATE_MEMBER_MESSAGE = "This member is already on this plan.";
export function duplicatePlanMessage(name: string): string {
  return `A plan with the same courts, days and timings already exists (“${name}”). Change the days or hours to create a different plan.`;
}
