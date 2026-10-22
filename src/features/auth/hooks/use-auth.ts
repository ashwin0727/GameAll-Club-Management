"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useRouter } from "next/navigation";
import { getAuthService } from "@/services/auth";
import type { AuthUser } from "@/features/auth/types";
import type {
  ChangeEmailInput,
  ForgotPasswordInput,
  LoginInput,
  SignupInput,
} from "@/features/auth/validation";
import { markDeviceOnboarded } from "@/lib/storage/onboarding";
import { useOnboardingStore } from "@/features/onboarding/state/onboarding-store";

const CURRENT_USER_KEY = ["auth", "current-user"] as const;

export function useCurrentUser() {
  return useQuery<AuthUser | null>({
    queryKey: CURRENT_USER_KEY,
    queryFn: () => getAuthService().getCurrentUser(),
    // The session rarely changes mid-visit, and every page that reads it
    // (layouts, guards, forms) would otherwise trigger its own
    // auth.getUser() + profiles round trip on every mount/refocus.
    staleTime: 5 * 60_000,
  });
}

export function useSignup() {
  const router = useRouter();

  return useMutation({
    mutationFn: (input: SignupInput) => getAuthService().register(input),
    onSuccess: (result) => {
      // This device has an account now, so a later cold start opens on Login
      // rather than the first-run Welcome pitch.
      markDeviceOnboarded();
      if (result.sessionActive) {
        // A brand-new account can never have completed onboarding yet.
        router.replace("/onboarding/facility");
        router.refresh();
        return;
      }
      router.push(`/verify-email?email=${encodeURIComponent(result.email)}`);
    },
  });
}

/**
 * Completes signup: verifies the emailed 6-digit code, then signs the new owner in with the password they just chose
 * and sends them to onboarding. If the password is no longer in memory (page reload), the verified account is sent to
 * Sign In instead.
 */
export function useVerifySignup() {
  const router = useRouter();
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async ({ email, code, password }: { email: string; code: string; password?: string }) => {
      const auth = getAuthService();
      await auth.verifySignupCode(email, code);
      return password ? auth.login({ email, password }) : null;
    },
    onSuccess: (user, { email }) => {
      if (!user) {
        router.replace(`/login?verified=1&email=${encodeURIComponent(email)}`);
        return;
      }
      markDeviceOnboarded();
      queryClient.setQueryData(CURRENT_USER_KEY, user);
      router.replace(user.onboardingCompleted ? "/dashboard" : "/onboarding/facility");
      router.refresh();
    },
  });
}

export function useLogin() {
  const router = useRouter();
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (input: LoginInput) => getAuthService().login(input),
    onSuccess: async (user) => {
      markDeviceOnboarded();
      queryClient.setQueryData(CURRENT_USER_KEY, user);
      router.replace(user.onboardingCompleted ? "/dashboard" : "/onboarding/facility");
      // Server components hold the old (signed-out) session until refreshed.
      router.refresh();
    },
  });
}

export function useLogout() {
  const router = useRouter();
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: () => getAuthService().logout(),
    onSuccess: () => {
      queryClient.clear();
      useOnboardingStore.getState().reset();
      router.replace("/login");
      router.refresh();
    },
  });
}

export function useResendVerification() {
  return useMutation({
    mutationFn: (email: string) => getAuthService().resendVerificationEmail(email),
  });
}

export function useChangeEmail() {
  const router = useRouter();

  return useMutation({
    mutationFn: (input: ChangeEmailInput & { name: string; password: string }) =>
      getAuthService().changeEmail(input),
    onSuccess: (result) => {
      router.replace(`/verify-email?email=${encodeURIComponent(result.email)}`);
    },
  });
}

export function useResetPassword() {
  return useMutation({
    mutationFn: (input: ForgotPasswordInput) => getAuthService().resetPassword(input),
  });
}

export function useUpdatePassword() {
  const router = useRouter();

  return useMutation({
    mutationFn: (password: string) => getAuthService().updatePassword(password),
    onSuccess: () => {
      router.replace("/dashboard");
      router.refresh();
    },
  });
}