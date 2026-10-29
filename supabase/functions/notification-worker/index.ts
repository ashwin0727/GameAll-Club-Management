// ═══════════════════════════════════════════════════════════════════════════
// notification-worker — runs every minute.
//
//   1. run_notification_jobs()  writes the timed notifications (guest slot starts / ends in 5 minutes, the monthly report
//                               reminder, lapsed memberships and students). Event-driven ones are already written by
//                               database triggers.
//   2. pushes every notification not yet pushed to the person's phones through Firebase Cloud Messaging.
//
// It also completes account deletions that were waiting for payments to be settled.
//
// Schedule it in the Supabase dashboard: Integrations → Cron → Create job → "Supabase Edge Function" →
// notification-worker, every 1 minute.
//
// Secret:  supabase secrets set FIREBASE_SERVICE_ACCOUNT='<the whole service-account JSON>'
// Without it the in-app notifications still work; only the phone push is skipped.
// ═══════════════════════════════════════════════════════════════════════════

import { createClient } from "jsr:@supabase/supabase-js@2";
import { getAccessToken, parseServiceAccount, sendPush } from "../_shared/fcm.ts";
import { finishPendingDeletions } from "../_shared/account-deletion.ts";

const BATCH = 200;
// Anything older than this when push is first switched on is not worth buzzing a phone for.
const PUSH_MAX_AGE_MS = 60 * 60 * 1000;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

Deno.serve(async (req) => {
  if (req.method !== "POST" && req.method !== "GET") return json({ error: "Method not allowed" }, 405);

  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) return json({ error: "Not configured." }, 500);
  const admin = createClient(url, serviceKey);

  const jobs = await admin.rpc("run_notification_jobs");
  if (jobs.error) console.error("[notification-worker] run_notification_jobs failed", jobs.error.message);

  // Closed accounts whose payments have all been settled since: finish deleting them.
  try {
    await finishPendingDeletions(admin, { keyId: Deno.env.get("RAZORPAY_KEY_ID"), keySecret: Deno.env.get("RAZORPAY_KEY_SECRET") });
  } catch (err) {
    console.error("[notification-worker] pending account deletions failed", String(err));
  }

  const { data: pending, error } = await admin
    .from("notifications")
    .select("id, user_id, kind, title, body, data, created_at")
    .is("pushed_at", null)
    .order("created_at", { ascending: true })
    .limit(BATCH);
  if (error) return json({ error: error.message }, 500);
  if (!pending?.length) return json({ pushed: 0, jobs: jobs.error ? "failed" : "ok" });

  const sa = parseServiceAccount(Deno.env.get("FIREBASE_SERVICE_ACCOUNT"));
  if (!sa) {
    console.warn("[notification-worker] FIREBASE_SERVICE_ACCOUNT is not set — in-app notifications only");
    return json({ pushed: 0, pending: pending.length, push: "not configured" });
  }

  const accessToken = await getAccessToken(sa);
  const userIds = [...new Set(pending.map((n) => n.user_id))];
  const { data: tokens } = await admin.from("device_tokens").select("token, user_id").in("user_id", userIds);
  const byUser = new Map<string, string[]>();
  for (const t of tokens ?? []) byUser.set(t.user_id, [...(byUser.get(t.user_id) ?? []), t.token]);

  let sent = 0;
  const done: string[] = [];
  const dead: string[] = [];
  for (const n of pending) {
    const fresh = Date.now() - new Date(n.created_at).getTime() < PUSH_MAX_AGE_MS;
    if (fresh) {
      const data: Record<string, string> = { id: n.id, kind: n.kind, route: String((n.data as { route?: string } | null)?.route ?? "") };
      for (const token of byUser.get(n.user_id) ?? []) {
        const result = await sendPush(sa, accessToken, token, { title: n.title, body: n.body, data });
        if (result === "sent") sent++;
        else if (result === "invalid-token") dead.push(token);
      }
    }
    done.push(n.id);
  }

  if (done.length) await admin.from("notifications").update({ pushed_at: new Date().toISOString() }).in("id", done);
  if (dead.length) await admin.from("device_tokens").delete().in("token", dead);
  return json({ pushed: sent, processed: done.length, removedTokens: dead.length });
});
