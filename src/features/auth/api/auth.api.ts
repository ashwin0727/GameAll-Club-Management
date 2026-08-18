import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/types/database.types";
import type { AuthUser, Profile } from "@/features/auth/types";

/**
 * Server-side session reads. Client components go through
 * `@/services/auth` instead — these exist for server components, layouts and
 * route handlers, which hold their own request-scoped Supabase client.
 */
export async function getCurrentProfile(
  supabase: SupabaseClient<Database>,
): Promise<Profile | null> {
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const { data, error } = await supabase
    .from("profiles")
    .select("*")
    .eq("id", user.id)
    .maybeSingle();

  if (error) throw new Error(error.message);
  return data;
}

/** Profile joined with the auth facts the UI needs (verification state). */
export async function getCurrentAuthUser(
  supabase: SupabaseClient<Database>,
): Promise<AuthUser | null> {
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const { data: profile } = await supabase
    .from("profiles")
    .select("full_name, onboarding_completed")
    .eq("id", user.id)
    .maybeSingle();

  return {
    id: user.id,
    email: user.email ?? "",
    name: profile?.full_name ?? (user.user_metadata?.full_name as string | undefined) ?? "",
    emailVerified: Boolean(user.email_confirmed_at),
    onboardingCompleted: profile?.onboarding_completed ?? false,
  };
}

export async function signOut(supabase: SupabaseClient<Database>): Promise<void> {
  const { error } = await supabase.auth.signOut();
  if (error) throw new Error(error.message);
}