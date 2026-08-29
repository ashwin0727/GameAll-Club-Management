import type { OperatingDay } from "@/features/operating-hours/types";
import type {
  AttentionItem,
  CourtUtilizationEntry,
  DateRange,
  DateRangePreset,
  KpiValue,
  MembershipSummary,
  PaymentSummary,
  ScheduleBlock,
  ScheduleBlockType,
  ScheduleCourtRow,
  ScheduleTimeline,
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

function dayKey(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

/**
 * One bucket per calendar date in the period, summing paid revenue whose
 * `created_at` lands on that day (local). Derived from payments already
 * fetched for the KPIs — no extra query, no fabricated points.
 */
export function buildRevenueTrend(
  payments: { status: string; amount_inr: number; created_at: string }[],
  period: DateRange,
): { date: string; amountInr: number }[] {
  const byDay = new Map<string, number>();
  for (const p of payments) {
    if (p.status !== "paid") continue;
    const key = dayKey(startOfDay(new Date(p.created_at)));
    byDay.set(key, (byDay.get(key) ?? 0) + p.amount_inr);
  }
  return datesInRange(period).map((d) => {
    const key = dayKey(d);
    return { date: key, amountInr: byDay.get(key) ?? 0 };
  });
}

function formatClock(minuteOfDay: number): string {
  const wrapped = ((minuteOfDay % (24 * 60)) + 24 * 60) % (24 * 60);
  const hour = Math.floor(wrapped / 60);
  const minute = wrapped % 60;
  const hour12 = hour % 12 === 0 ? 12 : hour % 12;
  const meridiem = hour < 12 ? "AM" : "PM";
  return `${hour12}:${String(minute).padStart(2, "0")} ${meridiem}`;
}

/** "5:00 – 6:00 PM" when both ends share a meridiem, else "11:30 AM – 1:00 PM". */
function formatTimeRange(startMinute: number, endMinute: number): string {
  const startHour = Math.floor((((startMinute % (24 * 60)) + 24 * 60) % (24 * 60)) / 60);
  const endHour = Math.floor((((endMinute % (24 * 60)) + 24 * 60) % (24 * 60)) / 60);
  const sameMeridiem = startHour < 12 === endHour < 12;
  const start = sameMeridiem ? formatClock(startMinute).replace(/ (AM|PM)$/, "") : formatClock(startMinute);
  return `${start} – ${formatClock(endMinute)}`;
}

export interface TimelineBooking {
  id: string;
  playingAreaId: string;
  /** ISO instant. */
  startTime: string;
  endTime: string;
  status: string;
  type: ScheduleBlockType;
  label: string;
}

/** Greedy lane assignment so overlapping blocks in one court sit side by side instead of hiding each other. */
function packLanes(blocks: { startMinute: number; endMinute: number }[]): number[] {
  const laneEnds: number[] = [];
  const lanes: number[] = [];
  const order = blocks.map((_, i) => i).sort((a, b) => blocks[a]!.startMinute - blocks[b]!.startMinute);
  for (const i of order) {
    const b = blocks[i]!;
    let lane = laneEnds.findIndex((end) => end <= b.startMinute);
    if (lane === -1) {
      lane = laneEnds.length;
      laneEnds.push(b.endMinute);
    } else {
      laneEnds[lane] = b.endMinute;
    }
    lanes[i] = lane;
  }
  return lanes;
}

const DEFAULT_SCHEDULE_START_HOUR = 6;
const DEFAULT_SCHEDULE_END_HOUR = 22;

/**
 * A positioned, court-by-court view of today's activity — one row per playing
 * area (already sport-filtered by the caller), each block a real non-cancelled
 * booking or a confirmed membership session, positioned by its actual local
 * start/end.
 *
 * The hour axis comes from today's operating hours when configured, but the
 * grid ALWAYS renders: with no operating hours it falls back to the span of
 * today's bookings/sessions, or a default 6 AM–10 PM day when there is nothing
 * at all. Bookings that fall outside operating hours extend the axis rather
 * than being hidden.
 */
export function buildScheduleTimeline(input: {
  playingAreas: { id: string; name: string; facilitySportId: string }[];
  facilitySports: { id: string; sportId: string }[];
  sports: { id: string; name: string }[];
  facilityOperatingDays: OperatingDay[];
  bookings: TimelineBooking[];
  now: Date;
}): ScheduleTimeline {
  if (input.playingAreas.length === 0) {
    return { startHour: 0, endHour: 0, courts: [] };
  }

  const todayDow = input.now.getDay() as OperatingDay["dayOfWeek"];
  const todayDay = input.facilityOperatingDays.find((d) => d.dayOfWeek === todayDow);

  const areaIds = new Set(input.playingAreas.map((a) => a.id));
  const activeBookings = input.bookings.filter((b) => b.status !== "cancelled" && areaIds.has(b.playingAreaId));

  // Each of today's blocks as absolute local minute-of-day (end may exceed 1440).
  const blockSpans = activeBookings
    .map((b) => {
      const start = new Date(b.startTime);
      const end = new Date(b.endTime);
      if (start.getDay() !== todayDow) return null;
      const startMin = start.getHours() * 60 + start.getMinutes();
      let endMin = end.getHours() * 60 + end.getMinutes();
      if (endMin <= startMin) endMin += 24 * 60;
      return { id: b.id, playingAreaId: b.playingAreaId, label: b.label, type: b.type, startMin, endMin };
    })
    .filter((b): b is NonNullable<typeof b> => b !== null);

  // Base window: operating hours if present, else the bookings' own span, else a default day.
  let windowStart: number;
  let windowEnd: number;
  const hasOperatingHours = todayDay != null && !todayDay.isClosed && (todayDay.is24Hours || todayDay.slots.length > 0);
  if (hasOperatingHours && todayDay!.is24Hours) {
    windowStart = 0;
    windowEnd = 24 * 60;
  } else if (hasOperatingHours) {
    windowStart = 24 * 60;
    windowEnd = 0;
    for (const slot of todayDay!.slots) {
      const start = toMinutes(slot.startTime);
      let end = toMinutes(slot.endTime);
      if (end <= start) end += 24 * 60;
      windowStart = Math.min(windowStart, start);
      windowEnd = Math.max(windowEnd, end);
    }
  } else if (blockSpans.length > 0) {
    windowStart = Math.min(...blockSpans.map((b) => b.startMin));
    windowEnd = Math.max(...blockSpans.map((b) => b.endMin));
  } else {
    windowStart = DEFAULT_SCHEDULE_START_HOUR * 60;
    windowEnd = DEFAULT_SCHEDULE_END_HOUR * 60;
  }

  // Extend the axis so a booking outside operating hours is still visible.
  for (const b of blockSpans) {
    windowStart = Math.min(windowStart, b.startMin);
    windowEnd = Math.max(windowEnd, b.endMin);
  }

  let startHour = Math.floor(windowStart / 60);
  let endHour = Math.ceil(windowEnd / 60);
  const MIN_SPAN_HOURS = 6;
  if (endHour - startHour < MIN_SPAN_HOURS) {
    const pad = MIN_SPAN_HOURS - (endHour - startHour);
    startHour = Math.max(0, startHour - Math.floor(pad / 2));
    endHour = startHour + MIN_SPAN_HOURS;
  }
  endHour = Math.min(endHour, 30); // allow a little past midnight, never runaway
  const winStartMin = startHour * 60;
  const winEndMin = endHour * 60;

  const courts: ScheduleCourtRow[] = input.playingAreas
    .map((area) => {
      const facilitySport = input.facilitySports.find((fs) => fs.id === area.facilitySportId);
      const sport = input.sports.find((s) => s.id === facilitySport?.sportId);

      const raw = blockSpans
        .filter((b) => b.playingAreaId === area.id)
        .map((b) => {
          const timeLabel = formatTimeRange(b.startMin, b.endMin);
          const startMinute = Math.max(b.startMin, winStartMin);
          const endMinute = Math.min(b.endMin, winEndMin);
          if (endMinute <= startMinute) return null;
          return { id: b.id, label: b.label, type: b.type, startMinute, endMinute, timeLabel };
        })
        .filter((b): b is NonNullable<typeof b> => b !== null)
        .sort((a, b) => a.startMinute - b.startMinute);

      const lanes = packLanes(raw);
      const blocks: ScheduleBlock[] = raw.map((b, i) => ({ ...b, lane: lanes[i] ?? 0 }));

      return {
        courtId: area.id,
        courtName: area.name,
        sportName: sport?.name ?? "Sport",
        laneCount: Math.max(1, blocks.reduce((max, b) => Math.max(max, b.lane + 1), 0)),
        blocks,
      };
    })
    .sort((a, b) => a.courtName.localeCompare(b.courtName));

  return { startHour, endHour, courts };
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
/** When `sportScope` is given, a payment counts only if it's for a booking on the sport's
 *  courts or a membership whose member is enrolled in a batch of that sport. */
export function sumPaidRevenueInr(
  payments: { status: string; amount_inr: number; booking_id?: string | null; membership_id?: string | null }[],
  sportScope: { bookingIds: Set<string>; membershipIds: Set<string> } | null,
): number {
  let total = 0;
  for (const p of payments) {
    if (p.status !== "paid") continue;
    if (sportScope) {
      const inScope =
        (p.booking_id != null && sportScope.bookingIds.has(p.booking_id)) ||
        (p.membership_id != null && sportScope.membershipIds.has(p.membership_id));
      if (!inScope) continue;
    }
    total += p.amount_inr;
  }
  return total;
}

/** Memberships active as of now. `restrictToIds` (batch-derived) narrows to a single sport. */
export function countActiveMemberships(
  memberships: { id: string; status: string }[],
  restrictToIds: Set<string> | null,
): number {
  return memberships.filter((m) => m.status === "active" && (!restrictToIds || restrictToIds.has(m.id))).length;
}

/** Guest bookings that are both booked (not cancelled) and paid. Caller pre-filters by court and period. */
export function countPaidGuestBookings(
  bookings: { customerType: string; paymentStatus: string; status: string }[],
): number {
  return bookings.filter(
    (b) => b.customerType === "GUEST" && b.paymentStatus === "PAID" && b.status !== "cancelled",
  ).length;
}

const MONTH_NAMES = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

/**
 * Revenue for one calendar month plus the day-by-day series to plot it.
 * `payments` must cover at least [prevMonthStart, monthEnd). The series is
 * always one point per day of the month (zero-filled) so the chart renders
 * even for a month with no revenue.
 */
type RevenuePayment = {
  status: string;
  amount_inr: number;
  created_at: string;
  booking_id?: string | null;
  membership_id?: string | null;
};

export function buildRevenueOverview(
  payments: RevenuePayment[],
  now: Date,
  monthOffset: number,
): import("@/features/dashboard/types").RevenueOverview {
  const monthStartD = new Date(now.getFullYear(), now.getMonth() - monthOffset, 1);
  const monthEndD = new Date(now.getFullYear(), now.getMonth() - monthOffset + 1, 1);
  const prevMonthStartD = new Date(now.getFullYear(), now.getMonth() - monthOffset - 1, 1);

  const paidInRange = (from: Date, to: Date) =>
    payments.filter((p) => {
      if (p.status !== "paid") return false;
      const d = new Date(p.created_at);
      return d >= from && d < to;
    });

  const monthPaid = paidInRange(monthStartD, monthEndD);
  const totalInr = monthPaid.reduce((sum, p) => sum + p.amount_inr, 0);
  const prevTotal = paidInRange(prevMonthStartD, monthStartD).reduce((sum, p) => sum + p.amount_inr, 0);
  const changePercent = prevTotal === 0 ? null : ((totalInr - prevTotal) / prevTotal) * 100;

  const points = buildRevenueTrend(payments, {
    from: monthStartD.toISOString(),
    to: monthEndD.toISOString(),
  });

  // Breakdown: bookings vs memberships come from the payment's linked entity;
  // coaching has no payment source yet; "other" catches anything uncategorised.
  let bookingCount = 0;
  let bookingInr = 0;
  let membershipCount = 0;
  let membershipInr = 0;
  let otherCount = 0;
  let otherInr = 0;
  for (const p of monthPaid) {
    if (p.membership_id != null) {
      membershipCount++;
      membershipInr += p.amount_inr;
    } else if (p.booking_id != null) {
      bookingCount++;
      bookingInr += p.amount_inr;
    } else {
      otherCount++;
      otherInr += p.amount_inr;
    }
  }

  return {
    monthLabel: `${MONTH_NAMES[monthStartD.getMonth()]} ${monthStartD.getFullYear()}`,
    monthStart: dayKey(monthStartD),
    totalInr,
    changePercent,
    points,
    breakdown: [
      { key: "bookings", label: "Bookings", amountInr: bookingInr, count: bookingCount, unavailable: false },
      { key: "memberships", label: "Memberships", amountInr: membershipInr, count: membershipCount, unavailable: false },
      { key: "coaching", label: "Coaching", amountInr: 0, count: null, unavailable: true },
      { key: "other", label: "Other", amountInr: otherInr, count: otherCount || null, unavailable: otherInr === 0 },
    ],
  };
}
