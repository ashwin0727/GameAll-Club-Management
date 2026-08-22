import { describe, expect, it, vi } from "vitest";
import { SupabasePlayingAreasService } from "@/services/playing-areas/supabase-playing-areas.service";
import { fakeQueryBuilder } from "@/test/fakes/fake-supabase-query";
import type { PlayingAreaInput } from "@/features/courts-setup/types";

const INPUT: PlayingAreaInput = {
  id: "area-1",
  facilityId: "facility-1",
  facilitySportId: "fs-1",
  sportId: "s-badminton",
  name: "Court 1",
  type: "INDOOR",
  status: "ACTIVE",
  bookingEnabled: true,
  archived: false,
  displayOrder: 0,
};

describe("SupabasePlayingAreasService", () => {
  it("getPlayingAreas filters by facility and excludes archived rows", async () => {
    const builder = fakeQueryBuilder({ data: [], error: null });
    const from = vi.fn(() => builder);
    const service = new SupabasePlayingAreasService({ from } as never);

    await service.getPlayingAreas("facility-1");

    expect(from).toHaveBeenCalledWith("courts");
    expect(builder.eq).toHaveBeenCalledWith("facility_id", "facility-1");
    expect(builder.eq).toHaveBeenCalledWith("archived", false);
  });

  it("maps a duplicate-name violation to DUPLICATE_PLAYING_AREA", async () => {
    const from = vi.fn(() =>
      fakeQueryBuilder({ data: null, error: { code: "23505", message: "duplicate" } }),
    );
    const service = new SupabasePlayingAreasService({ from } as never);

    await expect(service.createPlayingArea(INPUT)).rejects.toMatchObject({ code: "DUPLICATE_PLAYING_AREA" });
  });

  it("maps a missing facility_sport (fk violation) to FACILITY_SPORT_NOT_FOUND", async () => {
    const from = vi.fn(() =>
      fakeQueryBuilder({ data: null, error: { code: "23503", message: "fk violation" } }),
    );
    const service = new SupabasePlayingAreasService({ from } as never);

    await expect(service.createPlayingArea(INPUT)).rejects.toMatchObject({ code: "FACILITY_SPORT_NOT_FOUND" });
  });

  it("maps the facility_sport/sport consistency trigger's check violation to INVALID_PLAYING_AREA", async () => {
    const from = vi.fn(() =>
      fakeQueryBuilder({ data: null, error: { code: "23514", message: "consistency check failed" } }),
    );
    const service = new SupabasePlayingAreasService({ from } as never);

    await expect(service.createPlayingArea(INPUT)).rejects.toMatchObject({ code: "INVALID_PLAYING_AREA" });
  });

  it("removePlayingArea soft-deletes by setting archived true, never a real delete", async () => {
    const builder = fakeQueryBuilder({ data: null, error: null });
    const from = vi.fn(() => builder);
    const service = new SupabasePlayingAreasService({ from } as never);

    await service.removePlayingArea("area-1");

    expect(builder.update).toHaveBeenCalledWith({ archived: true });
    expect(builder.eq).toHaveBeenCalledWith("id", "area-1");
  });
});