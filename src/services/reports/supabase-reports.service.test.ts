import { describe, expect, it, vi } from "vitest";
import { SupabaseReportsService } from "@/services/reports/supabase-reports.service";
import { ServiceError } from "@/services/shared/service-error";
import type { AnalyticsFilter } from "@/features/reports/types";

const filter: AnalyticsFilter = { facilityId: "fac-1", preset: "THIS_MONTH" };

const ANALYTICS_ROW = {
  total: 205,
  completed: 120,
  confirmed: 60,
  pending: 5,
  cancelled: 20,
  guest_count: 130,
  member_count: 75,
  avg_guest_booking_value_minor: 55000,
};

describe("SupabaseReportsService.getBookingAnalytics", () => {
  it("calls get_booking_analytics with resolved date + scope args and maps the row", async () => {
    const rpc = vi.fn(async () => ({ data: [ANALYTICS_ROW], error: null }));
    const service = new SupabaseReportsService({ rpc } as never);

    const result = await service.getBookingAnalytics({ ...filter, facilitySportId: "fs-1" });

    expect(rpc).toHaveBeenCalledWith("get_booking_analytics", {
      p_facility_id: "fac-1",
      p_preset: "THIS_MONTH",
      p_start_date: null,
      p_end_date: null,
      p_facility_sport_id: "fs-1",
      p_court_id: null,
    });
    expect(result).toEqual({
      total: 205,
      completed: 120,
      confirmed: 60,
      pending: 5,
      cancelled: 20,
      guestCount: 130,
      memberCount: 75,
      avgGuestBookingValueMinor: 55000,
    });
  });

  it("maps a facility-isolation denial to REPORTS_ACCESS_DENIED (never a fake zero row)", async () => {
    const rpc = vi.fn(async () => ({ data: null, error: { message: "Not authorized for this facility." } }));
    const service = new SupabaseReportsService({ rpc } as never);
    await expect(service.getBookingAnalytics(filter)).rejects.toMatchObject({ code: "REPORTS_ACCESS_DENIED" });
  });

  it("maps an invalid custom range to INVALID_DATE_RANGE", async () => {
    const rpc = vi.fn(async () => ({
      data: null,
      error: { message: "A custom date range requires a valid start and end date." },
    }));
    const service = new SupabaseReportsService({ rpc } as never);
    await expect(service.getBookingAnalytics({ ...filter, preset: "CUSTOM" })).rejects.toMatchObject({
      code: "INVALID_DATE_RANGE",
    });
  });

  it("throws ServiceError, not a raw object", async () => {
    const rpc = vi.fn(async () => ({ data: null, error: { message: "boom" } }));
    const service = new SupabaseReportsService({ rpc } as never);
    await expect(service.getBookingAnalytics(filter)).rejects.toThrow(ServiceError);
  });
});

describe("SupabaseReportsService.getBookingTrend", () => {
  it("passes the granularity and maps bucket rows", async () => {
    const rpc = vi.fn(async () => ({
      data: [{ bucket_date: "2026-09-01", total: 8, completed: 5, cancelled: 1 }],
      error: null,
    }));
    const service = new SupabaseReportsService({ rpc } as never);
    const result = await service.getBookingTrend(filter, "weekly");
    expect(rpc).toHaveBeenCalledWith(
      "get_booking_trend",
      expect.objectContaining({ p_granularity: "weekly", p_facility_id: "fac-1" }),
    );
    expect(result).toEqual([{ date: "2026-09-01", total: 8, completed: 5, cancelled: 1 }]);
  });
});

describe("SupabaseReportsService.getBookingsBySport / getBookingSourceSplit", () => {
  it("maps by-sport rows", async () => {
    const rpc = vi.fn(async () => ({
      data: [{ facility_sport_id: "fs-1", sport_name: "Badminton", booking_count: 120 }],
      error: null,
    }));
    const service = new SupabaseReportsService({ rpc } as never);
    expect(await service.getBookingsBySport(filter)).toEqual([
      { facilitySportId: "fs-1", sportName: "Badminton", bookingCount: 120 },
    ]);
  });

  it("maps source-split rows", async () => {
    const rpc = vi.fn(async () => ({
      data: [
        { source: "GUEST", booking_count: 130 },
        { source: "MEMBER", booking_count: 75 },
      ],
      error: null,
    }));
    const service = new SupabaseReportsService({ rpc } as never);
    expect(await service.getBookingSourceSplit(filter)).toEqual([
      { source: "GUEST", bookingCount: 130 },
      { source: "MEMBER", bookingCount: 75 },
    ]);
  });
});

