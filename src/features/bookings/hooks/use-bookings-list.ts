"use client";

import { keepPreviousData, useQuery } from "@tanstack/react-query";
import { createClient } from "@/lib/supabase/client";
import { getBookingService } from "@/services/bookings";
import { getCoachingService } from "@/services/coaching";
import { getMembershipService } from "@/services/memberships";
import { addDays, startOfDay } from "@/features/bookings/calendar-events";
import { enrollmentToRow, membershipToRow, parseLocalDate, type ProgramSchedule } from "@/features/bookings/list-sources";
import { bookingReference, type BookingRow } from "@/features/bookings/list-utils";

/** How far past the range to look for coaching sessions, so a program that starts in range still shows its pattern. */
const SESSION_LOOKAHEAD_DAYS = 90;

/**
 * Everything the bookings table lists for [from, to] (inclusive ISO dates):
 *
 *  - court bookings by members and guests that start in the range (cancelled
 *    ones too — the table shows them with a badge);
 *  - memberships that start in the range, with how many months they cover and
 *    the total for that period;
 *  - coaching enrolments that start in the range, with sessions, hours, the
 *    weekday / weekend pattern and the fee.
 *
 * Memberships and coaching are best-effort: someone without access to those
 * modules still gets their bookings. The previous range stays on screen while
 * a new one loads.
 */
export function useBookingsList(facilityId: string | null, from: string, to: string, courts: { id: string; name: string }[]) {
  const courtKey = courts.map((c) => c.id).join(",");
  return useQuery({
    queryKey: ["booking-list", facilityId, from, to, courtKey],
    enabled: Boolean(facilityId),
    placeholderData: keepPreviousData,
    staleTime: 15_000,
    refetchOnMount: "always",
    queryFn: async (): Promise<BookingRow[]> => {
      const fid = facilityId!;
      const start = startOfDay(parseLocalDate(from));
      const end = addDays(startOfDay(parseLocalDate(to)), 1);
      const inRange = (isoDate: string) => isoDate.slice(0, 10) >= from && isoDate.slice(0, 10) <= to;

      const coaching = getCoachingService();
      const [bookings, memberships, enrollments, programs, sessions] = await Promise.all([
        getBookingService().getBookingsForFacility(fid, start, end),
        getMembershipService()
          .listMemberships(fid, { page: 1, perPage: 1000, sort: "oldest" })
          .then((r) => r.rows)
          .catch(() => []),
        coaching
          .listEnrollments({ facilityId: fid, limit: 500 })
          .then((r) => r.enrollments)
          .catch(() => []),
        coaching
          .listPrograms({ facilityId: fid, limit: 200 })
          .then((r) => r.programs)
          .catch(() => []),
        coaching
          .listSessions({
            facilityId: fid,
            filters: { from: start.toISOString(), to: addDays(end, SESSION_LOOKAHEAD_DAYS).toISOString() },
            limit: 500,
          })
          .then((r) => r.sessions)
          .catch(() => []),
      ]);

      // A booking made for an existing member only carries a member id; the name and phone are on the members table.
      const memberIds = [...new Set(bookings.filter((b) => b.memberId).map((b) => b.memberId as string))];
      const people = new Map<string, { name: string; phone: string | null }>();
      if (memberIds.length > 0) {
        const { data } = await createClient().from("members").select("id, full_name, phone").in("id", memberIds);
        for (const m of data ?? []) people.set(m.id, { name: m.full_name, phone: m.phone });
      }

      const bookingRows: BookingRow[] = bookings.map((b) => {
        // Every court booking is a Guest booking here, even one made for an existing member.
        const kind = "GUEST";
        const person = b.memberId ? people.get(b.memberId) : undefined;
        const startAt = new Date(b.startTime);
        const endAt = new Date(b.endTime);
        const minutes = Math.round((endAt.getTime() - startAt.getTime()) / 60000);
        return {
          id: b.id,
          booking: b,
          kind,
          customerName: b.guestName ?? person?.name ?? "Guest",
          customerPhone: b.guestPhone ?? person?.phone ?? null,
          courtId: b.courtId,
          courtIds: [b.courtId],
          courtLabel: null,
          start: startAt,
          end: endAt,
          timeLabel: null,
          durationMin: minutes,
          durationLabel: minutes < 60 ? `${minutes} Min` : `${minutes / 60} ${minutes === 60 ? "Hour" : "Hours"}`,
          durationSub: null,
          amountMinor: b.amountMinor,
          amountSub: null,
          // Paid, and not since cancelled: only that is money in hand.
          collectedMinor: b.status !== "cancelled" && b.paymentStatus === "PAID" ? (b.amountMinor ?? 0) : 0,
          currency: b.currency,
          status: b.status,
          statusLabel: b.status.charAt(0).toUpperCase() + b.status.slice(1),
          reference: bookingReference(b.id, kind),
          href: null,
        } satisfies BookingRow;
      });

      // Each program's own schedule: which days it runs, on which courts, and how long a session is.
      const schedules = new Map<string, ProgramSchedule>();
      for (const p of programs) schedules.set(p.id, { sessionMinutes: p.defaultDurationMinutes, days: [], courtIds: [] });
      for (const s of sessions) {
        if (s.status === "CANCELLED") continue;
        const sched = schedules.get(s.programId) ?? { sessionMinutes: null, days: [], courtIds: [] };
        const day = new Date(s.startAt).getDay();
        if (!sched.days.includes(day)) sched.days.push(day);
        if (!sched.courtIds.includes(s.courtId)) sched.courtIds.push(s.courtId);
        schedules.set(s.programId, sched);
      }

      const membershipRows = memberships.filter((m) => inRange(m.startDate)).map((m) => membershipToRow(m, courts));
      const coachingRows = enrollments.filter((e) => inRange(e.startDate)).map((e) => enrollmentToRow(e, schedules.get(e.programId)));

      return [...bookingRows, ...membershipRows, ...coachingRows];
    },
  });
}
