import { describe, expect, it } from "vitest";
import { otherSportNameSchema } from "@/features/sports-setup/validation";

describe("otherSportNameSchema", () => {
  it("accepts a valid trimmed name", () => {
    expect(otherSportNameSchema.safeParse("Basketball").success).toBe(true);
  });

  it("trims surrounding whitespace before validating length", () => {
    const result = otherSportNameSchema.safeParse("  Go  ");
    expect(result.success).toBe(true);
    if (result.success) expect(result.data).toBe("Go");
  });

  it("rejects an empty name", () => {
    expect(otherSportNameSchema.safeParse("").success).toBe(false);
  });

  it("rejects a whitespace-only name", () => {
    expect(otherSportNameSchema.safeParse("   ").success).toBe(false);
  });

  it("rejects a name under 2 characters", () => {
    expect(otherSportNameSchema.safeParse("A").success).toBe(false);
  });

  it("rejects a name over 50 characters", () => {
    expect(otherSportNameSchema.safeParse("a".repeat(51)).success).toBe(false);
  });

  it("accepts a name at exactly 50 characters", () => {
    expect(otherSportNameSchema.safeParse("a".repeat(50)).success).toBe(true);
  });
});