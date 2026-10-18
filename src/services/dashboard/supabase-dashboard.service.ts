"use client";

import type { SupabaseClient } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";
import { getSportsService } from "@/services/sports";
import { getPlayingAreasService } from "@/services/playing-areas";
import { getOperatingHoursService } from "@/services/operating-hours";
import {
  buildAttentionItems,
  buildRevenueOverview,
  buildScheduleTimeline,
  computeKpiValue,
  computeUtilization,
  countActiveMemberships,
  countPaidGuestBookings,
  resolveDateRange,
  sumPaidRevenueInr,
  summarizeMemberships,
  summarizePayments,
  toUtilizationBookings,
  type TimelineBooking,
} from "@/features/dashboard/summary";
import type { DashboardSummary } from "@/features/dashboard/types";
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

  async getDashboardSummary(facility: Facility, params: DashboardSummaryParams): Promise<DashboardSummary> {
    const facilityId = facility.id;
    const now = new Date();
    const { current, previous } = resolveDateRange(params.preset, now, params.custom);

    const earliestFrom = previous ? previous.from : current.from;

    // Revenue Overview panel has its own month filter, independent of `preset`.
    const revenueMonthOffset = params.revenueMonthOffset ?? 0;
    const revWindowFrom = new Date(now.getFullYear(), now.getMonth() - revenueMonthOffset - 1, 1).toISOString();
    const revWindowTo = new Date(now.getFullYear(), now.getMonth() - revenueMonthOffset + 1, 1).toISOString();

    // None of these depend on one another's results, so they all fire together
    // instead of as two sequential round trips.
    const [
      facilitySportsAll,
      sports,
      playingAreasAll,
      schedule,
      bookingsRes,
      membershipsRes,
      paymentsRes,
      membershipSessionsRes,
      revenuePaymentsRes,
      pendingDuesRes,
    ] = await Promise.all([
      getSportsService().getFacilitySports(facilityId),
      getSportsService().getActiveSports(),
      getPlayingAreasService().getPlayingAreas(facilityId),
      getOperatingHoursService().getFacilitySchedule(facilityId),
      this.supabase
        .from("bookings")
        .select("id, court_id, start_time, end_time, status, customer_type, guest_name, member_id, payment_status")
        .eq("facility_id", facilityId)
        .gte("start_time", earliestFrom)
        .lt("start_time", current.to),
      this.supabase.from("memberships").select("id, status, end_date, created_at").eq("facility_id", facilityId),
      this.supabase
        .from("payments")
        .select("status, amount_inr, created_at, booking_id, membership_id, coaching_enrollment_id")
        .eq("facility_id", facilityId)
        .gte("created_at", earliestFrom)
        .lt("created_at", current.to),
      this.supabase.rpc("get_membership_utilization_sessions", {
        p_facility_id: facilityId,
        p_from: earliestFrom.slice(0, 10),
        p_to: current.to.slice(0, 10),
      }),
      this.supabase
        .from("payments")
        .select("status, amount_inr, created_at, paid_at, booking_id, membership_id, coaching_enrollment_id")
        .eq("facility_id", facilityId)
        // Dated the way Finance dates it: when the money was received (paid_at), else when the row was made.
        .or(
          `and(paid_at.gte.${revWindowFrom},paid_at.lt.${revWindowTo}),and(paid_at.is.null,created_at.gte.${revWindowFrom},created_at.lt.${revWindowTo})`,
        ),
      // Attention Required: what is still owed. Today -> only dues falling today; any other period -> everything owed.
      this.supabase.rpc("get_pending_payments_summary", {
        p_facility_id: facilityId,
        p_from: params.preset === "TODAY" ? localDateKey(now) : null,
        p_to: params.preset === "TODAY" ? localDateKey(now) : null,
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

    if (bookingsRes.error) throw mapSupabaseError(bookingsRes.error);
    if (membershipsRes.error) throw mapSupabaseError(membershipsRes.error);
    if (paymentsRes.error) throw mapSupabaseError(paymentsRes.error);
    if (membershipSessionsRes.error) throw mapSupabaseError(membershipSessionsRes.error);
    if (revenuePaymentsRes.error) throw mapSupabaseError(revenuePaymentsRes.error);

    // Actual usage of a membership-protected slot (member or guest) occupies
    // court-time exactly like a regular booking, even though it's tracked in
    // a different table — merged in here so utilization/today's-schedule
    // never treat a fully-attended membership court as 0% used.
    const membershipUtilizationBookings = toUtilizationBookings(
      (membershipSessionsRes.data ?? [])
        .filter((s) => playingAreaIds.has(s.court_id))
        .map((s) => ({ courtId: s.court_id, sessionDate: s.session_date, startTime: s.start_time, endTime: s.end_time })),
    );

    const allBookings = [
      ...((bookingsRes.data ?? []) as BookingRow[]).filter((b) => playingAreaIds.has(b.court_id)),
      ...membershipUtilizationBookings.map((b) => ({ court_id: b.playingAreaId, start_time: b.startTime, end_time: b.endTime, status: b.status })),
    ];
    const currentBookings = allBookings.filter((b) => b.start_time >= current.from && b.start_time < current.to);
    const previousBookings = previous
      ? allBookings.filter((b) => b.start_time >= previous.from && b.start_time < previous.to)
      : [];

    const allPayments = (paymentsRes.data ?? []) as PaymentRow[];
    const currentPayments = allPayments.filter((p) => p.created_at >= current.from && p.created_at < current.to);
    const previousPayments = previous
      ? allPayments.filter((p) => p.created_at >= previous.from && p.created_at < previous.to)
      : [];

    const currentPaymentSummary = summarizePayments(currentPayments);

    const activeCurrentBookings = currentBookings.filter((b) => b.status !== "cancelled");
    const activePreviousBookings = previousBookings.filter((b) => b.status !== "cancelled");

    const utilizationInput = {
      playingAreas: playingAreas.map((a) => ({ id: a.id, name: a.name, facilitySportId: a.facilitySportId })),
      facilitySports: facilitySports.map((fs) => ({ id: fs.id, sportId: fs.sportId })),
      sports,
      facilityOperatingDays: schedule?.days ?? [],
    };

    const currentUtilization = computeUtilization({
      ...utilizationInput,
      bookings: activeCurrentBookings.map((b) => ({
        playingAreaId: b.court_id,
        startTime: b.start_time,
        endTime: b.end_time,
        status: b.status,
      })),
      period: current,
    });
    const previousUtilization = previous
      ? computeUtilization({
          ...utilizationInput,
          bookings: activePreviousBookings.map((b) => ({
            playingAreaId: b.court_id,
            startTime: b.start_time,
            endTime: b.end_time,
            status: b.status,
          })),
          period: previous,
        })
      : null;

    const membershipRows = (membershipsRes.data ?? []) as MembershipRow[];
    const memberships = summarizeMemberships(membershipRows, now);

    // "Today's Schedule" timeline — positioned blocks for real bookings and
    // confirmed membership sessions on today's courts. Member names need a
    // profiles lookup (bookings only carry member_id); guests carry their own.
    const bookingRows = ((bookingsRes.data ?? []) as BookingRow[]).filter((b) => playingAreaIds.has(b.court_id));
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
      ...(membershipSessionsRes.data ?? [])
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

    // KPI scoping: with a specific sport selected, Revenue is narrowed to
    // payments for that sport's courts (via booking) or memberships enrolled
    // in that sport's batches; Active Membership to those same memberships.
    let sportScope: { bookingIds: Set<string>; membershipIds: Set<string> } | null = null;
    let sportMembershipIds: Set<string> | null = null;
    if (activeSportSet) {
      const [batchesRes, batchMembersRes] = await Promise.all([
        this.supabase.from("membership_batches").select("id, facility_sport_id").eq("facility_id", facilityId),
        this.supabase.from("membership_batch_members").select("membership_id, batch_id"),
      ]);
      if (batchesRes.error) throw mapSupabaseError(batchesRes.error);
      if (batchMembersRes.error) throw mapSupabaseError(batchMembersRes.error);
      const batchSport = new Map((batchesRes.data ?? []).map((b) => [b.id, b.facility_sport_id] as const));
      sportMembershipIds = new Set(
        (batchMembersRes.data ?? [])
          .filter((m) => m.membership_id != null && activeSportSet.has(batchSport.get(m.batch_id) ?? ""))
          .map((m) => m.membership_id as string),
      );
      sportScope = { bookingIds: new Set(bookingRows.map((b) => b.id)), membershipIds: sportMembershipIds };
    }

    const scopedCurrentPayments =
      sportScope != null
        ? currentPayments.filter(
            (p) =>
              (p.booking_id != null && sportScope!.bookingIds.has(p.booking_id)) ||
              (p.membership_id != null && sportScope!.membershipIds.has(p.membership_id)),
          )
        : currentPayments;
    const scopedCurrentPaymentSummary = sportScope != null ? summarizePayments(scopedCurrentPayments) : currentPaymentSummary;

    const inWindow = (t: string, w: { from: string; to: string }) => t >= w.from && t < w.to;
    const guestFilter = (b: BookingRow, w: { from: string; to: string }) =>
      b.customer_type === "GUEST" && b.payment_status === "PAID" && b.status !== "cancelled" && inWindow(b.start_time, w);
    const toGuestShape = (b: BookingRow) => ({ customerType: b.customer_type, paymentStatus: b.payment_status, status: b.status });
    const currentGuestBookings = bookingRows.filter((b) => guestFilter(b, current)).map(toGuestShape);
    const previousGuestBookings = previous ? bookingRows.filter((b) => guestFilter(b, previous)).map(toGuestShape) : [];

    // Revenue is money actually received — every payment that is "paid", whether it settled a booking in full or only
    // part of it (an advance, an instalment), whether Razorpay confirmed it or staff recorded it — counted on the day
    // it was received, exactly as Finance counts it.
    const revenueAll = ((revenuePaymentsRes.data ?? []) as PaymentRow[]).map((p) => ({ ...p, created_at: p.paid_at ?? p.created_at }));
    // All Sports counts every payment (coaching and uncategorised ones included). With a subset ticked, a payment
    // counts when what it paid for belongs to one of those sports: a booking on one of their courts, a membership in
    // one of their batches, a coaching enrollment in one of their programs.
    const revenuePayments = activeSportSet
      ? await this.paymentsInSports(revenueAll, activeSportSet, playingAreasAll, sportMembershipIds ?? new Set())
      : revenueAll;
    const revenueOverview = buildRevenueOverview(revenuePayments, now, revenueMonthOffset);

    return {
      facility: { id: facility.id, name: facility.name, city: facility.address.city },
      sports: facilitySportsAll.map((fs) => {
        const sport = sports.find((s) => s.id === fs.sportId);
        return { facilitySportId: fs.id, sportName: fs.customSportName || sport?.name || "Sport", sportIcon: sport?.icon ?? "🏅" };
      }),
      selectedFacilitySportIds: activeSportSet ? [...activeSportSet] : null,
      period: current,
      kpis: {
        revenueInr: computeKpiValue(
          sumPaidRevenueInr(currentPayments, sportScope),
          previous ? sumPaidRevenueInr(previousPayments, sportScope) : null,
        ),
        activeMemberships: computeKpiValue(countActiveMemberships(membershipRows, sportMembershipIds), null),
        guestBookings: computeKpiValue(
          countPaidGuestBookings(currentGuestBookings),
          previous ? countPaidGuestBookings(previousGuestBookings) : null,
        ),
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
      payments: scopedCurrentPaymentSummary,
      expenses: { available: false },
      businessPosition: { revenueInr: scopedCurrentPaymentSummary.collectedInr, expensesAvailable: false },
      attentionItems: buildAttentionItems({
        membershipsExpiringSoon: memberships.expiringSoon,
        paymentsPendingInr: Math.round((pendingDuesRes.data?.[0]?.outstanding_minor ?? 0) / 100),
      }),
      upcomingActivities: { available: false },
    };
  }
}