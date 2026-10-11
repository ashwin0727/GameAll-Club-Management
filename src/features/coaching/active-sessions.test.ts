import { describe, expect, it } from "vitest";
import { todaysActiveCount } from "@/features/coaching/active-sessions";

describe("todaysActiveCount", () => {
  it("counts every session the day has, except cancelled ones", () => {
    expect(todaysActiveCount([{ status: "SCHEDULED" }, { status: "IN_PROGRESS" }, { status: "CONFIRMED" }, { status: "CANCELLED" }, { status: "COMPLETED" }])).toBe(4);
  });
  it("is zero when the day has none", () => {
    expect(todaysActiveCount([])).toBe(0);
  });
});
