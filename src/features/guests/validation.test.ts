import { describe, expect, it } from "vitest";
import { normalizePhone, validateGuestName, validateGuestPhone } from "@/features/guests/validation";

describe("validateGuestName", () => {
  it("rejects an empty name", () => expect(validateGuestName("")).not.toBeNull());
  it("rejects a single-character name", () => expect(validateGuestName("A")).not.toBeNull());
  it("accepts a real name", () => expect(validateGuestName("Arun")).toBeNull());
});

describe("validateGuestPhone", () => {
  it("is optional — null/empty is valid", () => {
    expect(validateGuestPhone(null)).toBeNull();
    expect(validateGuestPhone("")).toBeNull();
  });
  it("rejects a number that isn't 10 digits", () => expect(validateGuestPhone("98765")).not.toBeNull());
  it("rejects a number starting with an invalid digit", () => expect(validateGuestPhone("1234567890")).not.toBeNull());
  it("accepts a valid 10-digit mobile number", () => expect(validateGuestPhone("9876543210")).toBeNull());
});

describe("normalizePhone", () => {
  it("strips all non-digit characters", () => expect(normalizePhone("+91 98765-43210")).toBe("919876543210"));
  it("returns empty string for null/undefined", () => {
    expect(normalizePhone(null)).toBe("");
    expect(normalizePhone(undefined)).toBe("");
  });
});