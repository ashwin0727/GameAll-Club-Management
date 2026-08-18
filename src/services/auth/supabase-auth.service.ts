"use client";

import type { AuthError as SupabaseAuthError, SupabaseClient } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";
import type { AuthUser } from "@/features/auth/types";
import type {
  ChangeEmailInput,
  ForgotPasswordInput,
  LoginInput,
  SignupInput,
} from "@/features/auth/validation";
import {
  AuthError,
  type AuthErrorCode,
  type AuthService,
  type RegisterResult,
} from "@/services/auth/auth.service";
import type { Database } from "@/types/database.types";

/** Where Supabase sends the user after they click a link in an email. */
function callbackUrl(next: string): string {
  const origin =
    typeof window !== "undefined"
      ? window.location.origin
      : (process.env.NEXT_PUBLIC_SITE_URL ?? "http://localhost:3000");
  return `${origin}/auth/callback?next=${encodeURIComponent(next)}`;
}

/**
 * Supabase's messages are written for developers. Users get ours instead —
 * and the mapping lives in exactly one place so wording stays consistent.
 */
function toAuthError(error: SupabaseAuthError | Error): AuthError {
  const message = error.message ?? "";
  const status = "status" in error ? error.status : undefined;

  const map: [RegExp, AuthErrorCode, string][] = [
    [
      /invalid login credentials|invalid_credentials/i,
      "invalid_credentials",
      "Invalid email or password.",
    ],
    [
      /email not confirmed|email_not_confirmed/i,
      "email_not_verified",
      "Please verify your email before signing in.",
    ],
    [
      /already registered|already been registered|user_already_exists/i,
      "email_taken",
      "An account already exists for this email address.",
    ],
    [
      /password should be|weak_password/i,
      "weak_password",
      "That password is too weak. Try a longer one.",
    ],
    [
      /rate limit|too many requests|over_email_send_rate_limit/i,
      "rate_limited",
      "Too many attempts. Please wait a moment and try again.",
    ],
    [
      /expired|invalid.*token|otp_expired/i,
      "expired_link",
      "That link has expired. Request a new one.",
    ],
    [/fetch failed|network|failed to fetch/i, "network", "Network error. Check your connection and try again."],
  ];

  for (const [pattern, code, friendly] of map) {
    if (pattern.test(message)) return new AuthError(code, friendly);
  }

  if (status === 429) {
    return new AuthError("rate_limited", "Too many attempts. Please wait a moment and try again.");
  }

  return new AuthError("unknown", "Something went wrong. Please try again.");
}

export class SupabaseAuthService implements AuthService {
  private readonly supabase: SupabaseClient<Database>;

  constructor(client?: SupabaseClient<Database>) {
    this.supabase = client ?? createClient();
  }

  async register({ name, email, password }: SignupInput): Promise<RegisterResult> {
    const { data, error } = await this.supabase.auth.signUp({
      email,
      password,
      options: {
        // Consumed by the handle_new_user trigger to seed the profile row.
        data: { full_name: name, account_type: "owner" },
        emailRedirectTo: callbackUrl("/login?verified=1"),
      },
    });

    if (error) throw toAuthError(error);

    // Supabase does not error on a duplicate signup — it returns a user with no
    // identities so an attacker cannot enumerate addresses. We surface it,
    // because the person in front of us genuinely needs to know to sign in.
    if (data.user && data.user.identities?.length === 0) {
      throw new AuthError(
        "email_taken",
        "An account already exists for this email address. Sign in instead.",
      );
    }

    return { email, sessionActive: Boolean(data.session) };
  }

  async login({ email, password }: LoginInput): Promise<AuthUser> {
    const { data, error } = await this.supabase.auth.signInWithPassword({ email, password });
    if (error) throw toAuthError(error);
    if (!data.user) throw new AuthError("unknown", "Sign in failed. Please try again.");

    const user = await this.getCurrentUser();
    if (!user) throw new AuthError("unknown", "Sign in failed. Please try again.");
    return user;
  }

  async logout(): Promise<void> {
    const { error } = await this.supabase.auth.signOut();
    if (error) throw toAuthError(error);
  }

  async getCurrentUser(): Promise<AuthUser | null> {
    const {
      data: { user },
    } = await this.supabase.auth.getUser();
    if (!user) return null;

    const { data: profile } = await this.supabase
      .from("profiles")
      .select("full_name, onboarding_completed")
      .eq("id", user.id)
      .maybeSingle();

    return {
      id: user.id,
      email: user.email ?? "",
      // The trigger fills the profile, but a just-created row can lag the first
      // read; fall back to the signup metadata rather than rendering blank.
      name: profile?.full_name ?? (user.user_metadata?.full_name as string | undefined) ?? "",
      emailVerified: Boolean(user.email_confirmed_at),
      onboardingCompleted: profile?.onboarding_completed ?? false,
    };
  }

  async isEmailVerified(): Promise<boolean> {
    const {
      data: { user },
    } = await this.supabase.auth.getUser();
    return Boolean(user?.email_confirmed_at);
  }

  async sendVerificationEmail(email: string): Promise<void> {
    const { error } = await this.supabase.auth.resend({
      type: "signup",
      email,
      options: { emailRedirectTo: callbackUrl("/login?verified=1") },
    });
    if (error) throw toAuthError(error);
  }

  async resendVerificationEmail(email: string): Promise<void> {
    await this.sendVerificationEmail(email);
  }

  async changeEmail({ name, email, password }: ChangeEmailInput & { name: string; password: string }) {
    // Before confirmation there is no session to update, so the corrected
    // address is registered as a fresh signup. The abandoned unconfirmed row
    // expires on Supabase's side.
    return this.register({ name, email, password, confirmPassword: password });
  }

  async resetPassword({ email }: ForgotPasswordInput): Promise<void> {
    const { error } = await this.supabase.auth.resetPasswordForEmail(email, {
      redirectTo: callbackUrl("/reset-password"),
    });
    // A missing account must look identical to a real one, so only infra
    // failures surface here.
    if (error && !/user not found/i.test(error.message)) throw toAuthError(error);
  }

  async updatePassword(password: string): Promise<void> {
    const { error } = await this.supabase.auth.updateUser({ password });
    if (error) throw toAuthError(error);
  }
}