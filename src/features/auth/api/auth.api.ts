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

/**
 * profiles.onboarding_completed is the fast, normal-path signal, but it's
 * only ever written by the complete_facility_setup RPC — a client that (by
 * bug, or a future new completion path) writes facilities.onboarding_step
 * directly instead would leave it stuck at false forever, sending an
 * already-onboarded owner back into onboarding on every sign-in. Treating
 * either signal as authoritative makes that class of bug self-healing
 * instead of a permanent lockout.
 */
async function hasCompletedFacility(supabase: SupabaseClient<Database>, userId: string): Promise<boolean> {
  const { data } = await supabase
    .from("facilities")
    .select("id")
    .eq("owner_id", userId)
    .eq("onboarding_step", "COMPLETED")
    .limit(1)
    .maybeSingle();
  return Boolean(data);
}

/** Profile joined with the auth facts the UI needs (verification state). */
export const getCurrentAuthUser = cache(async (): Promise<AuthUser | null> => {
  const { supabase, user } = await getAuthenticatedUser();
  if (!user) return null;

  const profile = await getCurrentProfile();
  const onboardingCompleted =
    (profile?.onboarding_completed ?? false) || (await hasCompletedFacility(supabase, user.id));

  return {
    id: user.id,
    email: user.email ?? "",
    name: profile?.full_name ?? (user.user_metadata?.full_name as string | undefined) ?? "",
    emailVerified: Boolean(user.email_confirmed_at),
    onboardingCompleted,
  };
});

export async function signOut(supabase: SupabaseClient<Database>): Promise<void> {
  const { error } = await supabase.auth.signOut();
  if (error) throw new Error(error.message);
}

/** The signed-in user's active facility, their role there, and the permission
 *  keys they hold — resolved through facility_users (owner OR active staff
 *  assignment), never ownership. The database (has_permission + RLS) stays
 *  authoritative; this only lets server components and the nav hide what the
 *  user cannot use. */
export interface FacilityContext {
  facilityId: string;
  facilityName: string;
  baseRole: "owner" | "manager" | "staff";
  permissions: string[];
}

export const getFacilityContext = cache(async (): Promise<FacilityContext | null> => {
  const { supabase, user } = await getAuthenticatedUser();
  if (!user) return null;

  // RLS on facilities scopes this to the user's own facilities (ACTIVE only).
  const { data: facilities } = await supabase
    .from("facilities")
    .select("id, name, owner_id")
    .order("created_at", { ascending: true });
  const facility =
    (facilities ?? []).find((f) => f.owner_id === user.id) ?? facilities?.[0] ?? null;
  if (!facility) return null;

  // Neither call depends on the other's result, only on facility.id.
  const [{ data: assignment }, { data: permissions }] = await Promise.all([
    supabase
      .from("facility_users")
      .select("role")
      .eq("facility_id", facility.id)
      .eq("user_id", user.id)
      .maybeSingle(),
    supabase.rpc("my_facility_permissions", { p_facility: facility.id }),
  ]);

  return {
    facilityId: facility.id,
    facilityName: facility.name,
    baseRole: (assignment?.role ?? (facility.owner_id === user.id ? "owner" : "staff")) as
      | "owner"
      | "manager"
      | "staff",
    permissions: permissions ?? [],
  };
});