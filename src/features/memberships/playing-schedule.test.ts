import { describe, expect, it } from "vitest";
import {
  DAY_PRESETS,
  findMatchingBatch,
  groupContiguousRanges,
  HOUR_BLOCKS,
  matchingPreset,
  validatePlayingSchedule,
  type BatchSlot,
  type PlayingScheduleDraft,
} from "@/features/memberships/playing-schedule";

function draft(overrides: Partial<PlayingScheduleDraft> = {}): PlayingScheduleDraft {
  return { facilitySportId: "sport-1", courtId: "court-1", daysOfWeek: [1, 2, 3, 4, 5], times: [], ...overrides };
}

describe("HOUR_BLOCKS", () => {
  it("covers the full 24-hour day, one block per hour", () => {
    expect(HOUR_BLOCKS).toHaveLength(24);
    expect(HOUR_BLOCKS[0]).toEqual({ start: "00:00", end: "01:00", label: "12 AM - 1 AM" });
    expect(HOUR_BLOCKS[23]).toEqual({ start: "23:00", end: "24:00", label: "11 PM - 12 AM" });
  });

  it("has no gaps — each block's end is the next block's start", () => {
    for (let i = 0; i < HOUR_BLOCKS.length - 1; i++) {
      expect(HOUR_BLOCKS[i]!.end).toBe(HOUR_BLOCKS[i + 1]!.start);
    }
  });

  it("labels morning and evening hours correctly", () => {
    const eleven = HOUR_BLOCKS.find((b) => b.start === "11:00")!;
    const noon = HOUR_BLOCKS.find((b) => b.start === "12:00")!;
    const six_pm = HOUR_BLOCKS.find((b) => b.start === "18:00")!;
    expect(eleven.label).toBe("11 AM - 12 PM");
    expect(noon.label).toBe("12 PM - 1 PM");
    expect(six_pm.label).toBe("6 PM - 7 PM");
  });
});

describe("matchingPreset", () => {
  it("recognises each preset's exact day set", () => {
    expect(matchingPreset([1, 2, 3, 4, 5])).toBe("weekdays");
    expect(matchingPreset([1, 2, 3, 4, 5, 6])).toBe("mon-sat");
    expect(matchingPreset([0, 6])).toBe("weekend");
  });

  it("is order independent", () => {
    expect(matchingPreset([5, 4, 3, 2, 1])).toBe("weekdays");
  });

  it("falls back to custom for anything else, including empty", () => {
    expect(matchingPreset([1, 3, 5])).toBe("custom");
    expect(matchingPreset([])).toBe("custom");
    expect(matchingPreset([1, 2, 3, 4, 5, 0])).toBe("custom");
  });
});

describe("groupContiguousRanges", () => {
  it("merges back-to-back hours into one range", () => {
    expect(groupContiguousRanges(["06:00", "07:00"])).toEqual([{ startTime: "06:00", endTime: "08:00" }]);
    expect(groupContiguousRanges(["06:00", "07:00", "08:00"])).toEqual([{ startTime: "06:00", endTime: "09:00" }]);
  });

  it("keeps non-adjacent hours as separate ranges", () => {
    expect(groupContiguousRanges(["06:00", "14:00", "15:00"])).toEqual([
      { startTime: "06:00", endTime: "07:00" },
      { startTime: "14:00", endTime: "16:00" },
    ]);
  });

  it("doesn't care about selection order", () => {
    expect(groupContiguousRanges(["08:00", "06:00", "07:00"])).toEqual([{ startTime: "06:00", endTime: "09:00" }]);
  });

  it("de-duplicates a repeated hour", () => {
    expect(groupContiguousRanges(["06:00", "06:00"])).toEqual([{ startTime: "06:00", endTime: "07:00" }]);
  });

  it("returns nothing for no selection", () => {
    expect(groupContiguousRanges([])).toEqual([]);
  });
});

describe("validatePlayingSchedule", () => {
  it("is entirely optional with nothing selected", () => {
    expect(validatePlayingSchedule(draft({ times: [], courtId: "", daysOfWeek: [] }))).toBeNull();
  });

  it("needs a court once any hour is picked", () => {
    expect(validatePlayingSchedule(draft({ times: ["06:00"], courtId: "" }))).toMatch(/court/i);
    expect(validatePlayingSchedule(draft({ times: ["06:00"], courtId: "court-1" }))).toBeNull();
  });

  it("needs at least one day once any hour is picked", () => {
    expect(validatePlayingSchedule(draft({ times: ["06:00"], daysOfWeek: [] }))).toMatch(/day/i);
  });
});

describe("DAY_PRESETS", () => {
  it("is the four presets from the design, in order", () => {
    expect(DAY_PRESETS.map((p) => p.label)).toEqual(["Mon - Fri", "Mon - Sat", "Weekends", "Custom"]);
  });
});

describe("findMatchingBatch", () => {
  function batch(overrides: Partial<BatchSlot> = {}): BatchSlot {
    return { batchId: "batch-1", courtId: "court-1", daysOfWeek: [1, 2, 3, 4, 5], startTime: "06:00", endTime: "07:00", ...overrides };
  }

  it("matches an existing batch on the same court, clock range and exact day set", () => {
    const found = findMatchingBatch([batch()], { courtId: "court-1", daysOfWeek: [1, 2, 3, 4, 5], startTime: "06:00", endTime: "07:00" });
    expect(found?.batchId).toBe("batch-1");
  });

  it("still matches when the stored times carry a Postgres ':00' seconds suffix", () => {
    const found = findMatchingBatch([batch({ startTime: "06:00:00", endTime: "07:00:00" })], {
      courtId: "court-1",
      daysOfWeek: [1, 2, 3, 4, 5],
      startTime: "06:00",
      endTime: "07:00",
    });
    expect(found?.batchId).toBe("batch-1");
  });

  it("doesn't care about day order — [5,1,3,2,4] matches [1,2,3,4,5]", () => {
    const found = findMatchingBatch([batch({ daysOfWeek: [5, 1, 3, 2, 4] })], {
      courtId: "court-1",
      daysOfWeek: [1, 2, 3, 4, 5],
      startTime: "06:00",
      endTime: "07:00",
    });
    expect(found?.batchId).toBe("batch-1");
  });

  it("won't match a different court, clock range, or day set", () => {
    const wanted = { courtId: "court-1", daysOfWeek: [1, 2, 3, 4, 5], startTime: "06:00", endTime: "07:00" };
    expect(findMatchingBatch([batch({ courtId: "court-2" })], wanted)).toBeUndefined();
    expect(findMatchingBatch([batch({ startTime: "07:00", endTime: "08:00" })], wanted)).toBeUndefined();
    expect(findMatchingBatch([batch({ daysOfWeek: [1, 2, 3] })], wanted)).toBeUndefined();
  });

  it("returns undefined when there's nothing to match against", () => {
    expect(findMatchingBatch([], { courtId: "court-1", daysOfWeek: [1], startTime: "06:00", endTime: "07:00" })).toBeUndefined();
  });
});
