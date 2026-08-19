import { cache } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/server";
import type { Database } from "@/types/database.types";
import type { AuthUser, Profile } from "@/features/auth/types";

/**
 * Server-side session reads. Client components go through
 * `@/services/auth` instead — these exist for server components, layouts and
 * route handlers.
 *
 * Each is wrapped in React's `cache()` so a layout and its page (which both
 * commonly need the session) share one Supabase round trip per request
 * instead of each re-authenticating and re-querying the profile — see
 * https://nextjs.org/docs/app/building-your-application/caching#request-memoization
 */
const getAuthenticatedUser = cache(async () => {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  return { supabase, user };
});

export const getCurrentProfile = cache(async (): Promise<Profile | null> => {
  const { supabase, user } = await getAuthenticatedUser();
  if (!user) return null;

  const { data, error } = await supabase
    .from("profiles")
    .select("*")
    .eq("id", user.id)
    .maybeSingle();

  if (error) throw new Error(error.message);
  return data;
});

/** Profile joined with the auth facts the UI needs (verification state). */
export const getCurrentAuthUser = cache(async (): Promise<AuthUser | null> => {
  const { user } = await getAuthenticatedUser();
  if (!user) return null;

  const profile = await getCurrentProfile();

  return {
    id: user.id,
    email: user.email ?? "",
    name: profile?.full_name ?? (user.user_metadata?.full_name as string | undefined) ?? "",
    emailVerified: Boolean(user.email_confirmed_at),
    onboardingCompleted: profile?.onboarding_completed ?? false,
  };
});

export async function signOut(supabase: SupabaseClient<Database>): Promise<void> {
  const { error } = await supabase.auth.signOut();
  if (error) throw new Error(error.message);
}