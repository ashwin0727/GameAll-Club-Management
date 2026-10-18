import { describe, expect, it } from "vitest";
import { displayBatchName, newBatchName } from "@/features/membership-sessions/batch-name";

describe("displayBatchName", () => {
  it("turns a start-time-only name into the full range", () => {
    expect(displayBatchName("Morning Monthly Membership (5 AM to 6 AM) — 05:00", "05:00:00", "06:00:00")).toBe(
      "Morning Monthly Membership (5 AM to 6 AM) — 05:00 to 06:00",
    );
  });
  it("handles a plain hyphen and a seconds suffix", () => {
    expect(displayBatchName("Evening Plan - 18:30:00", "18:30:00", "19:30:00")).toBe("Evening Plan — 18:30 to 19:30");
  });
  it("leaves a name that already has the range, or no time at all, alone", () => {
    expect(displayBatchName("Plan — 05:00 to 06:00", "05:00", "06:00")).toBe("Plan — 05:00 to 06:00");
    expect(displayBatchName("Batch 1", "05:00", "06:00")).toBe("Batch 1");
  });
  it("leaves the name when the times are unknown", () => {
    expect(displayBatchName("Plan — 05:00", "", "")).toBe("Plan — 05:00");
  });
});

describe("newBatchName", () => {
  it("names a slot with its whole range", () => {
    expect(newBatchName("Morning Monthly Membership (5 AM to 6 AM)", "05:00", "06:00")).toBe("Morning Monthly Membership (5 AM to 6 AM) — 05:00 to 06:00");
  });
});
