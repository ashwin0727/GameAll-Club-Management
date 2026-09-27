import { describe, expect, it } from "vitest";
import {
  dateOfBirthBounds,
  isValidDateOfBirth,
  isValidEmail,
  isValidPhoneDigits,
  sanitizePhoneDigits,
} from "@/features/coaching/add-coach-validation";

describe("sanitizePhoneDigits", () => {
  it("strips non-digits and caps at 10", () => {
    expect(sanitizePhoneDigits("98765 43210")).toBe("9876543210");
    expect(sanitizePhoneDigits("+91-98765-43210")).toBe("9198765432"); // capped at 10, leading +91 digits counted
    expect(sanitizePhoneDigits("abc123")).toBe("123");
  });
});

describe("isValidPhoneDigits", () => {
  it("accepts empty (optional) and exactly 10 digits", () => {
    expect(isValidPhoneDigits("")).toBe(true);
    expect(isValidPhoneDigits("9876543210")).toBe(true);
  });

  it("rejects anything else", () => {
    expect(isValidPhoneDigits("987654321")).toBe(false); // 9 digits
    expect(isValidPhoneDigits("98765432109")).toBe(false); // would never happen post-sanitize, but guard anyway
  });
});

describe("isValidEmail", () => {
  it("accepts a plausible email", () => {
    expect(isValidEmail("arjun@example.com")).toBe(true);
  });

  it("rejects missing @, missing domain dot, or spaces", () => {
    expect(isValidEmail("arjun.example.com")).toBe(false);
    expect(isValidEmail("arjun@example")).toBe(false);
    expect(isValidEmail("arjun @example.com")).toBe(false);
    expect(isValidEmail("")).toBe(false);
  });
});

describe("isValidDateOfBirth", () => {
  const today = new Date(2026, 8, 26); // 26 Sep 2026

  it("accepts empty (optional)", () => {
    expect(isValidDateOfBirth("", today)).toBe(true);
  });

  it("accepts a real adult birth date", () => {
    expect(isValidDateOfBirth("1995-03-14", today)).toBe(true);
  });

  it("rejects an unparseable date", () => {
    expect(isValidDateOfBirth("not-a-date", today)).toBe(false);
  });

  it("rejects a future date", () => {
    expect(isValidDateOfBirth("2026-12-25", today)).toBe(false);
  });

  it("rejects someone under 18", () => {
    expect(isValidDateOfBirth("2015-01-01", today)).toBe(false);
  });

  it("rejects someone implausibly old (over 100)", () => {
    expect(isValidDateOfBirth("1900-01-01", today)).toBe(false);
  });

  it("accepts exactly the 18-year boundary", () => {
    expect(isValidDateOfBirth("2008-09-26", today)).toBe(true);
  });
});

describe("dateOfBirthBounds", () => {
  it("returns a min 100 years back and a max 18 years back", () => {
    const today = new Date(2026, 8, 26);
    const bounds = dateOfBirthBounds(today);
    expect(bounds.min).toBe("1926-09-26");
    expect(bounds.max).toBe("2008-09-26");
  });
});
