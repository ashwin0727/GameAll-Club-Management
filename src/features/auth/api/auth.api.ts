import { cache } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/server";
import type { Database } from "@/types/database.types";
import type { AuthUser, Profile } from "@/features/auth/types";
import { toPlanSnapshot } from "@/features/plans/plans";
import type { PlanSnapshot } from "@/features/plans/types";

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
export const getAuthenticatedUser = cache(async () => {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  return { supabase, user };
});

/**
 * Everything the app needs about the signed-in person in ONE database call (get_session_bundle, migration 0164): profile, facility,
 * role, permissions, plan and whether they are the platform admin. getCurrentProfile, getFacilityContext and the admin check all read
 * from it, so a page load makes one request instead of three or four. Null when the function is not there yet (the migration has
 * not been applied), in which case each of them falls back to its own queries.
 */
interface SessionBundle {
  profile: Profile | null;
  facility: { id: string; name: string; owner_id: string } | null;
  baseRole: "owner" | "manager" | "staff" | null;
  permissions: string[];
  plan: Record<string, unknown> | null;
  isPlatformAdmin: boolean;
}

const getSessionBundle = cache(async (): Promise<SessionBundle | null> => {
  const { supabase, user } = await getAuthenticatedUser();
  if (!user) return null;
  const { data, error } = await (supabase.rpc as unknown as (fn: string) => Promise<{ data: SessionBundle | null; error: unknown }>).call(
    supabase,
    "get_session_bundle",
  );
  if (error || !data || typeof data !== "object" || !("isPlatformAdmin" in data)) return null;
  return data;
});

export const getCurrentProfile = cache(async (): Promise<Profile | null> => {
  const { supabase, user } = await getAuthenticatedUser();
  if (!user) return null;

  const bundle = await getSessionBundle();
  if (bundle) return bundle.profile;

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
  if (data) return true;
  // A staff member added by an owner has no facility of their own and nothing to set up: they belong to one already.
  const { data: assignment } = await supabase
    .from("facility_users")
    .select("facility_id")
    .eq("user_id", userId)
    .eq("status", "ACTIVE")
    .limit(1)
    .maybeSingle();
  return Boolean(assignment);
}

/** Whether the signed-in user is GameAll's platform admin (the database decides; see migration 0160). */
export async function checkPlatformAdmin(supabase: SupabaseClient<Database>): Promise<boolean> {
  const { data, error } = await (supabase.rpc as unknown as (fn: string) => Promise<{ data: boolean | null; error: unknown }>).call(
    supabase,
    "is_platform_admin",
  );
  return !error && data === true;
}

/** Whether the signed-in person is the platform admin — read from the session bundle, so it costs no extra request. */
export const getIsPlatformAdmin = cache(async (): Promise<boolean> => {
  const { supabase, user } = await getAuthenticatedUser();
  if (!user) return false;
  const bundle = await getSessionBundle();
  return bundle ? bundle.isPlatformAdmin : checkPlatformAdmin(supabase);
});

/** Profile joined with the auth facts the UI needs (verification state). */
export const getCurrentAuthUser = cache(async (): Promise<AuthUser | null> => {
  const { supabase, user } = await getAuthenticatedUser();
  if (!user) return null;

  const profile = await getCurrentProfile();
  const onboardingCompleted =
    (profile?.onboarding_completed ?? false) || (await hasCompletedFacility(supabase, user.id));

  const isPlatformAdmin = await getIsPlatformAdmin();

  let mobileVerificationPending = false;
  if (user.user_metadata?.require_mobile === true) {
    const { data: verified } = await supabase.from("user_verified_phones" as never).select("user_id").eq("user_id", user.id).maybeSingle();
    mobileVerificationPending = !verified;
  }

  return {
    id: user.id,
    email: user.email ?? "",
    name: profile?.full_name ?? (user.user_metadata?.full_name as string | undefined) ?? "",
    emailVerified: Boolean(user.email_confirmed_at),
    onboardingCompleted,
    mobileVerificationPending,
    isPlatformAdmin,
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
  /** The club's plan; null = none chosen yet, which leaves every page open. */
  plan: PlanSnapshot | null;
}

export const getFacilityContext = cache(async (): Promise<FacilityContext | null> => {
  const { supabase, user } = await getAuthenticatedUser();
  if (!user) return null;

  const bundle = await getSessionBundle();
  if (bundle) {
    if (!bundle.facility) return null;
    return {
      facilityId: bundle.facility.id,
      facilityName: bundle.facility.name,
      baseRole: bundle.baseRole ?? (bundle.facility.owner_id === user.id ? "owner" : "staff"),
      permissions: bundle.permissions ?? [],
      plan: toPlanSnapshot(bundle.plan),
    };
  }

  // RLS on facilities scopes this to the user's own facilities (ACTIVE only).
  const { data: facilities } = await supabase
    .from("facilities")
    .select("id, name, owner_id")
    .order("created_at", { ascending: true });
  const facility =
    (facilities ?? []).find((f) => f.owner_id === user.id) ?? facilities?.[0] ?? null;
  if (!facility) return null;

  // Neither call depends on the other's result, only on facility.id.
  const [{ data: assignment }, { data: permissions }, { data: plan }] = await Promise.all([
    supabase
      .from("facility_users")
      .select("role")
      .eq("facility_id", facility.id)
      .eq("user_id", user.id)
      .maybeSingle(),
    supabase.rpc("my_facility_permissions", { p_facility: facility.id }),
    // Newer than the generated types; an error (e.g. migration 0157 not applied yet) reads as "no plan" = unrestricted.
    (supabase.rpc as unknown as (fn: string, args: object) => Promise<{ data: Record<string, unknown> | null }>).call(
      supabase,
      "my_facility_plan",
      { p_facility_id: facility.id },
    ),
  ]);

  return {
    facilityId: facility.id,
    facilityName: facility.name,
    baseRole: (assignment?.role ?? (facility.owner_id === user.id ? "owner" : "staff")) as
      | "owner"
      | "manager"
      | "staff",
    permissions: permissions ?? [],
    plan: toPlanSnapshot(plan),
  };
});
/**
 * Whether the person may use the dashboard shell at all: an owner / admin / staff profile, or anyone assigned to a facility
 * (staff created by an owner carry the plain "member" profile role). What they can open inside is decided per page by
 * the page-access matrix (RouteGuard in the UI, has_permission in the database).
 */
export async function hasDashboardAccess(profile: Profile): Promise<boolean> {
  if (profile.role === "admin" || profile.role === "staff") return true;
  return (await getFacilityContext()) !== null;
}
