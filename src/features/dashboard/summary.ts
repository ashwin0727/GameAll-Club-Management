import type { OperatingDay } from "@/features/operating-hours/types";
import type {
  AttentionItem,
  CourtUtilizationEntry,
  DateRange,
  DateRangePreset,
  KpiValue,
  MembershipSummary,
  PaymentSummary,
  SportUtilizationEntry,
  UtilizationSummary,
} from "@/features/dashboard/types";

export interface ResolvedPeriod {
  current: DateRange;
  /** null for CUSTOM — an arbitrary range has no well-defined "previous period" to diff against. */
  previous: DateRange | null;
}

function startOfDay(d: Date): Date {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate());
}
function addDays(d: Date, days: number): Date {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate() + days);
}

/** Resolves a preset (relative to `now`) into a [from, to) range plus the equal-length prior period, for comparison. */
export function resolveDateRange(
  preset: DateRangePreset,
  now: Date,
  custom?: { from: string; to: string },
): ResolvedPeriod {
  if (preset === "CUSTOM") {
    if (!custom) throw new Error("CUSTOM preset requires a from/to range.");
    return { current: { from: custom.from, to: custom.to }, previous: null };
  }

  const today0 = startOfDay(now);

  if (preset === "TODAY") {
    return {
      current: { from: today0.toISOString(), to: addDays(today0, 1).toISOString() },
      previous: { from: addDays(today0, -1).toISOString(), to: today0.toISOString() },
    };
  }
  if (preset === "YESTERDAY") {
    const y = addDays(today0, -1);
    return {
      current: { from: y.toISOString(), to: today0.toISOString() },
      previous: { from: addDays(y, -1).toISOString(), to: y.toISOString() },
    };
  }
  if (preset === "THIS_WEEK") {
    const dayIndex = today0.getDay(); // 0 = Sunday
    const weekStart = addDays(today0, -dayIndex);
    return {
      current: { from: weekStart.toISOString(), to: addDays(today0, 1).toISOString() },
      previous: { from: addDays(weekStart, -7).toISOString(), to: weekStart.toISOString() },
    };
  }
  // THIS_MONTH
  const monthStart = new Date(today0.getFullYear(), today0.getMonth(), 1);
  const prevMonthStart = new Date(today0.getFullYear(), today0.getMonth() - 1, 1);
  return {
    current: { from: monthStart.toISOString(), to: addDays(today0, 1).toISOString() },
    previous: { from: prevMonthStart.toISOString(), to: monthStart.toISOString() },
  };
}

export function computeKpiValue(current: number, previous: number | null): KpiValue {
  if (previous === null) return { value: current, previousValue: null, changePercent: null };
  if (previous === 0) return { value: current, previousValue: previous, changePercent: null };
  const changePercent = ((current - previous) / previous) * 100;
  return { value: current, previousValue: previous, changePercent };
}

function toMinutes(time: string): number {
  const [h, m] = time.split(":").map(Number);
  return (h ?? 0) * 60 + (m ?? 0);
}

/** Total open minutes across all slots of one operating day (0 if closed, 1440 if 24-hour). */
export function operatingMinutesForDay(day: Pick<OperatingDay, "isClosed" | "is24Hours" | "slots">): number {
  if (day.isClosed) return 0;
  if (day.is24Hours) return 24 * 60;
  return day.slots.reduce((sum, slot) => {
    const start = toMinutes(slot.startTime);
    let end = toMinutes(slot.endTime);
    if (end <= start) end += 24 * 60;
    return sum + (end - start);
  }, 0);
}

export function bookingDurationMinutes(startTime: string, endTime: string): number {
  const ms = new Date(endTime).getTime() - new Date(startTime).getTime();
  return Math.max(0, ms / 60000);
}

export function computeUtilizationPercent(bookedMinutes: number, availableMinutes: number): number {
  if (availableMinutes <= 0) return 0;
  return Math.min(100, Math.round((bookedMinutes / availableMinutes) * 100));
}

/** Every calendar date in [from, to), inclusive of from's date, exclusive of to's date. */
function datesInRange(period: DateRange): Date[] {
  const dates: Date[] = [];
  let cursor = startOfDay(new Date(period.from));
  const end = startOfDay(new Date(period.to));
  while (cursor < end) {
    dates.push(cursor);
    cursor = addDays(cursor, 1);
  }
  return dates;
}

