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

const CURRENT_USER_KEY = ["auth", "current-user"] as const;

export function useCurrentUser() {
  return useQuery<AuthUser | null>({
    queryKey: CURRENT_USER_KEY,
    queryFn: () => getAuthService().getCurrentUser(),
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