// ═══════════════════════════════════════════════════════════════════════════
// delete-account — the signed-in person deletes their own account (web Profile, the app's Profile and the public
// /delete-account page all call this). The rules, and what "closed until settled" means, are in _shared/account-deletion.ts.
//
// Body: { "confirm": true }. The caller can only ever delete THEMSELVES: the id comes from their sign-in, never from the request.
// ═══════════════════════════════════════════════════════════════════════════

import { createClient } from "jsr:@supabase/supabase-js@2";
import { closeOrDeleteAccount } from "../_shared/account-deletion.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS_HEADERS });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anonKey || !serviceKey) return json({ error: "Not configured." }, 500);

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "Sign in to delete your account." }, 401);
  const asCaller = createClient(url, anonKey, { global: { headers: { Authorization: authHeader } } });
  const caller = (await asCaller.auth.getUser()).data.user;
  if (!caller) return json({ error: "Sign in to delete your account." }, 401);

  let body: { confirm?: boolean } = {};
  try {
    body = await req.json();
  } catch {
    /* an empty body is the same as not confirmed */
  }
  if (body.confirm !== true) return json({ error: "Please confirm that you want to delete your account." }, 400);

  const admin = createClient(url, serviceKey);
  try {
    const outcome = await closeOrDeleteAccount(admin, caller.id, {
      keyId: Deno.env.get("RAZORPAY_KEY_ID"),
      keySecret: Deno.env.get("RAZORPAY_KEY_SECRET"),
    });
    return json(outcome, 200);
  } catch (err) {
    console.error("[delete-account] failed", String(err));
    const message = err instanceof Error && err.message.includes("administrator") ? err.message : "We could not delete your account. Please try again or contact support.";
    return json({ error: message }, 500);
  }
});
