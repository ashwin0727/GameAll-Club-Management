import { afterEach, describe, expect, it, vi } from "vitest";
import { bankFromIfsc, lookupIfsc } from "@/features/payout-setup/banks";
import { DEFAULT_PAYOUT_SETTINGS, validatePayoutSettings } from "@/features/payout-setup/payout-settings";
import { bankPayoutSchema, maskAccountNumber } from "@/features/profile/payout-validation";

describe("bank from IFSC", () => {
  it("names the bank from the first four letters, in any case", () => {
    expect(bankFromIfsc("HDFC0001234")).toBe("HDFC Bank");
    expect(bankFromIfsc("sbin0000001")).toBe("State Bank of India");
    expect(bankFromIfsc("ZZZZ0000001")).toBeNull();
  });
});

describe("IFSC lookup", () => {
  afterEach(() => vi.unstubAllGlobals());

  it("returns null without calling out for a malformed code", async () => {
    const f = vi.fn();
    vi.stubGlobal("fetch", f);
    expect(await lookupIfsc("HDFC123")).toBeNull();
    expect(f).not.toHaveBeenCalled();
  });

  it("returns the bank and branch, and null for an unknown code", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValueOnce({ ok: true, status: 200, json: async () => ({ BANK: "HDFC Bank", BRANCH: "Koramangala", CITY: "Bengaluru" }) }));
    expect(await lookupIfsc("hdfc0001234")).toEqual({ bank: "HDFC Bank", branch: "Koramangala", city: "Bengaluru" });
    vi.stubGlobal("fetch", vi.fn().mockResolvedValueOnce({ ok: false, status: 404 }));
    expect(await lookupIfsc("HDFC0009999")).toBeNull();
  });

  it("throws when the directory is down, so the caller can say try again instead of not found", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValueOnce({ ok: false, status: 503 }));
    await expect(lookupIfsc("HDFC0001234")).rejects.toThrow();
  });
});

describe("payout settings", () => {
  it("accepts the defaults", () => {
    expect(validatePayoutSettings(DEFAULT_PAYOUT_SETTINGS)).toBeNull();
  });
  it("needs at least one earning included", () => {
    expect(validatePayoutSettings({ ...DEFAULT_PAYOUT_SETTINGS, includeBookings: false, includeMemberships: false, includeCoaching: false })).toMatch(/at least one/i);
  });
  it("keeps the minimum payout within range", () => {
    expect(validatePayoutSettings({ ...DEFAULT_PAYOUT_SETTINGS, minimumPayoutInr: -1 })).not.toBeNull();
    expect(validatePayoutSettings({ ...DEFAULT_PAYOUT_SETTINGS, minimumPayoutInr: 2_000_000 })).not.toBeNull();
    expect(validatePayoutSettings({ ...DEFAULT_PAYOUT_SETTINGS, minimumPayoutInr: 0 })).toBeNull();
  });
});

describe("bank account details", () => {
  it("requires an account type", () => {
    const r = bankPayoutSchema.safeParse({ type: "BANK", accountHolderName: "Champz Turf", bankName: "HDFC Bank", accountNumber: "123456789012", ifsc: "HDFC0001234" });
    expect(r.success).toBe(false);
  });
  it("shows only the last four digits", () => {
    expect(maskAccountNumber("4821")).toBe("•••• 4821");
    expect(maskAccountNumber(null)).toBe("");
  });
});
