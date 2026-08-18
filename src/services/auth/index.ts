import type { AuthService } from "@/services/auth/auth.service";
import { SupabaseAuthService } from "@/services/auth/supabase-auth.service";

let instance: AuthService | null = null;

/**
 * Single entry point for the auth implementation. Swapping providers, or
 * injecting a fake in tests, happens here and nowhere else.
 */
export function getAuthService(): AuthService {
  instance ??= new SupabaseAuthService();
  return instance;
}

/** Test seam: overrides the singleton for the current module instance. */
export function setAuthService(service: AuthService | null): void {
  instance = service;
}

export { AuthError } from "@/services/auth/auth.service";
export type { AuthService, AuthErrorCode, RegisterResult } from "@/services/auth/auth.service";