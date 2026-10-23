// ═══════════════════════════════════════════════════════════════════════════
// create-staff — add a person to a facility's staff, and reset a staff member's password.
//
// AUTHENTICATION ≠ AUTHORIZATION. This runs in two clients:
//   * the caller's own session (anon key + their JWT) — used only to check has_permission(facilityId, …). RLS still
//     applies.
//   * the service role — used only to create / update the auth account. It never touches facility data directly.
//
// Staff do NOT sign in with their own email. Every new account gets a generated login
//     <first name><DDMM of joining><MMSS of creation>@gameall.co
// and a default password
//     <Facility full name>@<HH:MM:SS>
// (date/time in the facility's timezone). The email the owner types is stored as a contact email only
// (profiles.contact_email). The account is flagged must_reset_password, so the staff member picks their own password on
// first sign-in.
//
// Actions (POST JSON):
//   (default)               create — body: facilityId, firstName, lastName, email (contact), phone?, roleId, …
//                           → { userId, loginEmail, temporaryPassword, linked: false }, shown to the owner ONCE.
//   action: "reset-password"  body: facilityId, userId → sets a NEW default password (the old one stops working at once)
//                           and returns it to the owner. Needs USERS_EDIT; refuses owners, yourself, and people who
//                           also work at other facilities (their password isn't this facility's to reset).
//
// Passwords are never written to the GameAll database (spec §2 / §47); the owner can always generate a fresh one.
// ═══════════════════════════════════════════════════════════════════════════

