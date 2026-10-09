import type { PlanSlot } from "@/features/memberships/plan-slots";
import type { MembershipListRow } from "@/features/memberships/types";

/** Weekdays in the order the Slots tab lists them: Monday first, Sunday last. */
export const WEEK_ORDER: { day: number; label: string }[] = [
  { day: 1, label: "Monday" },
  { day: 2, label: "Tuesday" },
  { day: 3, label: "Wednesday" },
  { day: 4, label: "Thursday" },
  { day: 5, label: "Friday" },
  { day: 6, label: "Saturday" },
  { day: 0, label: "Sunday" },
];

export interface DaySlotRow {
  day: number;
  label: string;
  /** Each slot that runs this day; empty = "Not available". */
  slots: PlanSlot[];
}

/** One row per weekday, with whichever of the plan's slots run on it. */
export function slotsByDay(slots: PlanSlot[]): DaySlotRow[] {
  return WEEK_ORDER.map(({ day, label }) => ({
    day,
    label,
    slots: slots.filter((s) => s.daysOfWeek.includes(day)).sort((a, b) => a.startTime.localeCompare(b.startTime)),
  }));
}

/** The memberships on a plan, newest start first. */
export function membersOfPlan(rows: MembershipListRow[], plan: { id: string; name: string }): MembershipListRow[] {
  // A membership made through the full form has no plan id — its name is the link back to the plan.
  const name = plan.name.trim().toLowerCase();
  return rows
    .filter((r) => r.planId === plan.id || (!r.planId && r.planName.trim().toLowerCase() === name))
    .sort((a, b) => b.startDate.localeCompare(a.startDate));
}

export type MemberStatusFilter = "all" | "active" | "inactive";

/** Search by name/phone, and filter by whether the membership is currently active. */
export function filterPlanMembers(rows: MembershipListRow[], query: string, status: MemberStatusFilter): MembershipListRow[] {
  const q = query.trim().toLowerCase();
  return rows.filter((r) => {
    if (status === "active" && r.status !== "active") return false;
    if (status === "inactive" && r.status === "active") return false;
    if (!q) return true;
    return r.memberName.toLowerCase().includes(q) || r.memberPhone.toLowerCase().includes(q);
  });
}

export function paginate<T>(items: T[], page: number, perPage: number): { items: T[]; pages: number; page: number } {
  const pages = Math.max(1, Math.ceil(items.length / perPage));
  const p = Math.min(Math.max(1, page), pages);
  return { items: items.slice((p - 1) * perPage, p * perPage), pages, page: p };
}

export interface PlanRevenue {
  totalMinor: number;
  members: number;
  avgPerMemberMinor: number;
}

/** Revenue from paid payments only, and the average per member who paid. */
export function planRevenue(payments: { membershipId: string | null; amountMinor: number; status: string }[]): PlanRevenue {
  const paid = payments.filter((p) => p.status === "paid");
  const totalMinor = paid.reduce((sum, p) => sum + p.amountMinor, 0);
  const members = new Set(paid.map((p) => p.membershipId).filter(Boolean)).size;
  return { totalMinor, members, avgPerMemberMinor: members === 0 ? 0 : Math.round(totalMinor / members) };
}

/** "AK" for "Arun Kumar". */
export function initialsOf(name: string): string {
  return name
    .split(" ")
    .filter(Boolean)
    .slice(0, 2)
    .map((p) => p[0]!.toUpperCase())
    .join("");
}

/** A copy's name: "Batch 2" → "Batch 2 (Copy)". */
export function duplicateName(name: string): string {
  return `${name.trim()} (Copy)`;
}

/** A plan slot with what the Slots tab edits: its capacity, how many hold it, and its sport. */
export interface PlanSlotDetail extends PlanSlot {
  capacity: number;
  enrolledCount: number;
  facilitySportId: string;
}

/**
 * The first thing wrong with an edited slot, or null when it can be saved. The capacity can't drop
 * below the members already on it.
 */
export function validateSlotEdit(input: {
  days: number[];
  startTime: string;
  endTime: string;
  capacity: number | null;
  enrolled: number;
}): string | null {
  if (input.days.length === 0) return "Select at least one day.";
  if (input.startTime >= input.endTime) return "The end time must be after the start time.";
  if (input.capacity === null || input.capacity < 1) return "Slot capacity must be at least 1.";
  if (input.capacity < input.enrolled) {
    return `${input.enrolled} ${input.enrolled === 1 ? "member is" : "members are"} already on this slot — capacity can't be lower than that.`;
  }
  return null;
}
