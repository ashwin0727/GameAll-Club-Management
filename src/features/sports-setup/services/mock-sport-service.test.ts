import { beforeEach, describe, expect, it } from "vitest";
import { MockSportService } from "@/features/sports-setup/services/mock-sport-service";
import { OTHER_SPORT_ID } from "@/features/sports-setup/constants";
import type { FacilitySportInput } from "@/features/sports-setup/types";

const FACILITY_A = "facility_a";
const FACILITY_B = "facility_b";

function rows(facilityId: string, sportIds: string[]): FacilitySportInput[] {
  return sportIds.map((sportId) => ({ facilityId, sportId, enabled: true }));
}

describe("MockSportService", () => {
  beforeEach(() => {
    window.localStorage.clear();
  });

  it("returns all six active sports", async () => {
    const sports = await MockSportService.getAvailableSports();
    expect(sports).toHaveLength(6);
    expect(sports.every((sport) => sport.isActive)).toBe(true);
  });

  it("returns an empty array for a facility with no saved sports", async () => {
    expect(await MockSportService.getFacilitySports(FACILITY_A)).toEqual([]);
  });

  it("saves sports for a facility and assigns ids and timestamps", async () => {
    const saved = await MockSportService.saveFacilitySports(
      FACILITY_A,
      rows(FACILITY_A, ["sport_badminton", "sport_pickleball"]),
    );

    expect(saved).toHaveLength(2);
    for (const row of saved) {
      expect(row.id).toBeTruthy();
      expect(row.createdAt).toBeTruthy();
      expect(row.facilityId).toBe(FACILITY_A);
    }
  });

  it("retrieves saved sports scoped to the correct facility only", async () => {
    await MockSportService.saveFacilitySports(FACILITY_A, rows(FACILITY_A, ["sport_badminton"]));
    await MockSportService.saveFacilitySports(FACILITY_B, rows(FACILITY_B, ["sport_cricket"]));

    const aSports = await MockSportService.getFacilitySports(FACILITY_A);
    const bSports = await MockSportService.getFacilitySports(FACILITY_B);

    expect(aSports.map((row) => row.sportId)).toEqual(["sport_badminton"]);
    expect(bSports.map((row) => row.sportId)).toEqual(["sport_cricket"]);
  });

  it("replaces a facility's sports on re-save, removing deselected ones", async () => {
    await MockSportService.saveFacilitySports(
      FACILITY_A,
      rows(FACILITY_A, ["sport_badminton", "sport_pickleball", "sport_cricket"]),
    );

    const updated = await MockSportService.saveFacilitySports(FACILITY_A, rows(FACILITY_A, ["sport_badminton"]));

    expect(updated.map((row) => row.sportId)).toEqual(["sport_badminton"]);
    const reread = await MockSportService.getFacilitySports(FACILITY_A);
    expect(reread.map((row) => row.sportId)).toEqual(["sport_badminton"]);
  });

  it("re-saving one facility's sports does not affect another facility's rows", async () => {
    await MockSportService.saveFacilitySports(FACILITY_A, rows(FACILITY_A, ["sport_badminton"]));
    await MockSportService.saveFacilitySports(FACILITY_B, rows(FACILITY_B, ["sport_cricket"]));

    await MockSportService.saveFacilitySports(FACILITY_A, rows(FACILITY_A, ["sport_tennis"]));

    const bSports = await MockSportService.getFacilitySports(FACILITY_B);
    expect(bSports.map((row) => row.sportId)).toEqual(["sport_cricket"]);
  });

  it("stores customSportName only on the Other row", async () => {
    const saved = await MockSportService.saveFacilitySports(FACILITY_A, [
      { facilityId: FACILITY_A, sportId: "sport_badminton", enabled: true },
      { facilityId: FACILITY_A, sportId: OTHER_SPORT_ID, enabled: true, customSportName: "Basketball" },
    ]);

    const other = saved.find((row) => row.sportId === OTHER_SPORT_ID);
    const badminton = saved.find((row) => row.sportId === "sport_badminton");
    expect(other?.customSportName).toBe("Basketball");
    expect(badminton?.customSportName).toBeUndefined();
  });

  it("preserves id and createdAt for a sport that was already selected, across re-saves", async () => {
    const first = await MockSportService.saveFacilitySports(
      FACILITY_A,
      rows(FACILITY_A, ["sport_badminton", "sport_pickleball"]),
    );
    const badmintonId = first.find((row) => row.sportId === "sport_badminton")?.id;
    const badmintonCreatedAt = first.find((row) => row.sportId === "sport_badminton")?.createdAt;

    // Re-saving the exact same selection (e.g. navigating Back to Sports
    // and clicking Continue again without changing anything) must not mint
    // a new id — anything holding facilitySportId as a foreign key (like a
    // saved court) would otherwise be silently orphaned.
    const second = await MockSportService.saveFacilitySports(
      FACILITY_A,
      rows(FACILITY_A, ["sport_badminton", "sport_pickleball"]),
    );
    const badmintonAgain = second.find((row) => row.sportId === "sport_badminton");

    expect(badmintonAgain?.id).toBe(badmintonId);
    expect(badmintonAgain?.createdAt).toBe(badmintonCreatedAt);
  });

  it("mints a new id only for a genuinely newly-added sport on re-save", async () => {
    const first = await MockSportService.saveFacilitySports(FACILITY_A, rows(FACILITY_A, ["sport_badminton"]));
    const badmintonId = first[0]?.id;

    const second = await MockSportService.saveFacilitySports(
      FACILITY_A,
      rows(FACILITY_A, ["sport_badminton", "sport_cricket"]),
    );

    expect(second.find((row) => row.sportId === "sport_badminton")?.id).toBe(badmintonId);
    expect(second.find((row) => row.sportId === "sport_cricket")?.id).toBeTruthy();
    expect(second.find((row) => row.sportId === "sport_cricket")?.id).not.toBe(badmintonId);
  });

  it("updateFacilitySports also replaces the full set", async () => {
    await MockSportService.saveFacilitySports(FACILITY_A, rows(FACILITY_A, ["sport_badminton"]));
    const updated = await MockSportService.updateFacilitySports(
      FACILITY_A,
      rows(FACILITY_A, ["sport_badminton", "sport_football"]),
    );

    expect(updated.map((row) => row.sportId).sort()).toEqual(["sport_badminton", "sport_football"]);
  });
});