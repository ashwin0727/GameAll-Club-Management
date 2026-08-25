"use client";

import type { SupabaseClient } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";
import { getFacilityService } from "@/services/facility";
import { getSportsService } from "@/services/sports";
import { getPlayingAreasService } from "@/services/playing-areas";
import { getOperatingHoursService } from "@/services/operating-hours";
import {
  buildAttentionItems,
  buildTodaysSchedule,
  computeKpiValue,
  computeUtilization,
  resolveDateRange,
  summarizeMemberships,
  summarizePayments,
  toUtilizationBookings,
} from "@/features/dashboard/summary";
import type { DashboardSummary } from "@/features/dashboard/types";
import type { DashboardService, DashboardSummaryParams } from "@/services/dashboard/dashboard.service";
import { ServiceError, mapSupabaseError } from "@/services/shared/service-error";
import type { Database } from "@/types/database.types";

type BookingRow = { court_id: string; start_time: string; end_time: string; status: string };
type MembershipRow = { status: string; end_date: string; created_at: string };
type PaymentRow = { status: string; amount_inr: number; created_at: string };

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

    const [bookingsRes, membershipsRes, paymentsRes, membershipSessionsRes] = await Promise.all([
      this.supabase
        .from("bookings")
        .select("court_id, start_time, end_time, status")
        .eq("facility_id", facilityId)
        .gte("start_time", earliestFrom)
        .lt("start_time", current.to),
      this.supabase.from("memberships").select("status, end_date, created_at").eq("facility_id", facilityId),
      this.supabase
        .from("payments")
        .select("status, amount_inr, created_at")
        .eq("facility_id", facilityId)
        .gte("created_at", earliestFrom)
        .lt("created_at", current.to),
      this.supabase.rpc("get_membership_utilization_sessions", {
        p_facility_id: facilityId,
        p_from: earliestFrom.slice(0, 10),
        p_to: current.to.slice(0, 10),
      }),
    ]);

    if (bookingsRes.error) throw mapSupabaseError(bookingsRes.error);
    if (membershipsRes.error) throw mapSupabaseError(membershipsRes.error);
    if (paymentsRes.error) throw mapSupabaseError(paymentsRes.error);
    if (membershipSessionsRes.error) throw mapSupabaseError(membershipSessionsRes.error);

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
    const previousPaymentSummary = previous ? summarizePayments(previousPayments) : null;

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

    const schedule_ = buildTodaysSchedule({
      playingAreas: utilizationInput.playingAreas,
      facilitySports: utilizationInput.facilitySports,
      sports,
      facilityOperatingDays: utilizationInput.facilityOperatingDays,
      bookings: activeCurrentBookings.map((b) => ({
        playingAreaId: b.court_id,
        startTime: b.start_time,
        endTime: b.end_time,
        status: b.status,
      })),
      now,
    });

    return {
      facility: { id: facility.id, name: facility.name, city: facility.address.city },
      sports: facilitySportsAll.map((fs) => {
        const sport = sports.find((s) => s.id === fs.sportId);
        return { facilitySportId: fs.id, sportName: fs.customSportName || sport?.name || "Sport", sportIcon: sport?.icon ?? "🏅" };
      }),
      selectedFacilitySportId: params.facilitySportId,
      period: current,
      kpis: {
        revenueInr: computeKpiValue(currentPaymentSummary.collectedInr, previousPaymentSummary?.collectedInr ?? null),
        bookings: computeKpiValue(activeCurrentBookings.length, previous ? activePreviousBookings.length : null),
        utilizationPercent: computeKpiValue(
          currentUtilization.overallPercent,
          previousUtilization?.overallPercent ?? null,
        ),
        activeMembers: computeKpiValue(memberships.active, null),
      },
      revenueBySport: { available: false },
      utilization: currentUtilization,
      schedule: schedule_,
      liveActivity: { available: false },
      memberships,
      guests: { available: false },
      payments: currentPaymentSummary,
      expenses: { available: false },
      businessPosition: { revenueInr: currentPaymentSummary.collectedInr, expensesAvailable: false },
      attentionItems: buildAttentionItems({
        membershipsExpiringSoon: memberships.expiringSoon,
        paymentsPendingInr: currentPaymentSummary.pendingInr,
      }),
      upcomingActivities: { available: false },
    };
  }
}