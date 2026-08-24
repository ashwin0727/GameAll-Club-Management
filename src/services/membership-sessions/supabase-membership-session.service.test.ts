import { describe, expect, it, vi } from "vitest";
import { SupabaseMembershipSessionService } from "@/services/membership-sessions/supabase-membership-session.service";
import { ServiceError } from "@/services/shared/service-error";
import { fakeQueryBuilder } from "@/test/fakes/fake-supabase-query";

const BATCH_ROW = {
  id: "batch-1",
  facility_id: "facility-1",
  plan_id: "plan-1",
  facility_sport_id: "fs-1",
  court_id: "court-1",
  name: "Evening Badminton",
  days_of_week: [1, 3, 5],
  start_time: "18:00:00",
  end_time: "19:00:00",
  capacity: 5,
  is_active: true,
  created_at: "2026-08-01T00:00:00.000Z",
  updated_at: "2026-08-01T00:00:00.000Z",
};

describe("SupabaseMembershipSessionService", () => {
  it("createBatch calls create_membership_batch with every field", async () => {
    const rpc = vi.fn(async () => ({ data: BATCH_ROW, error: null }));
    const service = new SupabaseMembershipSessionService({ rpc } as never);

    const batch = await service.createBatch({
      facilityId: "facility-1",
      planId: "plan-1",
      facilitySportId: "fs-1",
      courtId: "court-1",
      name: "Evening Badminton",
      daysOfWeek: [1, 3, 5],
      startTime: "18:00:00",
      endTime: "19:00:00",
      capacity: 5,
    });

    expect(rpc).toHaveBeenCalledWith(
      "create_membership_batch",
      expect.objectContaining({ p_facility_id: "facility-1", p_court_id: "court-1", p_capacity: 5, p_days_of_week: [1, 3, 5] }),
    );
    expect(batch.id).toBe("batch-1");
    expect(batch.daysOfWeek).toEqual([1, 3, 5]);
  });

  it("surfaces the exact business-rule message from a 23514 capacity violation, not a generic string", async () => {
    const rpc = vi.fn(async () => ({
      data: null,
      error: { code: "23514", message: "Cannot release more than the unused membership capacity." },
    }));
    const service = new SupabaseMembershipSessionService({ rpc } as never);

    await expect(service.releaseCapacity("session-1", 3)).rejects.toMatchObject({
      code: "MEMBERSHIP_CAPACITY_ERROR",
      message: "Cannot release more than the unused membership capacity.",
    });
  });

  it("releaseCapacity calls release_membership_capacity with the session id and count", async () => {
    const rpc = vi.fn(async () => ({ data: { ...BATCH_ROW }, error: null }));
    const service = new SupabaseMembershipSessionService({ rpc } as never);

    await service.releaseCapacity("session-1", 2);

    expect(rpc).toHaveBeenCalledWith("release_membership_capacity", { p_session_id: "session-1", p_count: 2 });
  });

  it("restoreCapacity calls restore_membership_capacity with the session id and count", async () => {
    const rpc = vi.fn(async () => ({ data: { ...BATCH_ROW }, error: null }));
    const service = new SupabaseMembershipSessionService({ rpc } as never);

    await service.restoreCapacity("session-1", 1);

    expect(rpc).toHaveBeenCalledWith("restore_membership_capacity", { p_session_id: "session-1", p_count: 1 });
  });

  it("bookGuestSlot maps a full-capacity rejection to MEMBERSHIP_CAPACITY_ERROR", async () => {
    const rpc = vi.fn(async () => ({
      data: null,
      error: { code: "23514", message: "No guest slots are currently available for this session." },
    }));
    const service = new SupabaseMembershipSessionService({ rpc } as never);

    await expect(service.bookGuestSlot("batch-1", "2026-08-24", "guest-1")).rejects.toThrow(ServiceError);
  });

  it("getSessionCapacity maps every derived count from the RPC row", async () => {
    const rpc = vi.fn(async () => ({
      data: [{ capacity: 5, released_capacity: 2, member_booked_count: 3, guest_booked_count: 1, unused_capacity: 2, guest_available_capacity: 1 }],
      error: null,
    }));
    const service = new SupabaseMembershipSessionService({ rpc } as never);

    const capacity = await service.getSessionCapacity("session-1");

    expect(capacity).toEqual({
      capacity: 5,
      releasedCapacity: 2,
      memberBookedCount: 3,
      guestBookedCount: 1,
      unusedCapacity: 2,
      guestAvailableCapacity: 1,
    });
  });

  it("listSessionsForDate maps every slot, including an unmaterialized session (sessionId null)", async () => {
    const rpc = vi.fn(async () => ({
      data: [
        {
          batch_id: "batch-1",
          session_id: null,
          batch_name: "Evening Badminton",
          court_id: "court-1",
          court_name: "Court 1",
          facility_sport_id: "fs-1",
          sport_name: "Badminton",
          session_date: "2026-08-24",
          start_time: "18:00:00",
          end_time: "19:00:00",
          capacity: 5,
          released_capacity: 0,
          member_booked_count: 0,
          guest_booked_count: 0,
        },
      ],
      error: null,
    }));
    const service = new SupabaseMembershipSessionService({ rpc } as never);

    const slots = await service.listSessionsForDate("facility-1", "2026-08-24");

    expect(slots).toHaveLength(1);
    expect(slots[0]).toMatchObject({ sessionId: null, batchName: "Evening Badminton", capacity: 5 });
  });

  it("updateBatch falls back to existing values for fields not in the patch", async () => {
    const from = vi.fn(() => fakeQueryBuilder({ data: BATCH_ROW, error: null }));
    const rpc = vi.fn(async () => ({ data: { ...BATCH_ROW, capacity: 8 }, error: null }));
    const service = new SupabaseMembershipSessionService({ from, rpc } as never);

    const updated = await service.updateBatch("batch-1", { capacity: 8 });

    expect(rpc).toHaveBeenCalledWith(
      "update_membership_batch",
      expect.objectContaining({ p_batch_id: "batch-1", p_capacity: 8, p_name: "Evening Badminton", p_court_id: "court-1" }),
    );
    expect(updated.capacity).toBe(8);
  });
});