import { describe, expect, it } from "vitest";
import { computeMembershipEndDate, computeMembershipStatus, daysUntilExpiry } from "./status";

describe("computeMembershipStatus", () => {
  const now = new Date("2026-08-23T12:00:00Z");

  it("is CANCELLED regardless of dates when the DB status is cancelled", () => {
    expect(computeMembershipStatus({ status: "cancelled", endDate: "2027-01-01" }, now)).toBe("CANCELLED");
    expect(computeMembershipStatus({ status: "cancelled", endDate: "2020-01-01" }, now)).toBe("CANCELLED");
  });

  it("is EXPIRED once the end date has passed", () => {
    expect(computeMembershipStatus({ status: "active", endDate: "2026-08-01" }, now)).toBe("EXPIRED");
  });

  it("is EXPIRING_SOON within the warning window", () => {
    expect(computeMembershipStatus({ status: "active", endDate: "2026-08-28" }, now)).toBe("EXPIRING_SOON");
    expect(computeMembershipStatus({ status: "active", endDate: "2026-08-23" }, now)).toBe("EXPIRING_SOON");
  });

  it("is ACTIVE well before expiry", () => {
    expect(computeMembershipStatus({ status: "active", endDate: "2026-12-01" }, now)).toBe("ACTIVE");
  });

  it("is NO_MEMBERSHIP for a member who has never been assigned a plan", () => {
    expect(computeMembershipStatus(null, now)).toBe("NO_MEMBERSHIP");
  });
});

describe("daysUntilExpiry", () => {
  it("returns a positive count for a future date", () => {
    expect(daysUntilExpiry("2026-08-30", new Date("2026-08-23T00:00:00Z"))).toBeGreaterThan(0);
  });

  it("returns a negative count for a past date", () => {
    expect(daysUntilExpiry("2026-08-01", new Date("2026-08-23T00:00:00Z"))).toBeLessThan(0);
  });
});

describe("computeMembershipEndDate", () => {
  it("adds duration_days to the start date", () => {
    expect(computeMembershipEndDate("2026-01-01", 30)).toBe("2026-01-31");
  });

  it("handles month/year rollovers", () => {
    expect(computeMembershipEndDate("2026-12-15", 365)).toBe("2027-12-15");
  });
});