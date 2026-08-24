import { describe, expect, it } from "vitest";
import { validateMemberName, validateMemberPhone } from "./validation";

describe("validateMemberName", () => {
  it("requires a name", () => {
    expect(validateMemberName("")).toBe("Member name is required.");
  });

  it("rejects a single character", () => {
    expect(validateMemberName("A")).toContain("at least 2 characters");
  });

  it("accepts a real name", () => {
    expect(validateMemberName("Arun Kumar")).toBeNull();
  });
});

describe("validateMemberPhone", () => {
  it("requires a mobile number — a Member has no auth account, so phone is the primary identity", () => {
    expect(validateMemberPhone("")).toBe("Mobile number is required.");
  });

  it("rejects an invalid number", () => {
    expect(validateMemberPhone("12345")).toContain("valid 10-digit");
  });

  it("accepts a valid 10-digit Indian mobile number", () => {
    expect(validateMemberPhone("9999999999")).toBeNull();
  });
});