import { createClient } from "jsr:@supabase/supabase-js@2";
import { buildDefaultPassword, buildStaffLogin } from "../_shared/staff-login.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface CreateStaffRequest {
  action?: string;
  facilityId: string;
  userId?: string;
  firstName?: string;
  lastName?: string;
  /** Older clients send only fullName; it is split into first / last. */
  fullName?: string;
  /** Contact email — stored for records, never used to sign in. */
  email?: string;
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
    headers: { ...CORS_HEADERS, "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}

function splitName(fullName: string): { first: string; last: string } {
  const parts = fullName.trim().split(/\s+/);
  return { first: parts[0] ?? "", last: parts.slice(1).join(" ") };
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
  if (!body.facilityId) return json({ error: "Facility is required." }, 400);

  const asCaller = createClient(url, anonKey, { global: { headers: { Authorization: authHeader } } });
  const admin = createClient(url, serviceKey, { auth: { autoRefreshToken: false, persistSession: false } });
  const callerId = (await asCaller.auth.getUser()).data.user?.id ?? null;
  if (!callerId) return json({ error: "Not authenticated" }, 401);

  // The facility's name (the password) and timezone (the clock the login and password are read from).
  const { data: facility } = await admin.from("facilities").select("name, timezone").eq("id", body.facilityId).maybeSingle();
  if (!facility?.name) return json({ error: "Facility not found." }, 404);
  const timeZone = facility.timezone || "Asia/Kolkata";

  // ── Reset password ──────────────────────────────────────────────────────
  if (body.action === "reset-password") {
    if (!body.userId) return json({ error: "Choose a staff member." }, 400);
    const { data: allowed, error: permError } = await asCaller.rpc("has_permission", {
      p_facility: body.facilityId,
      p_permission: "USERS_EDIT",
    });
    if (permError) return json({ error: "Could not verify your permissions." }, 500);
    if (!allowed) return json({ error: "You don't have permission to reset a staff password." }, 403);

    if (body.userId === callerId) return json({ error: "Change your own password from your account settings." }, 400);

    const { data: assignment } = await admin
      .from("facility_users")
      .select("role")
      .eq("facility_id", body.facilityId)
      .eq("user_id", body.userId)
      .maybeSingle();
    if (!assignment) return json({ error: "Staff member not found." }, 404);
    if (assignment.role === "owner") return json({ error: "An owner's password can't be reset from here." }, 403);

    const { count } = await admin.from("facility_users").select("facility_id", { count: "exact", head: true }).eq("user_id", body.userId);
    if ((count ?? 0) > 1) {
      return json({ error: "This person also works at another facility, so their password can't be reset from here." }, 409);
    }

    const password = buildDefaultPassword(facility.name, new Date(), timeZone);
    const { error: updateError } = await admin.auth.admin.updateUserById(body.userId, { password });
    if (updateError) {
      console.error("[create-staff] password reset failed", updateError.message);
      return json({ error: "Could not reset the password. Please try again." }, 500);
    }
    // They must choose their own password again at next sign-in, and any open session of theirs ends.
    await admin.from("profiles").update({ must_reset_password: true }).eq("id", body.userId);
    await admin.auth.admin.signOut(body.userId, "global").catch(() => undefined);

    const { data: profile } = await admin.from("profiles").select("full_name, staff_login, email").eq("id", body.userId).maybeSingle();
    await asCaller.rpc("log_security_event", {
      p_facility_id: body.facilityId,
      p_event: "STAFF_PASSWORD_RESET",
      p_summary: `Password reset for ${profile?.full_name ?? "staff member"}`,
      p_target_user_id: body.userId,
      p_target_role_id: null,
      p_detail: {},
    });
    return json({ userId: body.userId, loginEmail: profile?.staff_login ?? profile?.email ?? "", temporaryPassword: password }, 200);
  }

  // ── Create ──────────────────────────────────────────────────────────────
  const split = splitName(body.fullName ?? "");
  const firstName = (body.firstName ?? split.first).trim();
  const lastName = (body.lastName ?? split.last).trim();
  const contactEmail = (body.email ?? "").trim().toLowerCase();
  if (!firstName || !body.roleId) return json({ error: "Facility, first name and role are all required." }, 400);
  if (contactEmail && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(contactEmail)) {
    return json({ error: "Enter a valid email address." }, 400);
  }
  const fullName = [firstName, lastName].filter(Boolean).join(" ");

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

  const now = new Date();
  const password = buildDefaultPassword(facility.name, now, timeZone);

  // Two people with the same first name created in the same second would collide — count up until one is free.
  let loginEmail = "";
  let created: { user: { id: string } | null } | null = null;
  let createError: { message: string } | null = null;
  for (let attempt = 0; attempt < 5; attempt++) {
    loginEmail = buildStaffLogin(firstName, now, timeZone, attempt);
    const res = await admin.auth.admin.createUser({
      email: loginEmail,
      password,
      email_confirm: true,
      user_metadata: { full_name: fullName },
    });
    if (!res.error && res.data.user) {
      created = res.data;
      createError = null;
      break;
    }
    createError = res.error;
    if (!/already|registered|exists/i.test(res.error?.message ?? "")) break;
  }
  if (!created?.user) {
    console.error("[create-staff] createUser failed", createError?.message);
    return json({ error: "Could not create the staff account. Please try again." }, 500);
  }
  const userId = created.user.id;

  // The handle_new_user trigger has seeded the profile row; fill in the extras it doesn't know about.
  await admin
    .from("profiles")
    .update({
      full_name: fullName,
      first_name: firstName,
      last_name: lastName || null,
      contact_email: contactEmail || null,
      staff_login: loginEmail,
      phone: body.phone?.trim() || null,
      avatar_url: body.avatarUrl?.trim() || null,
      must_reset_password: true,
    })
    .eq("id", userId);

  // The facility assignment (service role — the RLS insert policy only allows an owner/manager, and we've already
  // checked USERS_CREATE which a custom role may hold instead).
  const { error: assignError } = await admin.from("facility_users").insert({
    facility_id: body.facilityId,
    user_id: userId,
    role: role.base_role ?? "staff",
    role_id: role.is_system ? null : role.id,
    status: "INVITED",
    is_primary: body.isPrimary ?? false,
    title: body.title?.trim() || null,
    notes: body.notes?.trim() || null,
    invited_by: callerId,
    invited_at: now.toISOString(),
    activated_at: null,
  });
  if (assignError) {
    console.error("[create-staff] facility_users insert failed", assignError.message);
    // Don't leave an orphan login behind.
    await admin.auth.admin.deleteUser(userId).catch(() => undefined);
    return json({ error: "Could not assign the staff member to this facility." }, 500);
  }

  await asCaller.rpc("log_security_event", {
    p_facility_id: body.facilityId,
    p_event: "STAFF_INVITED",
    p_summary: `${fullName} invited`,
    p_target_user_id: userId,
    p_target_role_id: role.id,
    p_detail: {},
  });

  return json(
    {
      userId,
      linked: false,
      loginEmail,
      // Returned to the administrator, who gives it to the new staff member; they must change it on first sign-in.
      temporaryPassword: password,
    },
    200,
  );
});
