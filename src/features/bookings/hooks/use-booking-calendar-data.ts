"use client";

import { keepPreviousData, useQuery } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";
import { getBookingService } from "@/services/bookings";
import { getCoachingService } from "@/services/coaching";
import { getMembershipSessionService } from "@/services/membership-sessions";
import { getOperatingHoursService } from "@/services/operating-hours";
import { countActiveMemberships } from "@/features/dashboard/summary";
import {
  dataRange,
  addDays as addDaysTo,
  type CalEvent,
  type CalView,
} from "@/features/bookings/calendar-events";
import type { Booking } from "@/features/bookings/types";
import type { PlayingArea } from "@/features/courts-setup/types";
import type { OperatingDay, OperatingSchedule } from "@/features/operating-hours/types";

function localDateStr(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

/** A booking made for an existing member only carries member_id; the person's name is on the members table. */
export async function loadMemberNames(ids: string[]): Promise<Map<string, string>> {
  const names = new Map<string, string>();
  if (ids.length === 0) return names;
  const { data } = await createClient().from("members").select("id, full_name").in("id", ids);
  for (const m of data ?? []) names.set(m.id, m.full_name);
  return names;
}

export function bookingToEvent(b: Booking, memberNames: Map<string, string>): CalEvent {
  return {
    id: b.id,
    courtId: b.courtId,
    start: new Date(b.startTime),
    end: new Date(b.endTime),
    // Every court booking is a guest booking on the calendar — an existing member booking a court is still one.
    kind: "GUEST",
    title: b.guestName ?? (b.memberId && memberNames.get(b.memberId)) ?? "Guest booking",
    subtitle: "Guest",
    status: b.status,
    paymentStatus: b.paymentStatus,
    booking: b,
  };
}

/**
 * Everything drawn on the calendar for [from, to): bookings, membership-session
 * windows, coaching sessions and active maintenance blocks, merged into one
 * list. Each secondary source is best-effort — a person without Coaching access
 * still gets their bookings.
 */
export async function fetchCalendarEvents(fid: string, from: Date, to: Date): Promise<CalEvent[]> {
    const supabase = createClient();
    // Membership windows are generated per date, so every date on screen needs its own lookup.
    const sessionDates: string[] = [];
    for (let d = from; d < to; d = addDaysTo(d, 1)) sessionDates.push(localDateStr(d));

    const [bookings, coaching, blocks, sessionGroups] = await Promise.all([
      getBookingService().getBookingsForFacility(fid, from, to),
      getCoachingService()
        .listSessions({ facilityId: fid, filters: { from: from.toISOString(), to: to.toISOString() }, limit: 500 })
        .then((r) => r.sessions)
        .catch(() => []),
      supabase
        .from("maintenance_blocks")
        .select("id, court_id, ticket_id, start_time, end_time")
        .eq("facility_id", fid)
        .eq("status", "ACTIVE")
        .lt("start_time", to.toISOString())
        .gt("end_time", from.toISOString())
        .then((r) => r.data ?? [], () => []),
      Promise.all(
        sessionDates.map((d) =>
          getMembershipSessionService()
            .listSessionsForDate(fid, d)
            .catch(() => []),
        ),
      ),
    ]);

    const liveBookings = bookings.filter((b) => b.status !== "cancelled");
    const memberNames = await loadMemberNames([
      ...new Set(liveBookings.filter((b) => b.memberId).map((b) => b.memberId as string)),
    ]);

    const events: CalEvent[] = liveBookings.map((b) => bookingToEvent(b, memberNames));

    for (const slot of sessionGroups.flat()) {
      events.push({
        id: `session-${slot.batchId}-${slot.sessionDate}-${slot.courtId}`,
        courtId: slot.courtId,
        start: new Date(`${slot.sessionDate}T${slot.startTime}`),
        end: new Date(`${slot.sessionDate}T${slot.endTime}`),
        kind: "SESSION",
        title: slot.batchName,
        subtitle: "Membership session",
        membershipSlot: slot,
      });
    }

    for (const s of coaching) {
      if (s.status === "CANCELLED") continue;
      events.push({
        id: `coaching-${s.id}`,
        courtId: s.courtId,
        start: new Date(s.startAt),
        end: new Date(s.endAt),
        kind: "COACHING",
        title: s.programName,
        subtitle: s.coachName,
        href: `/coaching/sessions/${s.id}`,
      });
    }

    // What the work is (a block only knows its ticket), so the calendar can say "Net repair" rather than just "Maintenance".
    const ticketTitles = new Map<string, string>();
    const ticketIds = [...new Set(blocks.map((m) => m.ticket_id))];
    if (ticketIds.length > 0) {
      const { data } = await supabase.from("maintenance_tickets").select("id, title").in("id", ticketIds);
      for (const t of data ?? []) ticketTitles.set(t.id, t.title);
    }

    for (const m of blocks) {
      events.push({
        id: `maintenance-${m.id}`,
        courtId: m.court_id,
        start: new Date(m.start_time),
        end: new Date(m.end_time),
        kind: "MAINTENANCE",
        title: ticketTitles.get(m.ticket_id) ?? "Maintenance",
        subtitle: "Court blocked",
        href: `/maintenance/tickets/${m.ticket_id}`,
      });
    }

    return events;
}

/**
 * The calendar's events for its visible period. The previous period stays on
 * screen while the next one loads, so paging never blanks the grid.
 */
export function useBookingCalendarData(facilityId: string | null, view: CalView, anchor: Date, enabled: boolean) {
  const { from, to } = dataRange(view, anchor);
  return useQuery({
    queryKey: ["booking-calendar", facilityId, view, from.getTime(), to.getTime()],
    enabled: enabled && Boolean(facilityId),
    placeholderData: keepPreviousData,
    staleTime: 15_000,
    // Coming back from creating a coaching session (or anything else elsewhere)
    // must show it, so a remount always refetches instead of trusting the cache.
    refetchOnMount: "always",
    queryFn: () => fetchCalendarEvents(facilityId!, from, to),
  });
}

/** The same events for any [from, to) — the bookings list uses it to work out utilization for its own date range. */
export function useCalendarEventsForRange(facilityId: string | null, from: Date, to: Date, enabled = true) {
  return useQuery({
    queryKey: ["booking-calendar-range", facilityId, from.getTime(), to.getTime()],
    enabled: enabled && Boolean(facilityId),
    placeholderData: keepPreviousData,
    staleTime: 15_000,
    refetchOnMount: "always",
    queryFn: () => fetchCalendarEvents(facilityId!, from, to),
  });
}

/** Per-court operating schedule (court override, else the facility's). Loaded once — it changes rarely. */
export function useCourtSchedules(facilityId: string | null, areas: PlayingArea[]) {
  const ids = areas.map((a) => a.id).join(",");
  return useQuery({
    queryKey: ["booking-court-schedules", facilityId, ids],
    enabled: Boolean(facilityId) && areas.length > 0,
    staleTime: 5 * 60_000,
    queryFn: async () => {
      const service = getOperatingHoursService();
      const facilitySchedule = await service.getFacilitySchedule(facilityId!);
      const overrides = await Promise.all(areas.map(async (a) => [a.id, await service.getPlayingAreaSchedule(a.id)] as const));
      const byCourt = new Map<string, OperatingSchedule | null>();
      for (const [courtId, override] of overrides) byCourt.set(courtId, override ?? facilitySchedule ?? null);
      return byCourt;
    },
  });
}

export function dayForCourt(
  schedules: Map<string, OperatingSchedule | null> | undefined,
  courtId: string,
  date: Date,
): OperatingDay | null {
  return schedules?.get(courtId)?.days.find((d) => d.dayOfWeek === date.getDay()) ?? null;
}

/** Active members — facility-wide, so it doesn't follow the date or filters. */
export function useBookingFacilityStats(facilityId: string | null) {
  return useQuery({
    queryKey: ["booking-facility-stats", facilityId],
    enabled: Boolean(facilityId),
    staleTime: 30_000,
    queryFn: async () => {
      const memberships = await createClient().from("memberships").select("id, status").eq("facility_id", facilityId!);
      return { activeMembers: countActiveMemberships(memberships.data ?? [], null) };
    },
  });
}

/** Money collected (paid payments) in [from, to), in rupees — the Court View's revenue card for its visible period. */
export function usePeriodRevenue(facilityId: string | null, from: Date, to: Date) {
  return useQuery({
    queryKey: ["booking-period-revenue", facilityId, from.getTime(), to.getTime()],
    enabled: Boolean(facilityId),
    placeholderData: keepPreviousData,
    staleTime: 30_000,
    queryFn: async () => {
      const { data } = await createClient()
        .from("payments")
        .select("status, amount_inr")
        .eq("facility_id", facilityId!)
        .gte("created_at", from.toISOString())
        .lt("created_at", to.toISOString());
      return (data ?? []).reduce((sum, p) => (p.status === "paid" ? sum + p.amount_inr : sum), 0);
    },
  });
}
