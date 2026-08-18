import type { AuthUser } from "@/features/auth/types";
import type {
  ChangeEmailInput,
  ForgotPasswordInput,
  LoginInput,
  SignupInput,
} from "@/features/auth/validation";

/**
 * The auth boundary the UI codes against.
 *
 * Screens never import a Supabase client directly — they call these methods, so
 * the provider can change without touching a single component.
 */
export type AuthErrorCode =
  | "invalid_credentials"
  | "email_not_verified"
  | "email_taken"
  | "weak_password"
  | "rate_limited"
  | "expired_link"
  | "network"
  | "unknown";

export class AuthError extends Error {
  readonly code: AuthErrorCode;

  constructor(code: AuthErrorCode, message: string) {
    super(message);
    this.name = "AuthError";
    this.code = code;
  }
}

export interface RegisterResult {
  /** The address the confirmation email went to — shown on /verify-email. */
  email: string;
  /**
   * True when the project has email confirmation switched off and the user is
   * already signed in, so the UI can skip the verification screen.
   */
  sessionActive: boolean;
}

export interface AuthService {
  register(input: SignupInput): Promise<RegisterResult>;
  login(input: LoginInput): Promise<AuthUser>;
  logout(): Promise<void>;
  getCurrentUser(): Promise<AuthUser | null>;
  isEmailVerified(): Promise<boolean>;
  /** Sent automatically by `register`; exposed for explicit re-triggers. */
  sendVerificationEmail(email: string): Promise<void>;
  resendVerificationEmail(email: string): Promise<void>;
  /** Re-issues the signup confirmation against a corrected address. */
  changeEmail(input: ChangeEmailInput & { name: string; password: string }): Promise<RegisterResult>;
  resetPassword(input: ForgotPasswordInput): Promise<void>;
  /** Completes a reset, using the session established by the recovery link. */
  updatePassword(password: string): Promise<void>;
}