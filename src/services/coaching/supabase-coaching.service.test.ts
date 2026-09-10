import { describe, expect, it, vi } from "vitest";
import { SupabaseCoachingService } from "@/services/coaching/supabase-coaching.service";
import { ServiceError } from "@/services/shared/service-error";

describe("SupabaseCoachingService", () => {
  it("listCoaches maps rows, sends filters and carries total_count", async () => {
    const row = {
      id: "c1",
      user_id: "u1",
      full_name: "Rahul Mehta",
      email: "rahul@x.com",
      phone: null,
      avatar_url: null,
      specialization: "Beginner",
      experience_years: 5,
      status: "ACTIVE",
      program_count: 2,
      session_count: 18,
      student_count: 42,
      total_count: 6,
    };
    const rpc = vi.fn(async () => ({ data: [row], error: null }));
    const service = new SupabaseCoachingService({ rpc } as never);
    const page = await service.listCoaches({ facilityId: "f1", filters: { status: "ACTIVE" } });

    expect(rpc).toHaveBeenCalledWith("list_coaches", {
      p_facility_id: "f1",
      p_search: null,
      p_status: "ACTIVE",
      p_specialization: null,
      p_limit: 20,
      p_offset: 0,
    });
    expect(page.totalCount).toBe(6);
    expect(page.coaches[0]?.fullName).toBe("Rahul Mehta");
    expect(page.coaches[0]?.studentCount).toBe(42);
  });

  it("addCoach forwards the staff user id and returns the new coach id", async () => {
    const rpc = vi.fn(async () => ({ data: { id: "coach-1" }, error: null }));
    const id = await new SupabaseCoachingService({ rpc } as never).addCoach("f1", "u9", { specialization: "Kids" });
    expect(id).toBe("coach-1");
    expect(rpc).toHaveBeenCalledWith(
      "add_coach",
      expect.objectContaining({ p_facility_id: "f1", p_user_id: "u9", p_specialization: "Kids" }),
    );
  });

  it("setCoachAvailability serialises windows to the RPC's jsonb shape", async () => {
    const rpc = vi.fn(async () => ({ error: null }));
    await new SupabaseCoachingService({ rpc } as never).setCoachAvailability("c1", [
      { dayOfWeek: 1, startTime: "16:00", endTime: "20:00" },
    ]);
    expect(rpc).toHaveBeenCalledWith("set_coach_availability", {
      p_coach_id: "c1",
      p_windows: [{ dayOfWeek: 1, startTime: "16:00", endTime: "20:00" }],
    });
  });

  it("maps a slot conflict to COACHING_CONFLICT with the server message", async () => {
    const rpc = vi.fn(async () => ({ data: null, error: { message: "This court is already booked during this time." } }));
    await expect(
      new SupabaseCoachingService({ rpc } as never).createSession({
        facilityId: "f1",
        programId: "p1",
        coachId: "c1",
        courtId: "ct1",
        startAt: "2026-09-08T09:00:00Z",
        endAt: "2026-09-08T10:00:00Z",
      }),
    ).rejects.toMatchObject({ code: "COACHING_CONFLICT", message: "This court is already booked during this time." });
  });

  it("maps a permission rejection (42501) to COACHING_ACCESS_DENIED", async () => {
    const rpc = vi.fn(async () => ({ data: null, error: { code: "42501", message: "denied" } }));
    await expect(
      new SupabaseCoachingService({ rpc } as never).createProgram({ facilityId: "f1", name: "Beginner" }),
    ).rejects.toMatchObject({ code: "COACHING_ACCESS_DENIED" });
  });

  it("maps a duplicate active enrollment to COACHING_DUPLICATE", async () => {
    const rpc = vi.fn(async () => ({
      data: null,
      error: { code: "23505", message: "This member already has an active enrollment in this program." },
    }));
    await expect(
      new SupabaseCoachingService({ rpc } as never).createEnrollment({ facilityId: "f1", memberId: "m1", programId: "p1" }),
    ).rejects.toMatchObject({ code: "COACHING_DUPLICATE" });
  });

  it("cancelSession sends the reason and throws a ServiceError on failure", async () => {
    const rpc = vi.fn(async () => ({ error: { message: "boom" } }));
    await expect(new SupabaseCoachingService({ rpc } as never).cancelSession("s1", "Coach ill")).rejects.toThrow(ServiceError);
    expect(rpc).toHaveBeenCalledWith("cancel_coaching_session", { p_session_id: "s1", p_reason: "Coach ill" });
  });

  it("listEnrollments maps the derived payment status", async () => {
    const rpc = vi.fn(async () => ({
      data: [
        {
          id: "e1",
          member_id: "m1",
          student_name: "Arun",
          student_phone: "9",
          program_id: "p1",
          program_name: "Beginner",
          coach_name: null,
          start_date: "2026-09-01",
          end_date: null,
          sessions_total: 8,
          price_minor: 300000,
          paid_minor: 100000,
          status: "ACTIVE",
          payment_status: "PARTIAL",
          total_count: 1,
        },
      ],
      error: null,
    }));
    const page = await new SupabaseCoachingService({ rpc } as never).listEnrollments({ facilityId: "f1" });
    expect(page.enrollments[0]?.paymentStatus).toBe("PARTIAL");
    expect(page.enrollments[0]?.priceMinor).toBe(300000);
  });
});