describe("SupabaseReportsService utilization", () => {
  it("getOverallUtilization reads the single row", async () => {
    const rpc = vi.fn(async () => ({
      data: [{ open_minutes: 1000, booked_minutes: 680, utilization_pct: 68 }],
      error: null,
    }));
    const service = new SupabaseReportsService({ rpc } as never);
    expect(await service.getOverallUtilization({ ...filter, facilitySportId: "fs-1" })).toEqual({
      openMinutes: 1000,
      bookedMinutes: 680,
      utilizationPct: 68,
    });
    expect(rpc).toHaveBeenCalledWith(
      "get_overall_utilization",
      expect.objectContaining({ p_facility_id: "fac-1", p_facility_sport_id: "fs-1", p_court_id: null }),
    );
  });

  it("getOverallUtilization maps a denial to REPORTS_ACCESS_DENIED", async () => {
    const rpc = vi.fn(async () => ({ data: null, error: { message: "Not authorized for this facility." } }));
    const service = new SupabaseReportsService({ rpc } as never);
    await expect(service.getOverallUtilization(filter)).rejects.toMatchObject({ code: "REPORTS_ACCESS_DENIED" });
  });

  it("getCourtUtilization maps rows", async () => {
    const rpc = vi.fn(async () => ({
      data: [
        {
          court_id: "c1",
          court_name: "Court 1",
          facility_sport_id: "fs1",
          sport_name: "Badminton",
          open_minutes: 600,
          booked_minutes: 420,
          utilization_pct: 70,
        },
      ],
      error: null,
    }));
    const service = new SupabaseReportsService({ rpc } as never);
    expect(await service.getCourtUtilization(filter)).toEqual([
      {
        courtId: "c1",
        courtName: "Court 1",
        facilitySportId: "fs1",
        sportName: "Badminton",
        openMinutes: 600,
        bookedMinutes: 420,
        utilizationPct: 70,
      },
    ]);
    expect(rpc).toHaveBeenCalledWith("get_court_utilization", expect.objectContaining({ p_facility_id: "fac-1" }));
  });

  it("getSportUtilization maps rows", async () => {
    const rpc = vi.fn(async () => ({
      data: [{ facility_sport_id: "fs1", sport_name: "Badminton", open_minutes: 6000, booked_minutes: 4080, utilization_pct: 68 }],
      error: null,
    }));
    const service = new SupabaseReportsService({ rpc } as never);
    expect(await service.getSportUtilization(filter)).toEqual([
      { facilitySportId: "fs1", sportName: "Badminton", openMinutes: 6000, bookedMinutes: 4080, utilizationPct: 68 },
    ]);
  });

  it("getPeakHours maps rows", async () => {
    const rpc = vi.fn(async () => ({
      data: [{ hour: 18, open_minutes: 300, booked_minutes: 270, demand_pct: 90 }],
      error: null,
    }));
    const service = new SupabaseReportsService({ rpc } as never);
    expect(await service.getPeakHours(filter)).toEqual([
      { hour: 18, openMinutes: 300, bookedMinutes: 270, demandPct: 90 },
    ]);
  });

  it("getDemandHeatmap maps cells", async () => {
    const rpc = vi.fn(async () => ({
      data: [{ dow: 1, hour: 18, open_minutes: 60, booked_minutes: 54, demand_pct: 90 }],
      error: null,
    }));
    const service = new SupabaseReportsService({ rpc } as never);
    expect(await service.getDemandHeatmap(filter)).toEqual([
      { dow: 1, hour: 18, openMinutes: 60, bookedMinutes: 54, demandPct: 90 },
    ]);
  });
});