export interface UtilizationBooking {
  playingAreaId: string;
  startTime: string;
  endTime: string;
  status: string;
}

/**
 * Utilization uses the facility's own operating schedule (not per-court
 * overrides — courts without a custom schedule already inherit it, and a v1
 * facility-wide business overview doesn't need per-court minute precision).
 * Cancelled bookings are excluded from booked time by construction — callers
 * must pass only non-cancelled bookings in.
 */
export function computeUtilization(input: {
  playingAreas: { id: string; name: string; facilitySportId: string }[];
  facilitySports: { id: string; sportId: string }[];
  sports: { id: string; name: string }[];
  facilityOperatingDays: OperatingDay[];
  bookings: UtilizationBooking[];
  period: DateRange;
}): UtilizationSummary {
  const availableMinutesPerCourt = datesInRange(input.period).reduce((sum, date) => {
    const dow = date.getDay() as OperatingDay["dayOfWeek"];
    const day = input.facilityOperatingDays.find((d) => d.dayOfWeek === dow);
    return sum + (day ? operatingMinutesForDay(day) : 0);
  }, 0);

  const bookedMinutesByArea = new Map<string, number>();
  for (const booking of input.bookings) {
    if (booking.status === "cancelled") continue;
    const minutes = bookingDurationMinutes(booking.startTime, booking.endTime);
    bookedMinutesByArea.set(booking.playingAreaId, (bookedMinutesByArea.get(booking.playingAreaId) ?? 0) + minutes);
  }

  const totalAvailable = availableMinutesPerCourt * input.playingAreas.length;
  const totalBooked = [...bookedMinutesByArea.values()].reduce((a, b) => a + b, 0);
  const overallPercent = computeUtilizationPercent(totalBooked, totalAvailable);

  const bySport: SportUtilizationEntry[] = input.facilitySports.map((fs) => {
    const sport = input.sports.find((s) => s.id === fs.sportId);
    const areasForSport = input.playingAreas.filter((a) => a.facilitySportId === fs.id);
    const courts: CourtUtilizationEntry[] = areasForSport.map((area) => ({
      playingAreaId: area.id,
      playingAreaName: area.name,
      utilizationPercent: computeUtilizationPercent(bookedMinutesByArea.get(area.id) ?? 0, availableMinutesPerCourt),
    }));
    const sportAvailable = availableMinutesPerCourt * areasForSport.length;
    const sportBooked = areasForSport.reduce((sum, a) => sum + (bookedMinutesByArea.get(a.id) ?? 0), 0);
    return {
      facilitySportId: fs.id,
      sportName: sport?.name ?? "Sport",
      utilizationPercent: computeUtilizationPercent(sportBooked, sportAvailable),
      courts,
    };
  });

  return { overallPercent, bySport };
}

/**
 * A membership session occupies its court once, for its full duration,
 * exactly when at least one member or guest has actually confirmed a slot
 * in it — allocation alone (no confirmed bookings) is not usage. The RPC
 * this feeds from (get_membership_utilization_sessions) already filters to
 * "has at least one CONFIRMED slot booking", so every row here counts.
 */
export function toUtilizationBookings(
  sessions: { courtId: string; sessionDate: string; startTime: string; endTime: string }[],
): UtilizationBooking[] {
  return sessions.map((s) => ({
    playingAreaId: s.courtId,
    startTime: `${s.sessionDate}T${s.startTime}`,
    endTime: `${s.sessionDate}T${s.endTime}`,
    status: "confirmed",
  }));
}

export function summarizeMemberships(
  memberships: { status: string; end_date: string; created_at: string }[],
  now: Date,
): MembershipSummary {
  const soon = addDays(startOfDay(now), 7);
  const monthStart = new Date(now.getFullYear(), now.getMonth(), 1);

  let active = 0;
  let expiringSoon = 0;
  let expired = 0;
  let newThisMonth = 0;

  for (const m of memberships) {
    const endDate = new Date(m.end_date);
    if (m.status === "active") {
      active++;
      if (endDate <= soon) expiringSoon++;
    }
    if (m.status === "expired") expired++;
    if (new Date(m.created_at) >= monthStart) newThisMonth++;
  }

  return { active, expiringSoon, expired, newThisMonth };
}

