"use client";

import type { SupabaseClient } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";
import { getSportsService } from "@/services/sports";
import { getPlayingAreasService } from "@/services/playing-areas";
import { getOperatingHoursService } from "@/services/operating-hours";
import {
  buildAttentionItems,
  bookingDurationMinutes,
  buildRevenueOverview,
  buildRevenueOverviewFromTotals,
  buildScheduleTimeline,
  computeKpiValue,
  computeUtilization,
  countActiveMemberships,
  countPaidGuestBookings,
  resolveDateRange,
  sumPaidRevenueInr,
  summarizeMemberships,
  summarizePayments,
  type RevenueTotals,
  type TimelineBooking,
} from "@/features/dashboard/summary";
import type { DashboardSummary, MembershipSummary, PaymentSummary, RevenueOverview } from "@/features/dashboard/types";
import type { Facility } from "@/features/onboarding/types";
import type { DashboardService, DashboardSummaryParams } from "@/services/dashboard/dashboard.service";
import { mapSupabaseError } from "@/services/shared/service-error";
import type { Database } from "@/types/database.types";

function localDateKey(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

type BookingRow = {
  id: string;
  court_id: string;
  start_time: string;
  end_time: string;
  status: string;
  customer_type: "MEMBER" | "GUEST";
  guest_name: string | null;
  member_id: string | null;
  payment_status: "PENDING" | "PAID" | "REFUNDED";
};
type MembershipRow = { id: string; status: string; end_date: string; created_at: string };
type PaymentRow = {
  status: string;
  amount_inr: number;
  created_at: string;
  /** When the money actually arrived; null on older rows, which fall back to created_at. */
  paid_at?: string | null;
  booking_id: string | null;
  membership_id: string | null;
};

type TotalsArgs = {
  facilityId: string;
  current: { from: string; to: string };
  previous: { from: string; to: string } | null;
  earliestFrom: string;
  courtIds: string[];
  sportIds: string[] | null;
  soon: Date;
  monthStart: Date;
  now: Date;
};

type DashboardTotals = {
  payments: PaymentSummary;
  previousCollectedInr: number;
  guestBookings: number;
  previousGuestBookings: number;
  activeMembershipsInScope: number;
  memberships: MembershipSummary;
};

export class SupabaseDashboardService implements DashboardService {
  private readonly supabase: SupabaseClient<Database>;

  constructor(client?: SupabaseClient<Database>) {
    this.supabase = client ?? createClient();
  }

  /** The payments that belong to the given sports (see the call site for what "belongs" means). */
  private async paymentsInSports<T extends { booking_id?: string | null; membership_id?: string | null; coaching_enrollment_id?: string | null }>(
    payments: T[],
    sports: ReadonlySet<string>,
    playingAreas: { id: string; facilitySportId: string }[],
    membershipIds: ReadonlySet<string>,
  ): Promise<T[]> {
    const sb = this.supabase as unknown as SupabaseClient;
    const courtSport = new Map(playingAreas.map((a) => [a.id, a.facilitySportId]));
    const chunks = <V,>(list: V[], n = 150): V[][] => Array.from({ length: Math.ceil(list.length / n) }, (_, i) => list.slice(i * n, i * n + n));

    const bookingIds = [...new Set(payments.map((p) => p.booking_id).filter((x): x is string => Boolean(x)))];
    const enrollmentIds = [...new Set(payments.map((p) => p.coaching_enrollment_id).filter((x): x is string => Boolean(x)))];

    const bookingSport = new Map<string, string | undefined>();
    for (const ids of chunks(bookingIds)) {
      const { data, error } = await sb.from("bookings").select("id, court_id").in("id", ids);
      if (error) throw mapSupabaseError(error);
      for (const b of (data ?? []) as { id: string; court_id: string }[]) bookingSport.set(b.id, courtSport.get(b.court_id));
    }

    const enrollmentProgram = new Map<string, string>();
    for (const ids of chunks(enrollmentIds)) {
      const { data, error } = await sb.from("coaching_enrollments").select("id, program_id").in("id", ids);
      if (error) throw mapSupabaseError(error);
      for (const e of (data ?? []) as { id: string; program_id: string }[]) enrollmentProgram.set(e.id, e.program_id);
    }
    const programSport = new Map<string, string | null>();
    for (const ids of chunks([...new Set(enrollmentProgram.values())])) {
      const { data, error } = await sb.from("coaching_programs").select("id, facility_sport_id").in("id", ids);
      if (error) throw mapSupabaseError(error);
      for (const p of (data ?? []) as { id: string; facility_sport_id: string | null }[]) programSport.set(p.id, p.facility_sport_id);
    }

    return payments.filter((p) => {
      if (p.membership_id != null) return membershipIds.has(p.membership_id);
      if (p.booking_id != null) {
        const sport = bookingSport.get(p.booking_id);
        return sport !== undefined && sports.has(sport);
      }
      if (p.coaching_enrollment_id != null) {
        const sport = programSport.get(enrollmentProgram.get(p.coaching_enrollment_id) ?? "");
        return sport != null && sports.has(sport);
      }
      return false;
    });
  }

  /** The memberships enrolled in a batch of the given sports (this club's batches only). */
  private async membershipIdsInSports(facilityId: string, sports: ReadonlySet<string>): Promise<Set<string>> {
    const { data: batches, error } = await this.supabase.from("membership_batches").select("id, facility_sport_id").eq("facility_id", facilityId);
    if (error) throw mapSupabaseError(error);
    const batchIds = (batches ?? []).filter((b) => sports.has(b.facility_sport_id ?? "")).map((b) => b.id);
    const ids = new Set<string>();
    for (let i = 0; i < batchIds.length; i += 150) {
      const { data, error: err } = await this.supabase
        .from("membership_batch_members")
        .select("membership_id")
        .in("batch_id", batchIds.slice(i, i + 150));
      if (err) throw mapSupabaseError(err);
      for (const m of data ?? []) if (m.membership_id != null) ids.add(m.membership_id);
    }
    return ids;
  }

  /** Totals for the KPI cards and panels: from the database, or (migration 0165 not applied yet) added up here from the rows. */
  private async fetchTotals(a: TotalsArgs): Promise<DashboardTotals> {
    const sb = this.supabase as unknown as SupabaseClient;
    const { data, error } = await sb.rpc("dashboard_totals", {
      p_facility_id: a.facilityId,
      p_cur_from: a.current.from,
      p_cur_to: a.current.to,
      p_prev_from: a.previous?.from ?? null,
      p_prev_to: a.previous?.to ?? null,
      p_court_ids: a.courtIds,
      p_facility_sport_ids: a.sportIds,
      p_soon: a.soon.toISOString(),
      p_month_start: a.monthStart.toISOString(),
    });
    if (!error && data) {
      const d = data as {
        collectedInr: number; pendingInr: number; refundsInr: number; previousCollectedInr: number;
        guestBookings: number; previousGuestBookings: number; activeMembershipsInScope: number;
        memberships: MembershipSummary;
      };
      return {
        payments: { collectedInr: Number(d.collectedInr), pendingInr: Number(d.pendingInr), refundsInr: Number(d.refundsInr) },
        previousCollectedInr: Number(d.previousCollectedInr),
        guestBookings: Number(d.guestBookings),
        previousGuestBookings: Number(d.previousGuestBookings),
        activeMembershipsInScope: Number(d.activeMembershipsInScope),
        memberships: {
          active: Number(d.memberships.active),
          expiringSoon: Number(d.memberships.expiringSoon),
          expired: Number(d.memberships.expired),
          newThisMonth: Number(d.memberships.newThisMonth),
        },
      };
    }
    if (error && error.code !== "PGRST202" && error.code !== "42883") throw mapSupabaseError(error);
    return this.legacyTotals(a);
  }

  private async legacyTotals(a: TotalsArgs): Promise<DashboardTotals> {
    const [bookingsRes, membershipsRes, paymentsRes] = await Promise.all([
      this.supabase
        .from("bookings")
        .select("id, court_id, start_time, end_time, status, customer_type, guest_name, member_id, payment_status")
        .eq("facility_id", a.facilityId)
        .gte("start_time", a.earliestFrom)
        .lt("start_time", a.current.to),
      this.supabase.from("memberships").select("id, status, end_date, created_at").eq("facility_id", a.facilityId),
      this.supabase
        .from("payments")
        .select("status, amount_inr, created_at, booking_id, membership_id, coaching_enrollment_id")
        .eq("facility_id", a.facilityId)
        .gte("created_at", a.earliestFrom)
        .lt("created_at", a.current.to),
    ]);
    if (bookingsRes.error) throw mapSupabaseError(bookingsRes.error);
    if (membershipsRes.error) throw mapSupabaseError(membershipsRes.error);
    if (paymentsRes.error) throw mapSupabaseError(paymentsRes.error);
    const courts = new Set(a.courtIds);
    const bookingRows = ((bookingsRes.data ?? []) as BookingRow[]).filter((b) => courts.has(b.court_id));
    const membershipRows = (membershipsRes.data ?? []) as MembershipRow[];
    const sportSet = a.sportIds ? new Set(a.sportIds) : null;
    const sportMembershipIds = sportSet ? await this.membershipIdsInSports(a.facilityId, sportSet) : null;
    const sportScope = sportSet ? { bookingIds: new Set(bookingRows.map((b) => b.id)), membershipIds: sportMembershipIds ?? new Set<string>() } : null;
    const all = (paymentsRes.data ?? []) as PaymentRow[];
    const inRange = (t: string, w: { from: string; to: string }) => t >= w.from && t < w.to;
    const scoped = (list: PaymentRow[]) =>
      sportScope
        ? list.filter(
            (p) =>
              (p.booking_id != null && sportScope.bookingIds.has(p.booking_id)) ||
              (p.membership_id != null && sportScope.membershipIds.has(p.membership_id)),
          )
        : list;
    const cur = scoped(all.filter((p) => inRange(p.created_at, a.current)));
    const prev = a.previous ? scoped(all.filter((p) => inRange(p.created_at, a.previous!))) : [];
    const guests = (w: { from: string; to: string }) =>
      countPaidGuestBookings(
        bookingRows
          .filter((b) => inRange(b.start_time, w))
          .map((b) => ({ customerType: b.customer_type, paymentStatus: b.payment_status, status: b.status })),
      );
    return {
      payments: summarizePayments(cur),
      previousCollectedInr: sumPaidRevenueInr(prev, null),
      guestBookings: guests(a.current),
      previousGuestBookings: a.previous ? guests(a.previous) : 0,
      activeMembershipsInScope: countActiveMemberships(membershipRows, sportMembershipIds),
      memberships: summarizeMemberships(membershipRows, a.now),
    };
  }

  /** Booked court time per court (minutes) for the current and previous period: from the database, or added up here from the rows. */
  private async fetchBookedMinutes(a: {
    facilityId: string;
    current: { from: string; to: string };
    previous: { from: string; to: string } | null;
    courtIds: string[];
  }): Promise<{ current: Map<string, number>; previous: Map<string, number> }> {
    const sb = this.supabase as unknown as SupabaseClient;
    const dateOf = (iso: string) => localDateKey(new Date(iso));
    const { data, error } = await sb.rpc("dashboard_booked_minutes", {
      p_facility_id: a.facilityId,
      p_cur_from: a.current.from,
      p_cur_to: a.current.to,
      p_prev_from: a.previous?.from ?? null,
      p_prev_to: a.previous?.to ?? null,
      p_cur_from_date: dateOf(a.current.from),
      p_cur_to_date: dateOf(a.current.to),
      p_prev_from_date: a.previous ? dateOf(a.previous.from) : null,
      p_prev_to_date: a.previous ? dateOf(a.previous.to) : null,
      p_court_ids: a.courtIds,
    });
    if (!error) {
      const current = new Map<string, number>();
      const previous = new Map<string, number>();
      for (const r of (data ?? []) as { court_id: string; cur_minutes: number; prev_minutes: number }[]) {
        current.set(r.court_id, Number(r.cur_minutes));
        previous.set(r.court_id, Number(r.prev_minutes));
      }
      return { current, previous };
    }
    if (error.code !== "PGRST202" && error.code !== "42883") throw mapSupabaseError(error);

    // Migration 0166 not applied yet: download the period's bookings and add them up here.
    const earliest = a.previous ? a.previous.from : a.current.from;
    const [bookingsRes, sessionsRes] = await Promise.all([
      this.supabase
        .from("bookings")
        .select("court_id, start_time, end_time, status")
        .eq("facility_id", a.facilityId)
        .gte("start_time", earliest)
        .lt("start_time", a.current.to),
      this.supabase.rpc("get_membership_utilization_sessions", {
        p_facility_id: a.facilityId,
        p_from: dateOf(earliest),
        p_to: dateOf(a.current.to),
      }),
    ]);
    if (bookingsRes.error) throw mapSupabaseError(bookingsRes.error);
    if (sessionsRes.error) throw mapSupabaseError(sessionsRes.error);
    const courts = new Set(a.courtIds);
    const add = (m: Map<string, number>, court: string, mins: number) => m.set(court, (m.get(court) ?? 0) + mins);
    const inRange = (t: string, w: { from: string; to: string }) => t >= w.from && t < w.to;
    const current = new Map<string, number>();
    const previous = new Map<string, number>();
    for (const b of bookingsRes.data ?? []) {
      if (b.status === "cancelled" || !courts.has(b.court_id)) continue;
      const mins = bookingDurationMinutes(b.start_time, b.end_time);
      if (inRange(b.start_time, a.current)) add(current, b.court_id, mins);
      else if (a.previous && inRange(b.start_time, a.previous)) add(previous, b.court_id, mins);
    }
    for (const s of sessionsRes.data ?? []) {
      if (!courts.has(s.court_id)) continue;
      const mins = bookingDurationMinutes(`${s.session_date}T${s.start_time}`, `${s.session_date}T${s.end_time}`);
      if (s.session_date >= dateOf(a.current.from) && s.session_date < dateOf(a.current.to)) add(current, s.court_id, mins);
      else if (a.previous && s.session_date >= dateOf(a.previous.from) && s.session_date < dateOf(a.previous.to)) add(previous, s.court_id, mins);
    }
    return { current, previous };
  }

  /** The Revenue Overview panel (its own month filter, independent of the period): from the database, or built here from the rows. */
  private async fetchRevenueOverview(a: {
    facilityId: string;
    now: Date;
    monthOffset: number;
    sportIds: string[] | null;
    playingAreasAll: { id: string; facilitySportId: string }[];
  }): Promise<RevenueOverview> {
    const sb = this.supabase as unknown as SupabaseClient;
    const { now, monthOffset } = a;
    const monthStart = new Date(now.getFullYear(), now.getMonth() - monthOffset, 1);
    const monthEnd = new Date(now.getFullYear(), now.getMonth() - monthOffset + 1, 1);
    const prevStart = new Date(now.getFullYear(), now.getMonth() - monthOffset - 1, 1);
    let timeZone = "UTC";
    try {
      timeZone = Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC";
    } catch {
      // keep UTC
    }
    const { data, error } = await sb.rpc("dashboard_revenue_overview", {
      p_facility_id: a.facilityId,
      p_month_start: monthStart.toISOString(),
      p_month_end: monthEnd.toISOString(),
      p_prev_start: prevStart.toISOString(),
      p_tz: timeZone,
      p_facility_sport_ids: a.sportIds,
    });
    if (!error && data) return buildRevenueOverviewFromTotals(data as RevenueTotals, now, monthOffset);
    if (error && error.code !== "PGRST202" && error.code !== "42883") throw mapSupabaseError(error);

    // Migration 0166 not applied yet: download two months of payments and add them up here.
    const from = prevStart.toISOString();
    const to = monthEnd.toISOString();
    const res = await this.supabase
      .from("payments")
      .select("status, amount_inr, created_at, paid_at, booking_id, membership_id, coaching_enrollment_id")
      .eq("facility_id", a.facilityId)
      // Dated the way Finance dates it: when the money was received (paid_at), else when the row was made.
      .or(`and(paid_at.gte.${from},paid_at.lt.${to}),and(paid_at.is.null,created_at.gte.${from},created_at.lt.${to})`);
    if (res.error) throw mapSupabaseError(res.error);
    const all = ((res.data ?? []) as PaymentRow[]).map((p) => ({ ...p, created_at: p.paid_at ?? p.created_at }));
    const sportSet = a.sportIds ? new Set(a.sportIds) : null;
    const payments = sportSet
      ? await this.paymentsInSports(all, sportSet, a.playingAreasAll, await this.membershipIdsInSports(a.facilityId, sportSet))
      : all;
    return buildRevenueOverview(payments, now, monthOffset);
  }

  async getDashboardSummary(facility: Facility, params: DashboardSummaryParams): Promise<DashboardSummary> {
    const facilityId = facility.id;
    const now = new Date();
    const { current, previous } = resolveDateRange(params.preset, now, params.custom);

    const earliestFrom = previous ? previous.from : current.from;
    const revenueMonthOffset = params.revenueMonthOffset ?? 0;

    // Only today's rows are downloaded (for the Today's Schedule panel); every period total is added up by the database.
    const dayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const dayEnd = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1);

    // None of these depend on one another's results, so they all fire together
    // instead of as two sequential round trips.
    const [facilitySportsAll, sports, playingAreasAll, schedule, todayBookingsRes, todaySessionsRes, pendingDuesRes] = await Promise.all([
      getSportsService().getFacilitySports(facilityId),
      getSportsService().getActiveSports(),
      getPlayingAreasService().getPlayingAreas(facilityId),
      getOperatingHoursService().getFacilitySchedule(facilityId),
      this.supabase
        .from("bookings")
        .select("id, court_id, start_time, end_time, status, customer_type, guest_name, member_id, payment_status")
        .eq("facility_id", facilityId)
        .gte("start_time", dayStart.toISOString())
        .lt("start_time", dayEnd.toISOString()),
      this.supabase.rpc("get_membership_utilization_sessions", {
        p_facility_id: facilityId,
        p_from: localDateKey(dayStart),
        p_to: localDateKey(dayEnd),
      }),
      // Attention Required: everything still owed, oldest due date first (so what is overdue leads). Today -> what is
      // overdue or due by today; any other period -> everything owed. Follows the top bar's sports.
      this.supabase.rpc("list_pending_payments", {
        p_facility_id: facilityId,
        p_status: "ALL_OUTSTANDING",
        p_to: params.preset === "TODAY" ? localDateKey(now) : null,
        p_sort: "DUE_DATE",
        p_limit: 50,
        p_offset: 0,
        p_facility_sport_ids: params.facilitySportIds && params.facilitySportIds.length > 0 ? params.facilitySportIds : null,
      }),
    ]);

    // The sports in view: the ticked subset, or null for All Sports (every number is then facility-wide).
    const requested = (params.facilitySportIds ?? []).filter((id) => facilitySportsAll.some((fs) => fs.id === id));
    const activeSportSet: Set<string> | null =
      requested.length > 0 && requested.length < facilitySportsAll.length ? new Set(requested) : null;

    const facilitySports = activeSportSet ? facilitySportsAll.filter((fs) => activeSportSet.has(fs.id)) : facilitySportsAll;
    const playingAreas = activeSportSet
      ? playingAreasAll.filter((a) => activeSportSet.has(a.facilitySportId))
      : playingAreasAll;
    const playingAreaIds = new Set(playingAreas.map((a) => a.id));

    // Totals, booked court time and the revenue chart are added up by the database (migrations 0165 and 0166). Started now so
    // they run together alongside the lookups below; the old browser-side sums are the fallback until those are applied.
    const soon = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 7);
    const monthStart = new Date(now.getFullYear(), now.getMonth(), 1);
    const sportIds = activeSportSet ? [...activeSportSet] : null;
    const totalsPromise = this.fetchTotals({
      facilityId,
      current,
      previous,
      earliestFrom,
      courtIds: [...playingAreaIds],
      sportIds,
      soon,
      monthStart,
      now,
    });
    const minutesPromise = this.fetchBookedMinutes({ facilityId, current, previous, courtIds: [...playingAreaIds] });
    const revenuePromise = this.fetchRevenueOverview({ facilityId, now, monthOffset: revenueMonthOffset, sportIds, playingAreasAll });

    if (todayBookingsRes.error) throw mapSupabaseError(todayBookingsRes.error);
    if (todaySessionsRes.error) throw mapSupabaseError(todaySessionsRes.error);

    const utilizationInput = {
      playingAreas: playingAreas.map((a) => ({ id: a.id, name: a.name, facilitySportId: a.facilitySportId })),
      facilitySports: facilitySports.map((fs) => ({ id: fs.id, sportId: fs.sportId })),
      sports,
      facilityOperatingDays: schedule?.days ?? [],
    };

    // A membership session that has at least one confirmed slot occupies its court exactly like a booking, so the database
    // counts it in booked time too (a fully-attended membership court is never shown as 0% used).
    const minutes = await minutesPromise;
    const currentUtilization = computeUtilization({
      ...utilizationInput,
      bookings: [],
      bookedMinutesByArea: minutes.current,
      period: current,
    });
    const previousUtilization = previous
      ? computeUtilization({ ...utilizationInput, bookings: [], bookedMinutesByArea: minutes.previous, period: previous })
      : null;

    const totals = await totalsPromise;
    const memberships = totals.memberships;

    // "Today's Schedule" timeline — positioned blocks for today's real bookings and confirmed membership sessions on the
    // courts in view. Member names need a profiles lookup (bookings only carry member_id); guests carry their own.
    const bookingRows = ((todayBookingsRes.data ?? []) as BookingRow[]).filter((b) => playingAreaIds.has(b.court_id));
    const memberIds = [...new Set(bookingRows.filter((b) => b.member_id).map((b) => b.member_id as string))];
    const memberNames = new Map<string, string>();
    if (memberIds.length > 0) {
      const profilesRes = await this.supabase.from("profiles").select("id, full_name").in("id", memberIds);
      if (profilesRes.error) throw mapSupabaseError(profilesRes.error);
      for (const p of profilesRes.data ?? []) memberNames.set(p.id, p.full_name);
    }

    const timelineBookings: TimelineBooking[] = [
      ...bookingRows.map((b) => ({
        id: b.id,
        playingAreaId: b.court_id,
        startTime: b.start_time,
        endTime: b.end_time,
        status: b.status,
        paymentStatus: b.payment_status,
        type: (b.customer_type === "GUEST" ? "GUEST" : "MEMBER") as TimelineBooking["type"],
        label:
          b.customer_type === "GUEST"
            ? b.guest_name ?? "Guest booking"
            : (b.member_id && memberNames.get(b.member_id)) || "Member booking",
      })),
      ...(todaySessionsRes.data ?? [])
        .filter((s) => playingAreaIds.has(s.court_id))
        .map((s, i) => ({
          id: `session-${i}`,
          playingAreaId: s.court_id,
          startTime: `${s.session_date}T${s.start_time}`,
          endTime: `${s.session_date}T${s.end_time}`,
          status: "confirmed",
          type: "SESSION" as const,
          label: "Membership session",
        })),
    ];

    const scheduleTimeline = buildScheduleTimeline({
      playingAreas: utilizationInput.playingAreas,
      facilitySports: utilizationInput.facilitySports,
      sports,
      facilityOperatingDays: utilizationInput.facilityOperatingDays,
      bookings: timelineBookings,
      now,
    });

    const revenueOverview = await revenuePromise;

    return {
      facility: { id: facility.id, name: facility.name, city: facility.address.city },
      sports: facilitySportsAll.map((fs) => {
        const sport = sports.find((s) => s.id === fs.sportId);
        return { facilitySportId: fs.id, sportName: fs.customSportName || sport?.name || "Sport", sportIcon: sport?.icon ?? "🏅" };
      }),
      selectedFacilitySportIds: activeSportSet ? [...activeSportSet] : null,
      period: current,
      kpis: {
        revenueInr: computeKpiValue(totals.payments.collectedInr, previous ? totals.previousCollectedInr : null),
        activeMemberships: computeKpiValue(totals.activeMembershipsInScope, null),
        guestBookings: computeKpiValue(totals.guestBookings, previous ? totals.previousGuestBookings : null),
        utilizationPercent: computeKpiValue(
          currentUtilization.overallPercent,
          previousUtilization?.overallPercent ?? null,
        ),
      },
      revenueBySport: { available: false },
      utilization: currentUtilization,
      scheduleTimeline,
      revenueOverview,
      liveActivity: { available: false },
      memberships,
      guests: { available: false },
      payments: totals.payments,
      expenses: { available: false },
      businessPosition: { revenueInr: totals.payments.collectedInr, expensesAvailable: false },
      attentionItems: buildAttentionItems({
        membershipsExpiringSoon: memberships.expiringSoon,
        obligations: (pendingDuesRes.data ?? []).map((r) => ({
          sourceType: r.source_type,
          sourceId: r.source_id,
          customerName: r.customer_name,
          outstandingInr: Math.round(r.outstanding_minor / 100),
          status: r.status,
          dueOn: r.due_on,
        })),
      }),
      upcomingActivities: { available: false },
    };
  }
}