import { describe, expect, it } from "vitest";
import { daysLeft, formatPlanDate, isPlanActive, isPlanTrial } from "@/features/profile/plan";
import { maskAccountNumber, maskUpi, payoutSchema } from "@/features/profile/payout-validation";
import { formatPhone, normalisePhone, profileEditSchema } from "@/features/profile/profile-validation";

describe("plan status", () => {
  const plan = { status: "active" as const, validTill: "2026-12-31" };

  it("is active until its last covered day has passed", () => {
    expect(isPlanActive(plan, "2026-12-31")).toBe(true);
    expect(isPlanActive(plan, "2027-01-01")).toBe(false);
  });

  it("is inactive when cancelled or missing", () => {
    expect(isPlanActive({ ...plan, status: "cancelled" }, "2026-01-01")).toBe(false);
    expect(isPlanActive(null)).toBe(false);
  });

  it("counts whole days left", () => {
    expect(daysLeft("2026-12-31", "2026-12-30")).toBe(1);
    expect(daysLeft("2026-12-31", "2026-12-31")).toBe(0);
    expect(daysLeft("2026-12-31", "2027-01-02")).toBe(-2);
  });

  it("formats the valid-till date", () => {
    expect(formatPlanDate("2026-12-31")).toBe("31 Dec 2026");
  });

  it("treats a free trial as active until its last day, and recognises it", () => {
    const trial = { status: "trialing" as const, validTill: "2027-01-25" };
    expect(isPlanActive(trial, "2026-10-25")).toBe(true);
    expect(isPlanTrial(trial, "2026-10-25")).toBe(true);
    expect(isPlanActive(trial, "2027-01-26")).toBe(false);
    expect(isPlanTrial(trial, "2027-01-26")).toBe(false);
    expect(isPlanTrial(plan, "2026-10-25")).toBe(false);
  });
});

describe("payout validation", () => {
  it("accepts a bank account and normalises the IFSC", () => {
    const r = payoutSchema.safeParse({ type: "BANK", accountHolderName: "Champz Turf", bankName: "HDFC Bank", accountNumber: "123456789012", ifsc: "hdfc0001234" });
    expect(r.success).toBe(true);
    if (r.success && r.data.type === "BANK") expect(r.data.ifsc).toBe("HDFC0001234");
  });

  it("rejects short account numbers and malformed IFSC codes", () => {
    const bad = payoutSchema.safeParse({ type: "BANK", accountHolderName: "A B", bankName: "HDFC", accountNumber: "1234", ifsc: "HDFC123" });
    expect(bad.success).toBe(false);
  });

  it("accepts and lower-cases a UPI id, rejects a malformed one", () => {
    const ok = payoutSchema.safeParse({ type: "UPI", accountHolderName: "Champz Turf", upiId: "Champz@OkHDFC" });
    expect(ok.success && ok.data.type === "UPI" && ok.data.upiId).toBe("champz@okhdfc");
    expect(payoutSchema.safeParse({ type: "UPI", accountHolderName: "Champz Turf", upiId: "nope" }).success).toBe(false);
  });

  it("masks account numbers and UPI handles", () => {
    expect(maskAccountNumber("123456789012")).toBe("XXXXXXXX9012");
    expect(maskUpi("champz@okhdfc")).toBe("ch••••@okhdfc");
  });
});

describe("profile validation", () => {
  it("accepts a mobile number with or without +91, and an empty one", () => {
    for (const phone of ["9876543210", "+91 98765 43210", "98765-43210", ""]) {
      expect(profileEditSchema.safeParse({ fullName: "Champz Owner", phone }).success).toBe(true);
    }
  });

  it("rejects a bad number or a missing name", () => {
    expect(profileEditSchema.safeParse({ fullName: "Champz Owner", phone: "12345" }).success).toBe(false);
    expect(profileEditSchema.safeParse({ fullName: "", phone: "" }).success).toBe(false);
  });

  it("normalises and formats", () => {
    expect(normalisePhone("+91 98765 43210")).toBe("9876543210");
    expect(formatPhone("9876543210")).toBe("+91 98765 43210");
  });
});
