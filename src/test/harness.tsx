import * as React from "react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, type RenderResult } from "@testing-library/react";
import { vi } from "vitest";
import { PendingSignupProvider } from "@/features/auth/context/pending-signup";
import { AuthError, type AuthErrorCode, type AuthService } from "@/services/auth/auth.service";
import { setAuthService } from "@/services/auth";

/**
 * A fake AuthService whose methods resolve happily unless a test overrides one.
 * Injected through `setAuthService`, the same seam production code uses to pick
 * its implementation — so no component needs to know it is under test.
 */
export function installFakeAuthService(overrides: Partial<AuthService> = {}): AuthService {
  const service: AuthService = {
    register: vi.fn(async ({ email }) => ({ email, sessionActive: false })),
    login: vi.fn(async ({ email }) => ({
      id: "user-1",
      name: "Ravi Kumar",
      email,
      emailVerified: true,
      onboardingCompleted: true,
    })),
    logout: vi.fn(async () => undefined),
    getCurrentUser: vi.fn(async () => null),
    isEmailVerified: vi.fn(async () => true),
    sendVerificationEmail: vi.fn(async () => undefined),
    resendVerificationEmail: vi.fn(async () => undefined),
    changeEmail: vi.fn(async ({ email }) => ({ email, sessionActive: false })),
    resetPassword: vi.fn(async () => undefined),
    updatePassword: vi.fn(async () => undefined),
    ...overrides,
  };

  setAuthService(service);
  return service;
}

/** Builds a service method that rejects with a real AuthError. */
export function failing(code: AuthErrorCode, message: string) {
  return vi.fn(async () => {
    throw new AuthError(code, message);
  });
}

export function renderWithProviders(ui: React.ReactElement): RenderResult {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  });

  return render(
    <QueryClientProvider client={queryClient}>
      <PendingSignupProvider>{ui}</PendingSignupProvider>
    </QueryClientProvider>,
  );
}