export function summarizePayments(payments: { status: string; amount_inr: number }[]): PaymentSummary {
  let collectedInr = 0;
  let pendingInr = 0;
  let refundsInr = 0;
  for (const p of payments) {
    if (p.status === "paid") collectedInr += p.amount_inr;
    else if (p.status === "created") pendingInr += p.amount_inr;
    else if (p.status === "refunded") refundsInr += p.amount_inr;
  }
  return { collectedInr, pendingInr, refundsInr };
}

function formatSlotTime(time: string): string {
  const [h, m] = time.split(":").map(Number);
  const hour = h ?? 0;
  const hour12 = hour % 12 === 0 ? 12 : hour % 12;
  const meridiem = hour < 12 ? "AM" : "PM";
  return `${String(hour12).padStart(2, "0")}:${String(m ?? 0).padStart(2, "0")} ${meridiem}`;
}

/**
 * One row per (playing area × operating slot) for today, marked BOOKED if
 * any non-cancelled booking overlaps that slot's window. Real, derived
 * entirely from actual operating hours + actual bookings — deliberately not
 * hour-by-hour granular, which would need booking-availability logic this
 * task explicitly excludes (that belongs to the future Bookings module).
 */
export function buildTodaysSchedule(input: {
  playingAreas: { id: string; name: string; facilitySportId: string }[];
  facilitySports: { id: string; sportId: string }[];
  sports: { id: string; name: string }[];
  facilityOperatingDays: OperatingDay[];
  bookings: { playingAreaId: string; startTime: string; endTime: string; status: string }[];
  now: Date;
}): import("@/features/dashboard/types").ScheduleEntry[] {
  const todayDow = input.now.getDay() as OperatingDay["dayOfWeek"];
  const todayDay = input.facilityOperatingDays.find((d) => d.dayOfWeek === todayDow);
  if (!todayDay || todayDay.isClosed || todayDay.slots.length === 0) return [];

  const activeBookings = input.bookings.filter((b) => b.status !== "cancelled");

  const entries: import("@/features/dashboard/types").ScheduleEntry[] = [];
  for (const area of input.playingAreas) {
    const facilitySport = input.facilitySports.find((fs) => fs.id === area.facilitySportId);
    const sport = input.sports.find((s) => s.id === facilitySport?.sportId);
    for (const slot of todayDay.slots) {
      const slotStart = toMinutes(slot.startTime);
      let slotEnd = toMinutes(slot.endTime);
      if (slotEnd <= slotStart) slotEnd += 24 * 60;

      const isBooked = activeBookings.some((b) => {
        if (b.playingAreaId !== area.id) return false;
        const bookingDate = new Date(b.startTime);
        if (bookingDate.getDay() !== todayDow) return false;
        const bStart = bookingDate.getHours() * 60 + bookingDate.getMinutes();
        const bEndDate = new Date(b.endTime);
        const bEnd = bEndDate.getHours() * 60 + bEndDate.getMinutes();
        return bStart < slotEnd && slotStart < (bEnd <= bStart ? bEnd + 24 * 60 : bEnd);
      });

      entries.push({
        time: formatSlotTime(slot.startTime),
        sportName: sport?.name ?? "Sport",
        playingAreaName: area.name,
        status: isBooked ? "BOOKED" : "AVAILABLE",
      });
    }
  }

  return entries.sort((a, b) => a.time.localeCompare(b.time));
}

export function buildAttentionItems(input: {
  membershipsExpiringSoon: number;
  paymentsPendingInr: number;
}): AttentionItem[] {
  const items: AttentionItem[] = [];
  if (input.membershipsExpiringSoon > 0) {
    items.push({
      id: "memberships-expiring",
      message: `${input.membershipsExpiringSoon} membership${input.membershipsExpiringSoon === 1 ? "" : "s"} expiring soon.`,
      actionLabel: "View Members",
      actionHref: "/members",
    });
  }
  if (input.paymentsPendingInr > 0) {
    items.push({
      id: "payments-pending",
      message: `₹${input.paymentsPendingInr.toLocaleString("en-IN")} in payments pending.`,
    });
  }
  return items;
}