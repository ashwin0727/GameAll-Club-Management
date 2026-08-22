import { describe, expect, it, vi } from "vitest";
import { SupabaseSportsService } from "@/services/sports/supabase-sports.service";
import { fakeQueryBuilder } from "@/test/fakes/fake-supabase-query";

const SPORT_ROWS = [
  { id: "s-badminton", key: "badminton", name: "Badminton", is_active: true, sort_order: 10 },
  { id: "s-other", key: "other", name: "Other", is_active: true, sort_order: 60 },
];

const FACILITY_SPORT_ROW = {
  id: "fs-1",
  facility_id: "facility-1",
  sport_id: "s-badminton",
  is_active: true,
  custom_sport_name: null,
  created_at: "2026-01-01T00:00:00.000Z",
  updated_at: "2026-01-01T00:00:00.000Z",
};

describe("SupabaseSportsService", () => {
  it("maps active sport rows through presentSport, preserving code/icon/name", async () => {
    const from = vi.fn(() => fakeQueryBuilder({ data: SPORT_ROWS, error: null }));
    const service = new SupabaseSportsService({ from } as never);

    const sports = await service.getActiveSports();

    expect(sports.map((s) => s.code)).toEqual(["BADMINTON", "OTHER"]);
    expect(sports.every((s) => s.icon.length > 0)).toBe(true);
  });

  it("saveFacilitySports calls sync_facility_sports with the selected sport ids and the Other custom name", async () => {
    const rpc = vi.fn(async () => ({ data: [FACILITY_SPORT_ROW], error: null }));
    const service = new SupabaseSportsService({ rpc } as never);

    await service.saveFacilitySports("facility-1", [
      { facilityId: "facility-1", sportId: "s-badminton", enabled: true },
      { facilityId: "facility-1", sportId: "s-other", enabled: true, customSportName: "Kabaddi" },
    ]);

    expect(rpc).toHaveBeenCalledWith("sync_facility_sports", {
      p_facility_id: "facility-1",
      p_sport_ids: ["s-badminton", "s-other"],
      p_custom_sport_name: "Kabaddi",
    });
  });

  it("maps a unique-violation from the RPC to DUPLICATE_FACILITY_SPORT", async () => {
    const rpc = vi.fn(async () => ({ data: null, error: { code: "23505", message: "duplicate" } }));
    const service = new SupabaseSportsService({ rpc } as never);

    await expect(
      service.saveFacilitySports("facility-1", [{ facilityId: "facility-1", sportId: "s-badminton", enabled: true }]),
    ).rejects.toMatchObject({ code: "DUPLICATE_FACILITY_SPORT" });
  });
});