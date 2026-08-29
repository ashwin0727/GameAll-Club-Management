"use client";

import type { SupabaseClient } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";
import { getFacilityService } from "@/services/facility";
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
import type { DashboardService, DashboardSummaryParams } from "@/services/dashboard/dashboard.service";
import { ServiceError, mapSupabaseError } from "@/services/shared/service-error";
import type { Database } from "@/types/database.types";

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
  booking_id: string | null;
  membership_id: string | null;
};

export class SupabaseDashboardService implements DashboardService {
  private readonly supabase: SupabaseClient<Database>;

  constructor(client?: SupabaseClient<Database>) {
    this.supabase = client ?? createClient();
  }

  async getDashboardSummary(facilityId: string, params: DashboardSummaryParams): Promise<DashboardSummary> {
    const facility = await getFacilityService().getFacility();
    if (!facility || facility.id !== facilityId) throw new ServiceError("FACILITY_NOT_FOUND");

    const now = new Date();
    const { current, previous } = resolveDateRange(params.preset, now, params.custom);

    const [facilitySportsAll, sports, playingAreasAll, schedule] = await Promise.all([
      getSportsService().getFacilitySports(facilityId),
      getSportsService().getActiveSports(),
      getPlayingAreasService().getPlayingAreas(facilityId),
      getOperatingHoursService().getFacilitySchedule(facilityId),
    ]);

    const facilitySports = params.facilitySportId
      ? facilitySportsAll.filter((fs) => fs.id === params.facilitySportId)
      : facilitySportsAll;
    const playingAreas = params.facilitySportId
      ? playingAreasAll.filter((a) => a.facilitySportId === params.facilitySportId)
      : playingAreasAll;
    const playingAreaIds = new Set(playingAreas.map((a) => a.id));

    const earliestFrom = previous ? previous.from : current.from;

    // Revenue Overview panel has its own month filter, independent of `preset`.
    const revenueMonthOffset = params.revenueMonthOffset ?? 0;
    const revWindowFrom = new Date(now.getFullYear(), now.getMonth() - revenueMonthOffset - 1, 1).toISOString();
    const revWindowTo = new Date(now.getFullYear(), now.getMonth() - revenueMonthOffset + 1, 1).toISOString();

    const [bookingsRes, membershipsRes, paymentsRes, membershipSessionsRes, revenuePaymentsRes] = await Promise.all([
      this.supabase
        .from("bookings")
        .select("id, court_id, start_time, end_time, status, customer_type, guest_name, member_id, payment_status")
        .eq("facility_id", facilityId)
        .gte("start_time", earliestFrom)
        .lt("start_time", current.to),
      this.supabase.from("memberships").select("id, status, end_date, created_at").eq("facility_id", facilityId),
      this.supabase
        .from("payments")
        .select("status, amount_inr, created_at, booking_id, membership_id")
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
        .select("status, amount_inr, created_at, booking_id, membership_id")
        .eq("facility_id", facilityId)
        .gte("created_at", revWindowFrom)
        .lt("created_at", revWindowTo),
    ]);

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
    if (params.facilitySportId) {
      const [batchesRes, batchMembersRes] = await Promise.all([
        this.supabase.from("membership_batches").select("id, facility_sport_id").eq("facility_id", facilityId),
        this.supabase.from("membership_batch_members").select("membership_id, batch_id"),
      ]);
      if (batchesRes.error) throw mapSupabaseError(batchesRes.error);
      if (batchMembersRes.error) throw mapSupabaseError(batchMembersRes.error);
      const batchSport = new Map((batchesRes.data ?? []).map((b) => [b.id, b.facility_sport_id] as const));
      sportMembershipIds = new Set(
        (batchMembersRes.data ?? [])
          .filter((m) => m.membership_id != null && batchSport.get(m.batch_id) === params.facilitySportId)
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

    const revenuePayments = ((revenuePaymentsRes.data ?? []) as PaymentRow[]).filter(
      (p) =>
        sportScope == null ||
        (p.booking_id != null && sportScope.bookingIds.has(p.booking_id)) ||
        (p.membership_id != null && sportScope.membershipIds.has(p.membership_id)),
    );
    const revenueOverview = buildRevenueOverview(revenuePayments, now, revenueMonthOffset);

    return {
      facility: { id: facility.id, name: facility.name, city: facility.address.city },
      sports: facilitySportsAll.map((fs) => {
        const sport = sports.find((s) => s.id === fs.sportId);
        return { facilitySportId: fs.id, sportName: fs.customSportName || sport?.name || "Sport", sportIcon: sport?.icon ?? "🏅" };
      }),
      selectedFacilitySportId: params.facilitySportId,
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
        paymentsPendingInr: currentPaymentSummary.pendingInr,
      }),
      upcomingActivities: { available: false },
    };
  }
}