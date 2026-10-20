import { describe, expect, it } from "vitest";
import { formatClock, formatDays, formatTiming, groupByCourt } from "@/features/reports/membership-timing";
import type { MembershipBatchRow } from "@/features/reports/types";

const row = (over: Partial<MembershipBatchRow>): MembershipBatchRow => ({
  facilitySportId: "fs-1",
  sportName: "Badminton",
  courtId: "c-1",
  courtName: "Court 1",
  batchId: "b-1",
  batchName: "Morning Batch",
  daysOfWeek: [1, 2, 3, 4, 5, 6],
  startTime: "05:00:00",
  endTime: "06:00:00",
  capacity: 20,
  members: 3,
  activeMembers: 2,
  courtMembers: 4,
  sportMembers: 6,
  ...over,
});

describe("membership timing labels", () => {
  it("formats clock times and ranges", () => {
    expect(formatClock("05:00:00")).toBe("5:00 AM");
    expect(formatClock("12:30:00")).toBe("12:30 PM");
    expect(formatClock("00:15:00")).toBe("12:15 AM");
    expect(formatClock("18:00:00")).toBe("6:00 PM");
    expect(formatTiming("05:00:00", "06:00:00")).toBe("5:00 AM – 6:00 AM");
    expect(formatTiming(null, null)).toBe("");
  });

  it("formats weekdays as ranges, Monday first", () => {
    expect(formatDays([1, 2, 3, 4, 5, 6])).toBe("Mon–Sat");
    expect(formatDays([0, 6])).toBe("Sat, Sun");
    expect(formatDays([1, 3, 5])).toBe("Mon, Wed, Fri");
    expect(formatDays([1, 2, 3, 4, 5])).toBe("Mon–Fri");
    expect(formatDays([0, 1, 2, 3, 4, 5, 6])).toBe("Every day");
  });
});

describe("groupByCourt", () => {
  it("folds rows into sport → court → timings and leaves the unassigned row out", () => {
    const rows = [
      row({ batchId: "b-1" }),
      row({ batchId: "b-2", startTime: "18:00:00", endTime: "19:00:00", members: 1, activeMembers: 1 }),
      row({ batchId: "b-3", courtId: "c-2", courtName: "Court 2", courtMembers: 2 }),
      row({ batchId: "b-4", facilitySportId: "fs-2", sportName: "Cricket", courtName: "Cricket Turf", sportMembers: 5, courtMembers: 5 }),
      row({ batchId: null, facilitySportId: null, sportName: "Not assigned to a session", courtName: null, members: 2 }),
    ];
    const groups = groupByCourt(rows);
    expect(groups.map((g) => g.sportName)).toEqual(["Badminton", "Cricket"]);
    expect(groups[0]!.members).toBe(6);
    expect(groups[0]!.courts.map((c) => c.courtName)).toEqual(["Court 1", "Court 2"]);
    expect(groups[0]!.courts[0]!.timings).toHaveLength(2);
    expect(groups[1]!.courts[0]!.courtName).toBe("Cricket Turf");
  });
});
