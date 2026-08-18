import { z } from "zod";

/**
 * Single source of truth for auth validation.
 *
 * Every schema here is used twice: once by the React form (inline, as the user
 * types) and once by the route handler that backs it. The server never trusts
 * the client's copy — it re-parses the payload with the same schema.
 */

export const MIN_PASSWORD_LENGTH = 8;

/**
 * Pragmatic email check. Stricter than `z.string().email()` on the cases turf
 * owners actually mistype: a missing TLD (`owner@example`), a trailing dot, or
 * a space in the local part.
 */
export const emailSchema = z
  .string()
  .trim()
  .min(1, "Email address is required")
  .max(254, "Email address is too long")
  .toLowerCase()
  .regex(
    /^[^\s@]+@[^\s@.]+(\.[^\s@.]+)+$/,
    "Enter a valid email address, like owner@example.com",
  );

export const nameSchema = z
  .string()
  .trim()
  .min(2, "Enter your full name")
  .max(80, "Name is too long");

export const passwordSchema = z
  .string()
  .min(MIN_PASSWORD_LENGTH, `Password must be at least ${MIN_PASSWORD_LENGTH} characters`)
  .max(128, "Password is too long");

export const signupSchema = z
  .object({
    name: nameSchema,
    email: emailSchema,
    password: passwordSchema,
    confirmPassword: z.string().min(1, "Confirm your password"),
  })
  .refine((values) => values.password === values.confirmPassword, {
    path: ["confirmPassword"],
    message: "Passwords do not match",
  });

export const loginSchema = z.object({
  email: emailSchema,
  // Length rules are a signup concern; at login any non-empty value is submitted
  // so we never hint at the stored password's shape.
  password: z.string().min(1, "Password is required"),
});

export const forgotPasswordSchema = z.object({
  email: emailSchema,
});

export const changeEmailSchema = z.object({
  email: emailSchema,
});

export const resendVerificationSchema = z.object({
  email: emailSchema,
});

export type SignupInput = z.infer<typeof signupSchema>;
export type LoginInput = z.infer<typeof loginSchema>;
export type ForgotPasswordInput = z.infer<typeof forgotPasswordSchema>;
export type ChangeEmailInput = z.infer<typeof changeEmailSchema>;

export type PasswordStrength = "empty" | "weak" | "medium" | "strong";

export interface PasswordStrengthResult {
  strength: PasswordStrength;
  /** 0–3, for the meter segments. */
  score: number;
  label: string;
  /** The single most useful next improvement, or null when strong. */
  hint: string | null;
}

/**
 * Scores a password for the strength meter only — it never gates submission.
 * The hard rule is the {@link MIN_PASSWORD_LENGTH} minimum in `passwordSchema`.
 */
export function evaluatePasswordStrength(password: string): PasswordStrengthResult {
  if (!password) {
    return { strength: "empty", score: 0, label: "", hint: null };
  }

  const hasLower = /[a-z]/.test(password);
  const hasUpper = /[A-Z]/.test(password);
  const hasDigit = /\d/.test(password);
  const hasSymbol = /[^A-Za-z0-9]/.test(password);
  const variety = [hasLower, hasUpper, hasDigit, hasSymbol].filter(Boolean).length;

  if (password.length < MIN_PASSWORD_LENGTH) {
    return {
      strength: "weak",
      score: 1,
      label: "Weak",
      hint: `Use at least ${MIN_PASSWORD_LENGTH} characters`,
    };
  }

  if (password.length >= 12 && variety >= 3) {
    return { strength: "strong", score: 3, label: "Strong", hint: null };
  }

  if (variety >= 2) {
    return {
      strength: "medium",
      score: 2,
      label: "Medium",
      hint:
        password.length < 12
          ? "Longer passwords are harder to guess — try 12+ characters"
          : "Add a number or symbol to strengthen it",
    };
  }

  return {
    strength: "weak",
    score: 1,
    label: "Weak",
    hint: "Mix uppercase, lowercase and numbers",
  };
}