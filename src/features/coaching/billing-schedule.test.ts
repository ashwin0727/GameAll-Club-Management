import { describe, expect, it } from "vitest";
import { chargeDates, chargesLeft, nextPaymentDate, perSessionMinor, programLengthLabel, upcomingCharges } from "@/features/coaching/billing-schedule";

describe("chargeDates", () => {
  it("is the same day each month: 14 Oct → 14 Nov → 14 Dec → 14 Jan", () => {
    expect(chargeDates("2026-10-14", 4)).toEqual(["2026-10-14", "2026-11-14", "2026-12-14", "2027-01-14"]);
  });
  it("clamps month ends without drifting: 31 Jan → 28 Feb → 31 Mar", () => {
    expect(chargeDates("2026-01-31", 3)).toEqual(["2026-01-31", "2026-02-28", "2026-03-31"]);
  });
  it("is at least one charge", () => {
    expect(chargeDates("2026-10-14", 0)).toEqual(["2026-10-14"]);
  });
});

describe("programLengthLabel", () => {
  it("reads the program's own dates in weeks and months", () => {
    expect(programLengthLabel("2026-10-01", "2027-03-17")).toBe("24 weeks · 6 months");
    expect(programLengthLabel("2026-10-01", "2026-10-07")).toBe("1 week · 1 month");
  });
  it("is null without both dates", () => {
    expect(programLengthLabel("2026-10-01", null)).toBeNull();
    expect(programLengthLabel(null, "2026-10-01")).toBeNull();
  });
});

describe("perSessionMinor", () => {
  it("spreads the total over the sessions", () => {
    expect(perSessionMinor(720_000, 72)).toBe(10_000);
  });
  it("is null when the session count or total is unknown", () => {
    expect(perSessionMinor(7_200_00, null)).toBeNull();
    expect(perSessionMinor(0, 72)).toBeNull();
  });
});

describe("nextPaymentDate / chargesLeft", () => {
  const base = { kind: "SUBSCRIPTION" as const, currentEnd: "2026-11-14" };
  it("is the current cycle's end only while charging", () => {
    expect(nextPaymentDate({ ...base, status: "ACTIVE" })).toBe("2026-11-14");
    expect(nextPaymentDate({ ...base, status: "PENDING" })).toBe("2026-11-14");
    expect(nextPaymentDate({ ...base, status: "CREATED" })).toBeNull();
    expect(nextPaymentDate({ ...base, status: "CANCELLED" })).toBeNull();
    expect(nextPaymentDate({ kind: "PAYMENT_LINK", status: "ACTIVE", currentEnd: "2026-11-14" })).toBeNull();
    expect(nextPaymentDate(null)).toBeNull();
  });
  it("counts the charges still to come", () => {
    expect(chargesLeft({ totalCycles: 6, chargeCount: 2 })).toBe(4);
    expect(chargesLeft({ totalCycles: 3, chargeCount: 5 })).toBe(0);
  });
});

describe("upcomingCharges", () => {
  const b = (over: Partial<Parameters<typeof upcomingCharges>[0] & object> = {}) => ({
    kind: "SUBSCRIPTION" as const,
    status: "ACTIVE" as const,
    currentEnd: "2026-11-14",
    totalCycles: 6,
    chargeCount: 2,
    ...over,
  });
  it("lists the next dates, month by month, capped at the limit", () => {
    expect(upcomingCharges(b())).toEqual(["2026-11-14", "2026-12-14", "2027-01-14"]);
  });
  it("never lists more than the charges left", () => {
    expect(upcomingCharges(b({ chargeCount: 5 }))).toEqual(["2026-11-14"]);
    expect(upcomingCharges(b({ chargeCount: 6 }))).toEqual([]);
  });
  it("is empty when nothing is charging", () => {
    expect(upcomingCharges(b({ status: "CANCELLED" }))).toEqual([]);
    expect(upcomingCharges(null)).toEqual([]);
  });
});
