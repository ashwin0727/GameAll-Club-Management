import { describe, expect, it } from "vitest";
import {
  evaluatePasswordStrength,
  forgotPasswordSchema,
  loginSchema,
  signupSchema,
} from "@/features/auth/validation";

const valid = {
  name: "Ravi Kumar",
  email: "owner@example.com",
  password: "TurfCourt2026",
  confirmPassword: "TurfCourt2026",
};

function firstError(result: ReturnType<typeof signupSchema.safeParse>, path: string) {
  if (result.success) return null;
  return result.error.issues.find((issue) => issue.path[0] === path)?.message ?? null;
}

describe("signupSchema", () => {
  it("accepts a complete, valid signup", () => {
    const result = signupSchema.safeParse(valid);
    expect(result.success).toBe(true);
  });

  it("rejects an empty name", () => {
    const result = signupSchema.safeParse({ ...valid, name: "" });
    expect(firstError(result, "name")).toBe("Enter your full name");
  });

  it.each(["owner@", "owner.com", "owner example.com", "owner@example", "@example.com"])(
    "rejects the invalid email %s",
    (email) => {
      const result = signupSchema.safeParse({ ...valid, email });
      expect(result.success).toBe(false);
      expect(firstError(result, "email")).toBeTruthy();
    },
  );

  it("normalises email casing and surrounding space", () => {
    const result = signupSchema.safeParse({ ...valid, email: "  Owner@Example.COM " });
    expect(result.success && result.data.email).toBe("owner@example.com");
  });

  it("rejects a password under 8 characters", () => {
    const result = signupSchema.safeParse({ ...valid, password: "Turf12", confirmPassword: "Turf12" });
    expect(firstError(result, "password")).toBe("Password must be at least 8 characters");
  });

  it("rejects a mismatched confirmation", () => {
    const result = signupSchema.safeParse({ ...valid, confirmPassword: "TurfCourt2027" });
    expect(firstError(result, "confirmPassword")).toBe("Passwords do not match");
  });
});

describe("loginSchema", () => {
  it("accepts any non-empty password so the stored shape is never hinted at", () => {
    const result = loginSchema.safeParse({ email: "owner@example.com", password: "x" });
    expect(result.success).toBe(true);
  });

  it("requires a password", () => {
    const result = loginSchema.safeParse({ email: "owner@example.com", password: "" });
    expect(result.success).toBe(false);
  });
});

describe("forgotPasswordSchema", () => {
  it("rejects an empty email", () => {
    const result = forgotPasswordSchema.safeParse({ email: "" });
    expect(result.success).toBe(false);
  });

  it("rejects an invalid email", () => {
    expect(forgotPasswordSchema.safeParse({ email: "owner@" }).success).toBe(false);
  });

  it("accepts a valid email", () => {
    expect(forgotPasswordSchema.safeParse({ email: "owner@example.com" }).success).toBe(true);
  });
});

describe("evaluatePasswordStrength", () => {
  it("reports nothing for an empty value", () => {
    expect(evaluatePasswordStrength("").strength).toBe("empty");
  });

  it("rates a short password weak", () => {
    expect(evaluatePasswordStrength("turf12").strength).toBe("weak");
  });

  it("rates a single-character-class password weak", () => {
    expect(evaluatePasswordStrength("turfturfturf").strength).toBe("weak");
  });

  it("rates a long mixed password medium", () => {
    expect(evaluatePasswordStrength("turfcourt1").strength).toBe("medium");
  });

  it("rates a long, varied password strong", () => {
    const result = evaluatePasswordStrength("TurfCourt2026!");
    expect(result.strength).toBe("strong");
    expect(result.hint).toBeNull();
  });
});