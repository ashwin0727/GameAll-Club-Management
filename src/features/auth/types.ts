import { z } from "zod";
import type { Role } from "@/types/database.types";

export const profileSchema = z.object({
  id: z.string().uuid(),
  full_name: z.string().min(1),
  email: z.string(),
  avatar_url: z.string().url().nullable(),
  role: z.enum(["admin", "staff", "member"]),
  phone: z.string().nullable(),
  onboarding_completed: z.boolean(),
  created_at: z.string(),
});

export type Profile = z.infer<typeof profileSchema>;
export type { Role };

/**
 * The authenticated account as the UI knows it: a flattened view of the Supabase
 * auth user joined to its profile row. Deliberately free of anything secret —
 * no password, no access token.
 */
export interface AuthUser {
  id: string;
  name: string;
  email: string;
  emailVerified: boolean;
  onboardingCompleted: boolean;
}

/** Where the splash screen sends the visitor once session state is known. */
export type EntryRoute = "/welcome" | "/login" | "/dashboard" | "/onboarding/facility";