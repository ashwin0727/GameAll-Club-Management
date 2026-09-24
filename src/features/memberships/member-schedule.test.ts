import { describe, expect, it } from "vitest";
import {
  assignedCourtIds,
  assignedCourtNames,
  blocksForDay,
  groupMemberSchedules,
  preferredTimeRanges,
  weekDates,
  type MemberBatchSlot,
  type OtherCourtEvent,
} from "@/features/memberships/member-schedule";
import type { MemberScheduleRow } from "@/features/memberships/types";

function row(overrides: Partial<MemberScheduleRow> = {}): MemberScheduleRow {
  return {
    memberId: "member-1",
    fullName: "Rahul Sharma",
    phone: "9876543210",
    status: "ACTIVE",
    membershipId: "membership-1",
    batchId: "batch-1",
    batchName: "Batch 3",
    courtId: "court-1",
    courtName: "Court 01",
    facilitySportId: "sport-1",
    sportName: "Badminton",
    daysOfWeek: [1, 2, 3, 4, 5],
    startTime: "07:00:00",
    endTime: "08:00:00",
    ...overrides,
  };
}

describe("groupMemberSchedules", () => {
  it("groups multiple (member, batch) rows into one entry per member, sorted by name", () => {
    const rows = [
      row({ memberId: "member-2", fullName: "Zoya Khan", batchId: "batch-2" }),
      row({ memberId: "member-1", fullName: "Rahul Sharma", batchId: "batch-1" }),
      row({ memberId: "member-1", fullName: "Rahul Sharma", batchId: "batch-3", courtId: "court-2", courtName: "Court 02" }),
    ];
    const result = groupMemberSchedules(rows);
    expect(result.map((m) => m.fullName)).toEqual(["Rahul Sharma", "Zoya Khan"]);
    expect(result[0]!.slots).toHaveLength(2);
    expect(result[0]!.slots.map((s) => s.batchId)).toEqual(["batch-1", "batch-3"]);
  });

  it("returns an empty list for no rows", () => {
    expect(groupMemberSchedules([])).toEqual([]);
  });

  it("prefers a non-null membershipId when an earlier row's is null", () => {
    const rows = [
      row({ membershipId: null, batchId: "batch-1" }),
      row({ membershipId: "membership-1", batchId: "batch-2" }),
    ];
    expect(groupMemberSchedules(rows)[0]!.membershipId).toBe("membership-1");
  });
});

function slot(overrides: Partial<MemberBatchSlot> = {}): MemberBatchSlot {
  return {
    batchId: "batch-1",
    batchName: "Batch 3",
    courtId: "court-1",
    courtName: "Court 01",
    daysOfWeek: [1, 2, 3, 4, 5],
    startTime: "07:00",
    endTime: "08:00",
    ...overrides,
  };
}

describe("assignedCourtIds / assignedCourtNames", () => {
  it("dedupes courts across slots", () => {
    const slots = [slot({ courtId: "court-1", courtName: "Court 01" }), slot({ courtId: "court-1", courtName: "Court 01" }), slot({ courtId: "court-2", courtName: "Court 02" })];
    expect(assignedCourtIds(slots)).toEqual(["court-1", "court-2"]);
    expect(assignedCourtNames(slots)).toEqual(["Court 01", "Court 02"]);
  });
});

describe("preferredTimeRanges", () => {
  it("dedupes identical start/end pairs across slots", () => {
    const slots = [
      slot({ startTime: "07:00", endTime: "08:00" }),
      slot({ startTime: "07:00", endTime: "08:00", courtId: "court-2" }),
      slot({ startTime: "18:00", endTime: "19:00" }),
    ];
    expect(preferredTimeRanges(slots)).toEqual([
      { startTime: "07:00", endTime: "08:00" },
      { startTime: "18:00", endTime: "19:00" },
    ]);
  });
});

describe("weekDates", () => {
  it("returns the 7 dates of the week, Monday first", () => {
    // 2026-09-16 is a Wednesday.
    const dates = weekDates(new Date(2026, 8, 16));
    expect(dates.map((d) => d.getDay())).toEqual([1, 2, 3, 4, 5, 6, 0]);
    expect(dates[0]!.getDate()).toBe(14); // Monday 14 Sep 2026
    expect(dates[6]!.getDate()).toBe(20); // Sunday 20 Sep 2026
  });
});

describe("blocksForDay", () => {
  const tue = new Date(2026, 8, 15); // Tuesday
  const sun = new Date(2026, 8, 20); // Sunday

  it("is just the Court Closed block when the day is closed, ignoring everything else", () => {
    const blocks = blocksForDay(sun, [slot({ daysOfWeek: [0] })], [], ["court-1"], true);
    expect(blocks).toEqual([{ kind: "CLOSED", startTime: "00:00", endTime: "24:00", title: "Court Closed", subtitle: "" }]);
  });

  it("includes a member slot only on its own weekdays", () => {
    const monFriSlot = slot({ daysOfWeek: [1, 2, 3, 4, 5] });
    expect(blocksForDay(tue, [monFriSlot], [], ["court-1"], false)).toHaveLength(1);
    expect(blocksForDay(sun, [monFriSlot], [], ["court-1"], false)).toHaveLength(0);
  });

  it("excludes a member slot on a court outside visibleCourtIds", () => {
    const blocks = blocksForDay(tue, [slot({ courtId: "court-9" })], [], ["court-1"], false);
    expect(blocks).toHaveLength(0);
  });

  it("includes guest/maintenance events overlapping the day, on a visible court", () => {
    const events: OtherCourtEvent[] = [
      {
        courtId: "court-1",
        start: new Date(2026, 8, 15, 9, 0),
        end: new Date(2026, 8, 15, 10, 0),
        kind: "GUEST",
        title: "Guest Booking",
        subtitle: "Guest",
      },
      {
        courtId: "court-9",
        start: new Date(2026, 8, 15, 11, 0),
        end: new Date(2026, 8, 15, 12, 0),
        kind: "MAINTENANCE",
        title: "Net repair",
        subtitle: "Court blocked",
      },
    ];
    const blocks = blocksForDay(tue, [], events, ["court-1"], false);
    expect(blocks).toEqual([
      { kind: "GUEST", startTime: "09:00", endTime: "10:00", title: "Guest Booking", subtitle: "Guest", href: undefined },
    ]);
  });

  it("clips an event that spans past midnight to the visible day's boundaries", () => {
    const events: OtherCourtEvent[] = [
      {
        courtId: "court-1",
        start: new Date(2026, 8, 14, 22, 0),
        end: new Date(2026, 8, 15, 2, 0),
        kind: "MAINTENANCE",
        title: "Overnight repair",
        subtitle: "Court blocked",
      },
    ];
    const blocks = blocksForDay(tue, [], events, ["court-1"], false);
    expect(blocks).toEqual([
      { kind: "MAINTENANCE", startTime: "00:00", endTime: "02:00", title: "Overnight repair", subtitle: "Court blocked", href: undefined },
    ]);
  });

  it("sorts member and other blocks together by start time", () => {
    const morning = slot({ startTime: "06:00", endTime: "07:00" });
    const events: OtherCourtEvent[] = [
      { courtId: "court-1", start: new Date(2026, 8, 15, 9, 0), end: new Date(2026, 8, 15, 10, 0), kind: "GUEST", title: "Guest", subtitle: "Guest" },
    ];
    const blocks = blocksForDay(tue, [morning], events, ["court-1"], false);
    expect(blocks.map((b) => b.kind)).toEqual(["MEMBER", "GUEST"]);
  });
});
