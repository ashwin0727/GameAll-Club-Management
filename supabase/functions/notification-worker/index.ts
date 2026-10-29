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
import { mapLimit } from "../_shared/concurrency.ts";

const BATCH = 100;
// How many pushes are in flight at once: fast, but gentle on Google's servers.
const PUSH_CONCURRENCY = 15;
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

  const sa = parseServiceAccount(Deno.env.get("FIREBASE_SERVICE_ACCOUNT"));
  if (!sa) {
    // Nothing is claimed, so the in-app list and any later push are unaffected.
    console.warn("[notification-worker] FIREBASE_SERVICE_ACCOUNT is not set — in-app notifications only");
    return json({ pushed: 0, push: "not configured" });
  }

  // Get the access token BEFORE claiming, so a failure here cannot lose a batch.
  let accessToken: string;
  try {
    accessToken = await getAccessToken(sa);
  } catch (err) {
    console.error("[notification-worker] could not get a Google access token", String(err));
    return json({ pushed: 0, push: "token error" }, 502);
  }

  // Claim a batch: the rows are marked pushed in the same statement that returns them, so two overlapping runs can never send the
  // same notification twice. Falls back to a plain read where the claim function does not exist yet (migration 0164 not applied).
  type Pending = { id: string; user_id: string; kind: string; title: string; body: string; data: unknown; created_at: string };
  let pending: Pending[] = [];
  const claim = await admin.rpc("claim_unpushed_notifications", { p_limit: BATCH });
  if (!claim.error) {
    pending = (claim.data ?? []) as Pending[];
  } else {
    const legacy = await admin.from("notifications").select("id, user_id, kind, title, body, data, created_at").is("pushed_at", null).order("created_at", { ascending: true }).limit(BATCH);
    if (legacy.error) return json({ error: legacy.error.message }, 500);
    pending = (legacy.data ?? []) as Pending[];
    if (pending.length) await admin.from("notifications").update({ pushed_at: new Date().toISOString() }).in("id", pending.map((n) => n.id));
  }
  if (!pending.length) return json({ pushed: 0, jobs: jobs.error ? "failed" : "ok" });

  const userIds = [...new Set(pending.map((n) => n.user_id))];
  const { data: tokens } = await admin.from("device_tokens").select("token, user_id").in("user_id", userIds);
  const byUser = new Map<string, string[]>();
  for (const t of tokens ?? []) byUser.set(t.user_id, [...(byUser.get(t.user_id) ?? []), t.token]);

  // One job per (notification, device), run a few at a time; one failure never stops the others.
  const jobList: { token: string; n: Pending }[] = [];
  for (const n of pending) {
    if (Date.now() - new Date(n.created_at).getTime() >= PUSH_MAX_AGE_MS) continue;
    for (const token of byUser.get(n.user_id) ?? []) jobList.push({ token, n });
  }
  const outcomes = await mapLimit(jobList, PUSH_CONCURRENCY, ({ token, n }) =>
    sendPush(sa, accessToken, token, {
      title: n.title,
      body: n.body,
      data: { id: n.id, kind: n.kind, route: String((n.data as { route?: string } | null)?.route ?? "") },
    }),
  );
  let sent = 0;
  const dead: string[] = [];
  outcomes.forEach((o, i) => {
    if (!o.ok) return;
    if (o.value === "sent") sent++;
    else if (o.value === "invalid-token") dead.push(jobList[i]!.token);
  });
  const done = pending;

  if (dead.length) await admin.from("device_tokens").delete().in("token", dead);
  return json({ pushed: sent, processed: done.length, removedTokens: dead.length });
});
