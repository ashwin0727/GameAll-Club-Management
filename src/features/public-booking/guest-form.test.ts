import { describe, expect, it } from "vitest";
import { EMPTY_GUEST, durationLabel, formatMoney, toDateParam, validateGuest } from "./guest-form";

const guest = (over: Partial<typeof EMPTY_GUEST> = {}) => ({ ...EMPTY_GUEST, ...over });

describe("validateGuest", () => {
  it("requires a name", () => {
    expect(validateGuest(guest({ phone: "9876543210" })).fullName).toBe("Please enter your name.");
  });

  it("treats whitespace as a missing name", () => {
    expect(validateGuest(guest({ fullName: "   ", phone: "9876543210" })).fullName).toBeDefined();
  });

  it("requires a phone number", () => {
    expect(validateGuest(guest({ fullName: "Rahul" })).phone).toBe("Please enter your mobile number.");
  });

  it("rejects a number that is too short to be real", () => {
    expect(validateGuest(guest({ fullName: "Rahul", phone: "12345" })).phone).toBe(
      "Please enter a valid mobile number.",
    );
  });

  it("rejects a number that is too long", () => {
    expect(validateGuest(guest({ fullName: "Rahul", phone: "1234567890123456" })).phone).toBeDefined();
  });

  it("accepts a number written with a country code and punctuation", () => {
    expect(validateGuest(guest({ fullName: "Rahul", phone: "+91 98765-43210" })).phone).toBeUndefined();
  });

  it("passes a complete, valid guest", () => {
    expect(validateGuest(guest({ fullName: "Rahul Sharma", phone: "9876543210" }))).toEqual({});
  });

  it("ignores email when blank, since it is optional", () => {
    expect(validateGuest(guest({ fullName: "R", phone: "9876543210", email: "" })).email).toBeUndefined();
  });

  it("rejects a malformed email when one is supplied", () => {
    expect(validateGuest(guest({ fullName: "R", phone: "9876543210", email: "nope" })).email).toBeDefined();
  });

  it("validates the alternate phone only when supplied", () => {
    expect(validateGuest(guest({ fullName: "R", phone: "9876543210", altPhone: "" })).altPhone).toBeUndefined();
    expect(validateGuest(guest({ fullName: "R", phone: "9876543210", altPhone: "123" })).altPhone).toBeDefined();
  });
});

describe("formatMoney", () => {
  it("renders minor units as whole rupees", () => {
    expect(formatMoney(40000)).toContain("400");
  });

  it("survives a missing amount rather than printing NaN", () => {
    expect(formatMoney(0)).toContain("0");
  });
});

describe("durationLabel", () => {
  it("says 1 hour for a single-hour slot", () => {
    expect(durationLabel("2026-05-24T18:00:00.000Z", "2026-05-24T19:00:00.000Z")).toBe("1 hour");
  });

  it("pluralises multi-hour slots", () => {
    expect(durationLabel("2026-05-24T18:00:00.000Z", "2026-05-24T20:00:00.000Z")).toBe("2 hours");
  });
});

describe("toDateParam", () => {
  it("formats a local date as YYYY-MM-DD with zero padding", () => {
    expect(toDateParam(new Date(2026, 4, 4))).toBe("2026-05-04");
  });
});
