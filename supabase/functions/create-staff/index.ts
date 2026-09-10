// ═══════════════════════════════════════════════════════════════════════════
// create-staff — add a person to a facility's staff.
//
// AUTHENTICATION ≠ AUTHORIZATION. This runs in two clients:
//   * the caller's own session (anon key + their JWT) — used only to check
//     has_permission(facilityId, 'USERS_CREATE'). RLS still applies.
//   * the service role — used only to create the auth account when the
//     person doesn't have one yet. It never touches facility data directly.
//
// Two paths:
//   1. The email already belongs to a GameAll account → link it: insert one
//      facility_users row (status ACTIVE — they already have a password).
//      No second auth account is ever created (spec §5 / §21 / TEST 8).
//   2. New person → admin.createUser with a random one-time password,
//      email confirmed, must_reset_password = true, facility_users status
//      INVITED. The temp password is returned ONCE and never stored.
//
// Passwords are never written to the GameAll database (spec §2 / §47).
// ═══════════════════════════════════════════════════════════════════════════

import { createClient } from "jsr:@supabase/supabase-js@2";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface CreateStaffRequest {
  facilityId: string;
  fullName: string;
  email: string;
  phone?: string;
  /** A system template id (owner/manager/staff) or a facility custom role id. */
  roleId: string;
  isPrimary?: boolean;
  title?: string;
  notes?: string;
  avatarUrl?: string;
}

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

function tempPassword(): string {
  // 18 url-safe chars from a CSPRNG — enough entropy, easy to read aloud once.
  const bytes = crypto.getRandomValues(new Uint8Array(18));
  return btoa(String.fromCharCode(...bytes)).replace(/[+/=]/g, "").slice(0, 18);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS_HEADERS });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "Not authenticated" }, 401);

  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anonKey || !serviceKey) {
    console.error("[create-staff] missing function secrets");
    return json({ error: "This action is not configured yet." }, 500);
  }

  let body: CreateStaffRequest;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid request body." }, 400);
  }

  const email = (body.email ?? "").trim().toLowerCase();
  const fullName = (body.fullName ?? "").trim();
  if (!body.facilityId || !email || !fullName || !body.roleId) {
    return json({ error: "Facility, name, email and role are all required." }, 400);
  }
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return json({ error: "Enter a valid email address." }, 400);
  }

  // ── 1. Authorize the caller against the facility (their own session). ──
  const asCaller = createClient(url, anonKey, { global: { headers: { Authorization: authHeader } } });
  const { data: allowed, error: permError } = await asCaller.rpc("has_permission", {
    p_facility: body.facilityId,
    p_permission: "USERS_CREATE",
  });
  if (permError) {
    console.error("[create-staff] permission check failed", permError.message);
    return json({ error: "Could not verify your permissions." }, 500);
  }
  if (!allowed) return json({ error: "You don't have permission to add staff." }, 403);

  // Validate the role belongs to this facility (or is a system template).
  const { data: role } = await asCaller
    .from("roles")
    .select("id, facility_id, base_role, is_system, is_template")
    .eq("id", body.roleId)
    .maybeSingle();
  if (!role || role.is_template || (role.facility_id && role.facility_id !== body.facilityId)) {
    return json({ error: "Choose a valid role." }, 400);
  }

  // ── 2. Service-role work: find or create the auth account. ──
  const admin = createClient(url, serviceKey, { auth: { autoRefreshToken: false, persistSession: false } });

  const { data: existingProfile } = await admin
    .from("profiles")
    .select("id")
    .eq("email", email)
    .maybeSingle();

  let userId: string;
  let generatedPassword: string | null = null;
  let status: "ACTIVE" | "INVITED";

  if (existingProfile) {
    userId = existingProfile.id;
    status = "ACTIVE";
    const { data: dupe } = await admin
      .from("facility_users")
      .select("facility_id")
      .eq("facility_id", body.facilityId)
      .eq("user_id", userId)
      .maybeSingle();
    if (dupe) return json({ error: "That person already has access to this facility." }, 409);
  } else {
    generatedPassword = tempPassword();
    const { data: created, error: createError } = await admin.auth.admin.createUser({
      email,
      password: generatedPassword,
      email_confirm: true,
      user_metadata: { full_name: fullName },
    });
    if (createError || !created.user) {
      console.error("[create-staff] createUser failed", createError?.message);
      return json({ error: "Could not create the staff account. Please try again." }, 500);
    }
    userId = created.user.id;
    status = "INVITED";
    // The handle_new_user trigger has seeded the profile row; force a reset
    // and fill in the extras the trigger doesn't know about.
    await admin
      .from("profiles")
      .update({
        full_name: fullName,
        phone: body.phone?.trim() || null,
        avatar_url: body.avatarUrl?.trim() || null,
        must_reset_password: true,
      })
      .eq("id", userId);
  }

  // ── 3. The facility assignment (service role — the RLS insert policy
  //       only allows an owner/manager, and we've already checked
  //       USERS_CREATE which a custom role may hold instead). ──
  const { error: assignError } = await admin.from("facility_users").insert({
    facility_id: body.facilityId,
    user_id: userId,
    role: role.base_role ?? "staff",
    role_id: role.is_system ? null : role.id,
    status,
    is_primary: body.isPrimary ?? false,
    title: body.title?.trim() || null,
    notes: body.notes?.trim() || null,
    invited_by: (await asCaller.auth.getUser()).data.user?.id ?? null,
    invited_at: new Date().toISOString(),
    activated_at: status === "ACTIVE" ? new Date().toISOString() : null,
  });
  if (assignError) {
    console.error("[create-staff] facility_users insert failed", assignError.message);
    return json({ error: "Could not assign the staff member to this facility." }, 500);
  }

  if (body.isPrimary) {
    await admin.from("facility_users").update({ is_primary: false }).eq("user_id", userId).neq("facility_id", body.facilityId);
  }

  await asCaller.rpc("log_security_event", {
    p_facility_id: body.facilityId,
    p_event: existingProfile ? "STAFF_LINKED" : "STAFF_INVITED",
    p_summary: existingProfile ? `${fullName} linked to this facility` : `${fullName} invited`,
    p_target_user_id: userId,
    p_target_role_id: role.id,
    p_detail: {},
  });

  return json(
    {
      userId,
      linked: Boolean(existingProfile),
      // Returned ONCE. The administrator gives it to the new staff member,
      // who must change it on first sign-in. Never persisted anywhere.
      temporaryPassword: generatedPassword,
    },
    200,
  );
});
