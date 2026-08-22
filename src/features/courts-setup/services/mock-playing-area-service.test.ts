import { beforeEach, describe, expect, it } from "vitest";
import { MockPlayingAreaService } from "@/features/courts-setup/services/mock-playing-area-service";
import type { PlayingAreaInput } from "@/features/courts-setup/types";

const FACILITY_A = "facility_a";
const FACILITY_SPORT_BADMINTON = "facility_sport_badminton";
const FACILITY_SPORT_PICKLEBALL = "facility_sport_pickleball";

function courtInput(overrides: Partial<PlayingAreaInput> = {}): PlayingAreaInput {
  return {
    facilityId: FACILITY_A,
    facilitySportId: FACILITY_SPORT_BADMINTON,
    sportId: "sport_badminton",
    name: "Court 1",
    type: "INDOOR",
    status: "ACTIVE",
    bookingEnabled: true,
    archived: false,
    displayOrder: 0,
    ...overrides,
    id: overrides.id ?? crypto.randomUUID(),
  };
}

describe("MockPlayingAreaService", () => {
  beforeEach(() => {
    window.localStorage.clear();
  });

  it("creates a playing area and assigns an id and timestamps", async () => {
    const created = await MockPlayingAreaService.createPlayingArea(courtInput());

    expect(created.id).toBeTruthy();
    expect(created.name).toBe("Court 1");
    expect(created.createdAt).toBeTruthy();
    expect(created.updatedAt).toBe(created.createdAt);
  });

  it("retrieves playing areas scoped to a facility", async () => {
    await MockPlayingAreaService.createPlayingArea(courtInput());
    await MockPlayingAreaService.createPlayingArea(
      courtInput({ facilityId: "facility_b", facilitySportId: "other_fs" }),
    );

    const areas = await MockPlayingAreaService.getPlayingAreas(FACILITY_A);
    expect(areas).toHaveLength(1);
    expect(areas[0]?.facilityId).toBe(FACILITY_A);
  });

  it("retrieves playing areas scoped to a facility sport", async () => {
    await MockPlayingAreaService.createPlayingArea(courtInput({ name: "Court 1" }));
    await MockPlayingAreaService.createPlayingArea(
      courtInput({
        facilitySportId: FACILITY_SPORT_PICKLEBALL,
        sportId: "sport_pickleball",
        name: "Court 1",
      }),
    );

    const badminton = await MockPlayingAreaService.getPlayingAreasByFacilitySport(
      FACILITY_SPORT_BADMINTON,
    );
    expect(badminton).toHaveLength(1);
    expect(badminton[0]?.sportId).toBe("sport_badminton");
  });

  it("updates a playing area and bumps updatedAt", async () => {
    const created = await MockPlayingAreaService.createPlayingArea(courtInput());
    await new Promise((resolve) => setTimeout(resolve, 2));

    const updated = await MockPlayingAreaService.updatePlayingArea(created.id, {
      name: "Renamed Court",
    });

    expect(updated.name).toBe("Renamed Court");
    expect(updated.updatedAt).not.toBe(created.updatedAt);
  });

  it("throws when updating a playing area that doesn't exist", async () => {
    await expect(
      MockPlayingAreaService.updatePlayingArea("does-not-exist", { name: "X" }),
    ).rejects.toThrow("Playing area not found");
  });

  it("soft-deletes on remove — the row survives but is excluded from reads", async () => {
    const created = await MockPlayingAreaService.createPlayingArea(courtInput());

    await MockPlayingAreaService.removePlayingArea(created.id);

    const areas = await MockPlayingAreaService.getPlayingAreas(FACILITY_A);
    expect(areas).toHaveLength(0);

    const raw = window.localStorage.getItem("turf.playing-areas.mock.v1") ?? "";
    expect(raw).toContain(created.id);
    expect(raw).toContain('"archived":true');
  });

  it("removing a nonexistent playing area is a harmless no-op", async () => {
    await expect(MockPlayingAreaService.removePlayingArea("does-not-exist")).resolves.toBeUndefined();
  });
});