import { describe, expect, it } from "vitest";
import {
  isValidAccountNumber,
  isValidGstin,
  isValidIfsc,
  isValidPan,
  isValidRupees,
  isValidSlot,
  isValidUpi,
  findAvailabilityConflict,
  normalizeIfsc,
  normalizePan,
  rupeesToMinor,
  validateCertificateFile,
} from "@/features/coaching/coach-onboarding-validation";

describe("coach onboarding validation", () => {
  it("IFSC is normalised (trim, strip spaces, upper-case) before it is checked", () => {
    expect(isValidIfsc("sbin0001234")).toBe(false);
    expect(isValidIfsc(normalizeIfsc(" sbin 0001234 "))).toBe(true);
    expect(isValidIfsc("SBIN1001234")).toBe(false); // 5th character must be 0
    expect(isValidIfsc("SBIN000123")).toBe(false);
  });

  it("PAN and GSTIN follow their government formats", () => {
    expect(isValidPan("ABCDE1234F")).toBe(true);
    expect(isValidPan(normalizePan(" abcde 1234f "))).toBe(true);
    expect(isValidPan("ABCDE12345")).toBe(false);
    expect(isValidGstin("22ABCDE1234F1Z5")).toBe(true);
    expect(isValidGstin("22ABCDE1234F1X5")).toBe(false);
  });

  it("UPI id needs a handle on both sides of @", () => {
    expect(isValidUpi("name@okhdfc")).toBe(true);
    expect(isValidUpi("name@")).toBe(false);
    expect(isValidUpi("@okhdfc")).toBe(false);
  });

  it("account number is 9 to 18 digits", () => {
    expect(isValidAccountNumber("12345678")).toBe(false);
    expect(isValidAccountNumber("123456789")).toBe(true);
    expect(isValidAccountNumber("1234567890123456789")).toBe(false);
    expect(isValidAccountNumber("12345 6789")).toBe(false);
  });

  it("rupee amounts are positive whole numbers and convert to paise", () => {
    expect(isValidRupees("500")).toBe(true);
    for (const bad of ["0", "-5", "10.5", "", "abc"]) expect(isValidRupees(bad)).toBe(false);
    expect(rupeesToMinor("500")).toBe(50000);
  });

  it("an availability slot must end after it starts", () => {
    expect(isValidSlot("09:00", "09:00")).toBe(false);
    expect(isValidSlot("10:00", "09:00")).toBe(false);
    expect(isValidSlot("09:00", "10:00")).toBe(true);
  });

  it("flags a repeated or overlapping slot on the same day, naming both", () => {
    const w = (dayOfWeek: number, startTime: string, endTime: string) => ({ dayOfWeek, startTime, endTime });
    expect(findAvailabilityConflict([w(1, "09:00", "12:00"), w(2, "09:00", "12:00")])).toBeNull(); // different days
    expect(findAvailabilityConflict([w(1, "09:00", "12:00"), w(1, "12:00", "14:00")])).toBeNull(); // touching is fine
    expect(findAvailabilityConflict([w(1, "09:00", "12:00"), w(1, "09:00", "12:00")])).toMatch(/Mon 09:00–12:00 is added twice/);
    expect(findAvailabilityConflict([w(1, "09:00", "12:00"), w(1, "11:00", "13:00")])).toMatch(/Mon 09:00–12:00 overlaps Mon 11:00–13:00/);
    expect(findAvailabilityConflict([w(1, "11:00", "13:00"), w(3, "08:00", "09:00"), w(1, "09:00", "12:00")])).toMatch(/overlaps/);
    expect(findAvailabilityConflict([w(1, "10:00", "09:00")])).toBeNull(); // a bad slot is reported separately (isValidSlot)
  });

  it("certificate files: JPG/PNG/WEBP/PDF up to 5 MB", () => {
    expect(validateCertificateFile({ type: "application/pdf", size: 6 * 1024 * 1024 })).toMatch(/larger than 5MB/);
    expect(validateCertificateFile({ type: "image/gif", size: 1 })).toMatch(/JPG, PNG, WEBP or PDF/);
    expect(validateCertificateFile({ type: "application/pdf", size: 1024 * 1024 })).toBeNull();
  });
});
