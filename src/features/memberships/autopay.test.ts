import { describe, expect, it } from "vitest";
import { autoPayCadence, autoPayNextCharge, autoPayStatusLabel, effectiveAutoPayStatus } from "@/features/memberships/autopay";

describe("autoPayCadence", () => {
  it("says how often the member is charged", () => {
    expect(autoPayCadence(1)).toBe("every month");
    expect(autoPayCadence(3)).toBe("every 3 months");
    expect(autoPayCadence(6)).toBe("every 6 months");
    expect(autoPayCadence(12)).toBe("every year");
    expect(autoPayCadence(null)).toBe("every month");
  });
});

describe("autoPayStatusLabel", () => {
  it("has a label for every status", () => {
    for (const s of ["created", "authenticated", "active", "pending", "halted", "cancelled", "completed"] as const) {
      expect(autoPayStatusLabel(s).label.length).toBeGreaterThan(0);
    }
    expect(autoPayStatusLabel("active").label).toBe("Active");
  });
});

describe("effectiveAutoPayStatus / autoPayNextCharge", () => {
  it("treats an authorised subscription that has already been charged as active", () => {
    expect(effectiveAutoPayStatus({ status: "authenticated", chargeCount: 1 })).toBe("active");
    expect(effectiveAutoPayStatus({ status: "authenticated", chargeCount: 0 })).toBe("authenticated");
    expect(effectiveAutoPayStatus({ status: "cancelled", chargeCount: 3 })).toBe("cancelled");
  });

  it("shows the next charge once AutoPay is running — Razorpay's date first, else the membership's", () => {
    expect(autoPayNextCharge({ status: "authenticated", chargeCount: 1, nextChargeDate: null }, "2026-11-14")).toBe("2026-11-14");
    expect(autoPayNextCharge({ status: "active", chargeCount: 2, nextChargeDate: "2026-12-14" }, "2026-11-14")).toBe("2026-12-14");
    expect(autoPayNextCharge({ status: "pending", chargeCount: 2, nextChargeDate: null }, "2026-11-14")).toBe("2026-11-14");
  });

  it("shows nothing before the first charge or after AutoPay has stopped", () => {
    expect(autoPayNextCharge({ status: "created", chargeCount: 0, nextChargeDate: null }, "2026-11-14")).toBeNull();
    expect(autoPayNextCharge({ status: "authenticated", chargeCount: 0, nextChargeDate: null }, "2026-11-14")).toBeNull();
    expect(autoPayNextCharge({ status: "cancelled", chargeCount: 3, nextChargeDate: "2026-12-14" }, "2026-11-14")).toBeNull();
    expect(autoPayNextCharge({ status: "halted", chargeCount: 3, nextChargeDate: null }, "2026-11-14")).toBeNull();
  });
});
