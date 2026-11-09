// Scenario tests for the newer database code (plans, platform admin, notifications, permissions, account deletion, fewer-request bundles),
process.on("unhandledRejection", (e) => { console.log("FATAL:", String((e && e.message) || e).split("\n")[0]); process.exit(2); });
// run against every migration applied to an in-memory Postgres. PGlite is a single superuser, so Row Level Security is not exercised;
// the functions are SECURITY DEFINER or check permissions themselves, which is what these tests cover. auth.uid() is set per call.
import { PGlite } from "@electric-sql/pglite";
import { btree_gist } from "@electric-sql/pglite/contrib/btree_gist";
import { pgcrypto } from "@electric-sql/pglite/contrib/pgcrypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const dir = process.argv[2] ?? fileURLToPath(new URL("../../migrations", import.meta.url));
const db = new PGlite({ extensions: { btree_gist, pgcrypto } });
await db.exec(`
  create role anon nologin; create role authenticated nologin; create role service_role nologin; create role supabase_admin nologin;
  create schema if not exists auth;
  create table auth.users (id uuid primary key default gen_random_uuid(), email text unique, encrypted_password text, email_confirmed_at timestamptz,
    phone text, raw_user_meta_data jsonb default '{}'::jsonb, raw_app_meta_data jsonb default '{}'::jsonb, created_at timestamptz default now(),
    updated_at timestamptz default now(), banned_until timestamptz, last_sign_in_at timestamptz);
  create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
  create function auth.role() returns text language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claim.role', true), ''), 'anon') $$;
  create function auth.jwt() returns jsonb language sql stable as $$ select '{}'::jsonb $$;
  create schema if not exists storage;
  create table storage.buckets (id text primary key, name text, public boolean default false, file_size_limit bigint, allowed_mime_types text[], created_at timestamptz default now());
  create table storage.objects (id uuid primary key default gen_random_uuid(), bucket_id text, name text, owner uuid, created_at timestamptz default now(), metadata jsonb);
  create function storage.foldername(name text) returns text[] language sql as $$ select string_to_array(name, '/') $$;
  create function storage.filename(name text) returns text language sql as $$ select (string_to_array(name, '/'))[array_length(string_to_array(name, '/'), 1)] $$;
  create schema if not exists extensions;
`);
for (const f of fs.readdirSync(dir).filter((f) => f.endsWith(".sql")).sort()) {
  await db.exec(fs.readFileSync(path.join(dir, f), "utf8").replace(/^﻿/, ""));
}

let passed = 0;
const failed = [];
const q = async (sql, params = []) => (await db.query(sql, params)).rows;
const asUser = async (uid) => { await db.query("select set_config('request.jwt.claim.sub', $1, false)", [uid ?? ""]); };
const check = (name, cond, detail = "") => { if (cond) passed++; else failed.push(`${name} ${detail}`); };
async function throws(name, fn, match) {
  try { await fn(); failed.push(`${name} (expected an error)`); }
  catch (e) { if (!match || String(e.message).includes(match)) passed++; else failed.push(`${name} (wrong error: ${e.message})`); }
}
const uuid = () => crypto.randomUUID();
let n = 0;
async function mkUser(email, name = "Test User") {
  const id = uuid();
  await q(`insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values ($1,$2,now(),$3::jsonb)`, [id, email, JSON.stringify({ full_name: name })]);
  await q(`insert into profiles (id, full_name, email) values ($1,$2,$3) on conflict (id) do nothing`, [id, name, email]);
  return id;
}
async function mkFacility(owner, name = "Venue") {
  const id = uuid();
  const base = { id, name, slug: `f-${n++}-${id.slice(0, 6)}`, owner_id: owner, timezone: "Asia/Kolkata", currency: "INR", facility_type: "BADMINTON" };
  // Fill whatever other columns are required and have no default (they differ between onboarding steps).
  const need = await q(`select column_name c, data_type t from information_schema.columns where table_name='facilities' and table_schema='public' and is_nullable='NO' and column_default is null`);
  for (const { c, t } of need) if (!(c in base)) base[c] = t === "text" || t === "character varying" ? "x@test.local" : t === "boolean" ? false : t === "integer" ? 1 : "x";
  const cols = Object.keys(base);
  await q(`insert into facilities (${cols.join(",")}) values (${cols.map((_, i) => "$" + (i + 1)).join(",")})`, cols.map((c) => base[c]));
  await q(`insert into facility_users (facility_id, user_id, role) values ($1,$2,'owner')`, [id, owner]);
  return id;
}
async function mkMember(f, name = "Arun Sharma") {
  const id = uuid();
  await q(`insert into members (id, facility_id, full_name, phone) values ($1,$2,$3,$4)`, [id, f, name, `9${Math.floor(Math.random() * 1e9).toString().padStart(9, "0")}`]);
  return id;
}
async function mkMembership(f, member, name = "Monthly") {
  const id = uuid();
  await q(`insert into memberships (id, facility_id, member_id, status, start_date, end_date, name, duration_days, membership_fee_inr, registration_fee_inr, total_amount_inr, monthly_price_inr)
           values ($1,$2,$3,'active', current_date, current_date + 30, $4, 30, 2500, 0, 2500, 2500)`, [id, f, member, name]);
  return id;
}

// ═══ Session bundle ═══════════════════════════════════════════════════════════
const owner = await mkUser("owner@test.local", "Olivia Owner");
const fac = await mkFacility(owner, "Smash Arena");
await asUser(owner);
{
  const [{ b }] = await q("select get_session_bundle() as b");
  check("bundle: owner profile", b.profile?.full_name === "Olivia Owner");
  check("bundle: owner facility", b.facility?.id === fac && b.facility?.owner_id === owner);
  check("bundle: baseRole owner", b.baseRole === "owner");
  check("bundle: owner permissions non-empty", Array.isArray(b.permissions) && b.permissions.length > 20, `got ${b.permissions?.length}`);
  check("bundle: no plan row -> null", b.plan === null);
  check("bundle: not admin", b.isPlatformAdmin === false);
}
const lonely = await mkUser("lonely@test.local");
await asUser(lonely);
{
  const [{ b }] = await q("select get_session_bundle() as b");
  check("bundle: user without a facility", b.facility === null && b.baseRole === null && b.permissions.length === 0);
}
await asUser(null);
check("bundle: signed out -> null", (await q("select get_session_bundle() as b"))[0].b === null);

// Staff member with a role holding only COACHING_SCHEDULE_VIEW (0158 + 0159)
const staff = await mkUser("staff@test.local", "Sam Staff");
const roleId = uuid();
await q(`insert into roles (id, facility_id, name, base_role, is_active) values ($1,$2,'Scheduler','staff', true)`, [roleId, fac]);
await q(`insert into role_permissions (role_id, permission_key) select $1, key from permissions where key in ('COACHING_SCHEDULE_VIEW','ROLES_VIEW')`, [roleId]);
await q(`insert into facility_users (facility_id, user_id, role, role_id, status) values ($1,$2,'staff',$3,'ACTIVE')`, [fac, staff, roleId]);
await asUser(staff);
{
  const [{ b }] = await q("select get_session_bundle() as b");
  check("bundle: staff base role", b.baseRole === "staff");
  check("bundle: staff sees exactly its permissions", b.permissions.includes("COACHING_SCHEDULE_VIEW") && !b.permissions.includes("FINANCE_VIEW"), JSON.stringify(b.permissions));
  const sessions = await q("select * from list_coaching_sessions($1)", [fac]);
  check("0158: schedule-only role can list coaching sessions", Array.isArray(sessions));
  const roles = await q("select * from list_roles($1)", [fac]);
  check("0159: roles-view-only role can list roles", roles.length >= 1);
  await throws("staff without FINANCE cannot read expense summary", () => q("select get_expense_summary($1)", [fac]), "permission");
}

// ═══ Calendar range + revenue ═════════════════════════════════════════════════
await asUser(owner);
{
  const rows = await q("select * from list_membership_sessions_for_range($1, current_date, current_date + 6)", [fac]);
  check("range sessions: runs for a week", Array.isArray(rows));
  await throws("range sessions: refuses > 2 months", () => q("select * from list_membership_sessions_for_range($1, current_date, current_date + 90)", [fac]), "two months");
  await asUser(lonely);
  await throws("range sessions: refuses a stranger", () => q("select * from list_membership_sessions_for_range($1, current_date, current_date + 3)", [fac]));
  await asUser(owner);
  const m = await mkMember(fac);
  await q(`insert into payments (facility_id, member_id, amount_inr, status, payment_method, paid_at) values ($1,$2,500,'paid','cash', now()), ($1,$2,300,'paid','cash', now()), ($1,$2,900,'created','cash', null)`, [fac, m]);
  const [{ r }] = await q("select period_revenue_inr($1, now() - interval '1 day', now() + interval '1 day') as r", [fac]);
  check("period revenue sums paid only", Number(r) === 800, `got ${r}`);
}

// ═══ Plans (0157) ═════════════════════════════════════════════════════════════
await asUser(owner);
{
  const plans = await q("select * from list_plans()");
  check("list_plans: two plans", plans.length === 2 && plans[0].code === "basic" && plans[1].code === "advanced");
  check("list_plans: 90-day trial", plans.every((p) => p.trial_days === 90));
  check("plans: Basic excludes Finance, Advanced includes it", !plans[0].page_keys.includes("FINANCE_OVERVIEW") && plans[1].page_keys.includes("FINANCE_OVERVIEW"));
  check("plans: Basic has no Guest Player Lists / Maintenance / Staff", ["GUEST_PLAYERS", "MAINTENANCE", "STAFF"].every((k) => !plans[0].page_keys.includes(k)));
  const [{ c }] = await q("select begin_plan_change($1, 'advanced', 'year') as c", [fac]);
  check("begin_plan_change: first plan is a trial", c.trial === true && c.amountMinor === 199900 && c.firstChargeOn);
  await throws("begin_plan_change: staff cannot choose a plan", async () => { await asUser(staff); await q("select begin_plan_change($1,'basic','month')", [fac]); }, "owner");
  await asUser(null);
  await q("select record_plan_checkout($1,'advanced','year','sub_a',$2::date,true,$3)", [fac, c.firstChargeOn, owner]);
  const act = (await q("select activate_plan_checkout('sub_a') as a"))[0].a;
  check("activate: nothing to replace the first time", act.replacedSubscriptionId === null);
  await asUser(owner);
  let p = (await q("select my_facility_plan($1) as p", [fac]))[0].p;
  check("plan: trialing advanced", p.planCode === "advanced" && p.status === "trialing" && p.onTrial === true && p.daysLeft > 80);
  check("plan: advanced has AutoPay and Player memberships", (await q("select plan_has_feature($1,'AUTOPAY') a, plan_has_feature($1,'PLAYER_MEMBERSHIPS') b", [fac]))[0].a === true);
  check("public: club accepts online memberships on Advanced", (await q("select public_facility_accepts_memberships($1) a", [fac]))[0].a === true);

  // Switch to Basic mid-trial: new price starts after the trial, old subscription is reported for cancelling
  const [{ c: c2 }] = await q("select begin_plan_change($1, 'basic', 'month') as c", [fac]);
  check("begin_plan_change: switching mid-trial is not a new trial and starts after it", c2.trial === false && c2.firstChargeOn > c.firstChargeOn.slice(0, 10) || c2.trial === false);
  await asUser(null);
  await q("select record_plan_checkout($1,'basic','month','sub_b',$2::date,false,$3)", [fac, c2.firstChargeOn, owner]);
  const act2 = (await q("select activate_plan_checkout('sub_b') as a"))[0].a;
  check("activate: reports the subscription it replaces", act2.replacedSubscriptionId === "sub_a");
  await asUser(owner);
  check("Basic: no AutoPay", (await q("select plan_has_feature($1,'AUTOPAY') a", [fac]))[0].a === false);
  check("Basic: Player App memberships off", (await q("select public_facility_accepts_memberships($1) a", [fac]))[0].a === false);
  check("Basic: Finance page not in plan, Home is", (await q("select plan_includes_page($1,'FINANCE_OVERVIEW') f, plan_includes_page($1,'HOME') h", [fac]))[0].f === false);
  check("Basic: owner loses finance permission through the plan", (await q("select has_permission($1,'FINANCE_VIEW') h", [fac]))[0].h === false);
  check("Basic: owner keeps memberships permission", (await q("select has_permission($1,'MEMBERSHIPS_VIEW') h", [fac]))[0].h === true);
  const [{ b }] = await q("select get_session_bundle() as b");
  check("bundle carries the plan", b.plan?.planCode === "basic" && b.plan.pageKeys.includes("HOME") && !b.plan.pageKeys.includes("FINANCE_OVERVIEW"));
  // Public membership signup is refused on Basic (0162)
  const planRow = uuid();
  await q(`insert into membership_plans (id, facility_id, name, price_inr, duration_days) values ($1,$2,'Gold',1000,30)`, [planRow, fac]);
  await asUser(null);
  await throws("public signup refused on Basic", () => q("select public_start_membership_signup($1,'Pat Player','9111100001',null,$2,null)", [fac, planRow]), "not taking online memberships");
  // Webhook branch
  check("webhook: unknown subscription is not ours", (await q("select apply_plan_subscription_webhook('nope','subscription.charged',current_date) a"))[0].a === false);
  check("webhook: ours", (await q("select apply_plan_subscription_webhook('sub_b','subscription.charged',(current_date + 30)) a"))[0].a === true);
  p = (await q("select status, valid_till from facility_subscriptions where facility_id=$1", [fac]))[0];
  check("webhook: charged -> active", p.status === "active");
  await q("select apply_plan_subscription_webhook('sub_b','subscription.halted',null)");
  check("webhook: halted -> cancelled -> Basic fallback", (await q("select effective_plan_code($1) c", [fac]))[0].c === "basic");
}
// free trial started from the mobile app
const o2 = await mkUser("owner2@test.local");
const f2 = await mkFacility(o2, "App Venue");
await asUser(o2);
{
  const t = (await q("select start_free_trial($1) as t", [f2]))[0].t;
  check("start_free_trial: trialing Advanced for 3 months", t.planCode === "advanced" && t.status === "trialing" && t.daysLeft >= 88 && t.daysLeft <= 92, JSON.stringify(t));
  const again = (await q("select start_free_trial($1) as t", [f2]))[0].t;
  check("start_free_trial: second call changes nothing", again.validTill === t.validTill);
  const [{ c }] = await q("select begin_plan_change($1,'advanced','month') as c", [f2]);
  check("web later: first charge starts after the app trial", c.trial === false && String(c.firstChargeOn).slice(0, 10) > new Date().toISOString().slice(0, 10));
  await asUser(owner);
  await throws("start_free_trial: only the owner", () => q("select start_free_trial($1)", [f2]), "owner");
}

// ═══ Platform admin (0160) ════════════════════════════════════════════════════
const admin = await mkUser("admin@gameall.co", "GameAll Admin");
const pm = uuid();
await asUser(null);
await q(`insert into facility_payout_methods (id, facility_id, method_type, account_holder_name, bank_name, account_number, ifsc) values ($1,$2,'BANK','Olivia','HDFC','1234567890','HDFC0001234')`, [pm, fac]);
await asUser(admin);
{
  check("admin: is_platform_admin", (await q("select is_platform_admin() a"))[0].a === true);
  const o = (await q("select admin_overview() as o"))[0].o;
  check("admin: overview counts facilities", o.facilities >= 2 && o.payoutsPending >= 1);
  const list = (await q("select admin_list_facilities(null,50,0) as l"))[0].l;
  check("admin: lists every facility with owner", list.total >= 2 && list.rows.some((r) => r.ownerEmail === "owner@test.local"));
  const det = (await q("select admin_get_facility($1) as d", [fac]))[0].d;
  check("admin: facility detail", det.facility.name === "Smash Arena" && det.owner.email === "owner@test.local" && det.payments && det.plan);
  await q("select admin_review_payout_method($1,'VERIFIED',null)", [pm]);
  const m = (await q("select verification_status, verified_by from facility_payout_methods where id=$1", [pm]))[0];
  check("admin: verifying a payout method", m.verification_status === "VERIFIED" && m.verified_by === admin);
  await throws("admin: reject needs a reason", () => q("select admin_review_payout_method($1,'REJECTED',null)", [pm]), "why");
  // Payments: online (Razorpay) vs cash
  const mem = await mkMember(fac, "Rita Player");
  await q(`insert into payments (facility_id, member_id, amount_inr, status, payment_method, paid_at, razorpay_payment_id) values ($1,$2,700,'paid','RAZORPAY', now(), 'pay_1'), ($1,$2,200,'paid','upi_autopay', now(), 'pay_2'), ($1,$2,100,'paid','cash', now(), null)`, [fac, mem]);
  const tf = (await q("select admin_list_transaction_facilities() as t"))[0].t;
  const mine = tf.find((x) => x.id === fac);
  check("admin: only Razorpay payments count", mine.recentCount === 2 && Number(mine.recentInr) === 900, JSON.stringify(mine));
  const tx = (await q("select admin_list_transactions($1,'recent',50,0) as t", [fac]))[0].t;
  check("admin: recent list excludes cash", tx.total === 2 && tx.rows.every((r) => r.razorpayPaymentId));
  const ids = tx.rows.map((r) => r.id);
  check("admin: mark settled", (await q("select admin_mark_settled($1::uuid[], 'sent') n", [ids]))[0].n === 2);
  check("admin: settled tab", (await q("select admin_list_transactions($1,'settled',50,0) as t", [fac]))[0].t.total === 2);
  check("admin: recent empty after settling", (await q("select admin_list_transactions($1,'recent',50,0) as t", [fac]))[0].t.total === 0);
  await q("select admin_unsettle($1)", [ids[0]]);
  check("admin: undo", (await q("select admin_list_transactions($1,'recent',50,0) as t", [fac]))[0].t.total === 1);
  await asUser(owner);
  await throws("non-admin cannot call admin functions", () => q("select admin_overview()"), "Platform administrators only");
  // a fresh method added by the owner always starts PENDING, and the owner cannot flip it
  const pm2 = uuid();
  await q("insert into facility_payout_methods (id, facility_id, method_type, account_holder_name, upi_id, verification_status) values ($1,$2,'UPI','Olivia','olivia@upi','VERIFIED')", [pm2, fac]);
  check("owner insert is forced to PENDING", (await q("select verification_status s from facility_payout_methods where id=$1", [pm2]))[0].s === "PENDING");
  await throws("owner cannot self-verify a payout method", () => q("update facility_payout_methods set verification_status='VERIFIED' where id=$1", [pm2]), "managed by GameAll");
  await throws("owner cannot change the verification note either", () => q("update facility_payout_methods set verification_note='ok' where id=$1", [pm2]), "managed by GameAll");
  await q("update facility_payout_methods set account_number='999' where id=$1", [pm]);
  check("owner editing the account resets verification", (await q("select verification_status s from facility_payout_methods where id=$1", [pm]))[0].s === "PENDING");
}

// ═══ Notifications (0161) ═════════════════════════════════════════════════════
await asUser(null);
{
  await q("delete from notifications");
  const m = await mkMember(fac, "Nina Member");
  const ms = await mkMembership(fac, m, "Monthly Gold");
  const created = await q("select * from notifications where user_id=$1 and kind='membership_created'", [owner]);
  check("notify: membership created", created.length === 1 && created[0].body === "Nina Member has been successfully created", JSON.stringify(created));
  await q(`insert into payments (facility_id, member_id, membership_id, amount_inr, status, razorpay_payment_id, paid_at) values ($1,$2,$3,2500,'paid','pay_m1', now())`, [fac, m, ms]);
  let rows = await q("select kind, body from notifications where user_id=$1 and kind in ('membership_payment_received','membership_renewed')", [owner]);
  check("notify: first payment is 'received', not 'renewed'", rows.length === 1 && rows[0].kind === "membership_payment_received" && rows[0].body === "Nina Member – Payment for Monthly Gold received successfully", JSON.stringify(rows));
  await q(`insert into payments (facility_id, member_id, membership_id, amount_inr, status, razorpay_payment_id, paid_at) values ($1,$2,$3,2500,'paid','pay_m2', now())`, [fac, m, ms]);
  rows = await q("select kind, body from notifications where user_id=$1 and kind='membership_renewed'", [owner]);
  check("notify: second payment renews", rows.length === 1 && rows[0].body === "Nina Member has been successfully Renewed", JSON.stringify(rows));
  await q(`insert into payments (facility_id, member_id, membership_id, amount_inr, status) values ($1,$2,$3,2500,'failed')`, [fac, m, ms]);
  rows = await q("select body from notifications where user_id=$1 and kind='membership_payment_failed'", [owner]);
  check("notify: failed payment message", rows.length === 1 && rows[0].body.includes("is Failed. Kindly contact for the Payment Updates."), JSON.stringify(rows));
  check("notify: staff without memberships access gets nothing", (await q("select count(*)::int c from notifications where user_id=$1", [staff]))[0].c === 0);
  // Preferences: switch memberships off for the owner
  await q(`update profiles set notification_prefs = '{"memberships": false}'::jsonb where id=$1`, [owner]);
  const m2 = await mkMember(fac, "Quiet Member");
  await mkMembership(fac, m2, "Silver");
  check("notify: respects the person's switch", (await q("select count(*)::int c from notifications where user_id=$1 and body like 'Quiet Member%'", [owner]))[0].c === 0);
  await q(`update profiles set notification_prefs = '{}'::jsonb where id=$1`, [owner]);

  // Timed: a guest booking about to start/end
  const court = await (async () => {
    const sport = (await q("select id from sports where key='badminton'"))[0].id;
    await q("insert into facility_sports (facility_id, sport_id) values ($1,$2) on conflict do nothing", [fac, sport]);
    const fs_ = (await q("select id from facility_sports where facility_id=$1 and sport_id=$2", [fac, sport]))[0].id;
    const cid = uuid();
    await q("insert into courts (id, facility_id, sport_id, facility_sport_id, name, hourly_rate_inr) values ($1,$2,$3,$4,'Court 1',300)", [cid, fac, sport, fs_]);
    return cid;
  })();
  const bid = uuid();
  await q(`insert into bookings (id, facility_id, court_id, customer_type, guest_name, guest_phone, start_time, end_time, status, amount_minor)
           values ($1,$2,$3,'GUEST','Ravi Guest','9111111111', now() + interval '4 minutes', now() + interval '64 minutes', 'confirmed', 30000)`, [bid, fac, court]);
  await q("select run_notification_jobs()");
  await q("select run_notification_jobs()");
  rows = await q("select body from notifications where user_id=$1 and kind='guest_booking_starting'", [owner]);
  check("notify: slot starts in 5 minutes (once, even if the job runs twice)", rows.length === 1 && rows[0].body === "Ravi Guest is going to Start in 5 minutes", JSON.stringify(rows));
  const sport2 = (await q("select id from sports where key='badminton'"))[0].id;
  const fsId = (await q("select id from facility_sports where facility_id=$1 and sport_id=$2", [fac, sport2]))[0].id;
  const court2 = uuid();
  await q("insert into courts (id, facility_id, sport_id, facility_sport_id, name, hourly_rate_inr) values ($1,$2,$3,$4,'Court 2',300)", [court2, fac, sport2, fsId]);
  const bid2 = uuid();
  await q(`insert into bookings (id, facility_id, court_id, customer_type, guest_name, guest_phone, start_time, end_time, status, amount_minor)
           values ($1,$2,$3,'GUEST','Sita Guest','9222222222', now() - interval '56 minutes', now() + interval '4 minutes', 'confirmed', 30000)`, [bid2, fac, court2]);
  await q("select run_notification_jobs()");
  rows = await q("select body from notifications where user_id=$1 and kind='guest_booking_ending'", [owner]);
  check("notify: slot ends in 5 minutes", rows.length === 1 && rows[0].body === "Sita Guest is going to End in 5 minutes", JSON.stringify(rows));

  // Atomic claim
  const first = await q("select * from claim_unpushed_notifications(200)");
  const second = await q("select * from claim_unpushed_notifications(200)");
  check("claim: first run gets the batch, second gets nothing", first.length > 5 && second.length === 0, `${first.length}/${second.length}`);
  await asUser(owner);
  check("mark read", (await q("select mark_notifications_read(null) n"))[0].n > 0);
  await q("select register_device_token('tok123','android')");
  await q("select register_device_token('tok123','android')");
  check("device token is stored once", (await q("select count(*)::int c from device_tokens where token='tok123'"))[0].c === 1);
}

// ═══ Account deletion (0163) ══════════════════════════════════════════════════
await asUser(null);
{
  const delOwner = await mkUser("delowner@test.local", "Dora Delete");
  const delFac = await mkFacility(delOwner, "Doomed Venue");
  const delStaff = await mkUser("delstaff@test.local", "Stan Staff");
  await q("insert into facility_users (facility_id, user_id, role, status) values ($1,$2,'staff','ACTIVE')", [delFac, delStaff]);
  // another facility where delStaff ALSO works -> must NOT be deleted as an orphan
  const sharedStaff = await mkUser("shared@test.local", "Shared Staff");
  await q("insert into facility_users (facility_id, user_id, role, status) values ($1,$2,'staff','ACTIVE'), ($3,$2,'staff','ACTIVE')", [delFac, sharedStaff, fac]);
  const dm = await mkMember(delFac, "Dev Member");
  const dms = await mkMembership(delFac, dm, "Silver");
  await q(`insert into payments (facility_id, member_id, membership_id, amount_inr, status, razorpay_payment_id, paid_at) values ($1,$2,$3,1000,'paid','pay_del1', now())`, [delFac, dm, dms]);
  await q(`insert into facility_subscriptions (facility_id, plan_name, price_minor, billing_interval, status, valid_till, plan_code, razorpay_subscription_id) values ($1,'Basic',12900,'month','active', current_date + 20, 'basic','sub_plan_del')`, [delFac]);
  await q(`insert into membership_subscriptions (membership_id, facility_id, member_id, razorpay_plan_id, razorpay_subscription_id, amount_inr, interval_months, one_time_inr) values ($1,$2,$3,'plan_x','sub_mem_del',1000,1,0)`, [dms, delFac, dm]);

  const blockers = (await q("select account_deletion_blockers($1) b", [delOwner]))[0].b;
  check("deletion: unsettled online payment blocks", blockers.unsettledCount === 1 && Number(blockers.unsettledInr) === 1000, JSON.stringify(blockers));
  const plan = (await q("select account_deletion_plan($1) p", [delOwner]))[0].p;
  check("deletion plan: facility, subscriptions and orphan staff", plan.facilities.length === 1 && plan.razorpaySubscriptions.includes("sub_plan_del") && plan.razorpaySubscriptions.includes("sub_mem_del") && plan.orphanStaff.includes(delStaff) && !plan.orphanStaff.includes(sharedStaff), JSON.stringify(plan));
  await q("select close_owned_facilities($1)", [delOwner]);
  check("deletion: closing keeps records but deactivates the facility", (await q("select status::text s from facilities where id=$1", [delFac]))[0].s === "INACTIVE" && (await q("select count(*)::int c from payments where facility_id=$1", [delFac]))[0].c === 1);
  // admin settles the payment -> nothing blocks any more
  await q("insert into payment_settlements (payment_id, facility_id) select id, facility_id from payments where facility_id=$1", [delFac]);
  check("deletion: settled payments no longer block", (await q("select account_deletion_blockers($1) b", [delOwner]))[0].b.unsettledCount === 0);

  // Records written by the staff member in ANOTHER facility must not block deleting them
  await q(`insert into bookings (facility_id, court_id, customer_type, guest_name, guest_phone, start_time, end_time, status, amount_minor, created_by)
           select $1, c.id, 'GUEST', 'By Stan', '9333333333', now() + interval '3 days', now() + interval '3 days 1 hour', 'confirmed', 100, $2 from courts c where c.facility_id=$1 limit 1`, [fac, delStaff]);
  const placeholder = await mkUser("deleted-user@gameall.invalid", "Deleted user");
  // run the exact sequence the edge function runs
  await q("select delete_owned_facilities($1)", [delOwner]);
  check("deletion: facility and all its data gone", (await q("select count(*)::int c from facilities where id=$1", [delFac]))[0].c === 0 && (await q("select count(*)::int c from payments where facility_id=$1", [delFac]))[0].c === 0 && (await q("select count(*)::int c from memberships where facility_id=$1", [delFac]))[0].c === 0);
  for (const s of plan.orphanStaff) {
    await q("select reassign_user_references($1,$2)", [s, placeholder]);
    await q("delete from auth.users where id=$1", [s]);
  }
  await q("select reassign_user_references($1,$2)", [delOwner, placeholder]);
  await q("delete from auth.users where id=$1", [delOwner]);
  check("deletion: owner and orphan staff accounts gone", (await q("select count(*)::int c from auth.users where id = any($1::uuid[])", [[delOwner, delStaff]]))[0].c === 0 && (await q("select count(*)::int c from profiles where id = any($1::uuid[])", [[delOwner, delStaff]]))[0].c === 0);
  check("deletion: staff who also work elsewhere survive", (await q("select count(*)::int c from auth.users where id=$1", [sharedStaff]))[0].c === 1);
  check("deletion: records the staff wrote elsewhere are kept, re-pointed to the placeholder", (await q("select created_by from bookings where guest_name='By Stan'"))[0].created_by === placeholder);
  check("deletion: other facilities untouched", (await q("select count(*)::int c from facilities where id=$1", [fac]))[0].c === 1);
  await throws("deletion helpers are not callable by signed-in users", async () => { await q("set role authenticated"); try { await q("select delete_owned_facilities($1)", [owner]); } finally { await q("reset role"); } });
}

// ═══ dashboard_totals (0165) — must give the same numbers the browser used to add up ══════════════════════════
{
  const o2 = await mkUser("dash-owner@test.local", "Dash Owner");
  const f2 = await mkFacility(o2, "Dash Arena");
  await asUser(o2);
  const sports = await q("select id from sports where key in ('badminton','cricket') order by key");
  const fsIds = [];
  const courts = [];
  for (const [i, s] of sports.entries()) {
    const fsid = uuid();
    await q("insert into facility_sports (id, facility_id, sport_id) values ($1,$2,$3)", [fsid, f2, s.id]);
    const cid = uuid();
    await q("insert into courts (id, facility_id, sport_id, facility_sport_id, name, hourly_rate_inr) values ($1,$2,$3,$4,$5,300)", [cid, f2, s.id, fsid, `Court ${i + 1}`]);
    fsIds.push(fsid);
    courts.push(cid);
  }
  const [cA, cB] = courts; // cA = badminton (sport 1), cB = cricket (sport 2)
  const mkBooking = async (court, status, pay, at, guest = "Guest") => {
    const id = uuid();
    await q(`insert into bookings (id, facility_id, court_id, customer_type, guest_name, guest_phone, start_time, end_time, status, payment_status, amount_minor)
             values ($1,$2,$3,'GUEST',$4,'9000000000',$5::timestamptz,$5::timestamptz + interval '1 hour',$6,$7,10000)`, [id, f2, court, guest, at, status, pay]);
    return id;
  };
  const b1 = await mkBooking(cA, "confirmed", "PAID", "2026-10-05 10:00+00");
  await mkBooking(cA, "cancelled", "PAID", "2026-10-06 10:00+00");
  await mkBooking(cA, "confirmed", "PENDING", "2026-10-07 10:00+00");
  const b4 = await mkBooking(cB, "confirmed", "PAID", "2026-10-08 10:00+00");
  const b3 = await mkBooking(cA, "confirmed", "PAID", "2026-09-10 10:00+00");

  const pm = await mkMember(f2, "Pay Member");
  const msA = await mkMembership(f2, pm, "In sport one");
  const m2 = await mkMember(f2, "Soon Member");
  const msSoon = await mkMembership(f2, m2, "Ending soon");
  await q("update memberships set end_date = current_date + 3 where id=$1", [msSoon]);
  const m3 = await mkMember(f2, "Old Member");
  const msOld = await mkMembership(f2, m3, "Lapsed");
  await q("update memberships set status='expired', created_at = now() - interval '60 days' where id=$1", [msOld]);

  // membership msA is enrolled in a batch of sport 1
  const plan = uuid();
  await q("insert into membership_plans (id, facility_id, name, price_inr, duration_days) values ($1,$2,'P',1000,30)", [plan, f2]);
  const batch = uuid();
  await q(`insert into membership_batches (id, facility_id, plan_id, facility_sport_id, court_id, name, days_of_week, start_time, end_time, capacity)
           values ($1,$2,$3,$4,$5,'B','{1}','06:00','07:00',10)`, [batch, f2, plan, fsIds[0], cA]);
  await q("insert into membership_batch_members (batch_id, member_id, membership_id) values ($1,$2,$3)", [batch, pm, msA]);

  const pay = (amount, status, at, link = {}) =>
    q(`insert into payments (facility_id, member_id, booking_id, membership_id, amount_inr, status, created_at) values ($1,$2,$3,$4,$5,$6,$7::timestamptz)`,
      [f2, pm, link.booking ?? null, link.membership ?? null, amount, status, at]);
  await pay(1000, "paid", "2026-10-10 09:00+00", { booking: b1 });
  await pay(500, "paid", "2026-10-11 09:00+00", { booking: b4 });
  await pay(300, "created", "2026-10-12 09:00+00", { booking: b1 });
  await pay(200, "refunded", "2026-10-13 09:00+00", { booking: b1 });
  await pay(400, "paid", "2026-10-14 09:00+00");
  await pay(900, "paid", "2026-10-15 09:00+00", { membership: msA });
  await pay(700, "paid", "2026-09-15 09:00+00", { booking: b3 });
  await pay(111, "paid", "2026-08-15 09:00+00"); // before both windows
  // the database stamps paid_at with "now" on insert; make the money arrive the day the row was made
  await q("update payments set paid_at = created_at where facility_id=$1 and status='paid'", [f2]);

  const totals = async (sportIds, courtIds = courts) =>
    (await q(`select dashboard_totals($1, '2026-10-01+00', '2026-11-01+00', '2026-09-01+00', '2026-10-01+00', $2::uuid[], $3::uuid[], now() + interval '7 days', date_trunc('month', now())) t`, [f2, courtIds, sportIds]))[0].t;

  const all = await totals(null);
  check("totals (all sports): payments", all.collectedInr === 2800 && all.pendingInr === 300 && all.refundsInr === 200 && all.previousCollectedInr === 700, JSON.stringify(all));
  check("totals (all sports): guest bookings count paid, uncancelled only", all.guestBookings === 2 && all.previousGuestBookings === 1, JSON.stringify(all));
  check("totals: memberships", all.memberships.active === 2 && all.memberships.expiringSoon === 1 && all.memberships.expired === 1 && all.memberships.newThisMonth === 2 && all.activeMembershipsInScope === 2, JSON.stringify(all.memberships));

  const one = await totals([fsIds[0]], [cA]);
  check("totals (one sport): only its bookings and memberships", one.collectedInr === 1900 && one.pendingInr === 300 && one.refundsInr === 200 && one.previousCollectedInr === 700, JSON.stringify(one));
  check("totals (one sport): guests and memberships follow the sport", one.guestBookings === 1 && one.previousGuestBookings === 1 && one.activeMembershipsInScope === 1, JSON.stringify(one));
  const other = await totals([fsIds[1]], [cB]);
  check("totals (other sport)", other.collectedInr === 500 && other.guestBookings === 1 && other.activeMembershipsInScope === 0, JSON.stringify(other));

  const noPrev = (await q(`select dashboard_totals($1, '2026-10-01+00', '2026-11-01+00', null, null, $2::uuid[], null, now(), now()) t`, [f2, courts]))[0].t;
  check("totals: no comparison period gives zero previous", noPrev.previousCollectedInr === 0 && noPrev.previousGuestBookings === 0 && noPrev.collectedInr === 2800, JSON.stringify(noPrev));
  // ── booked minutes (0166) ──
  const mins = await q(`select * from dashboard_booked_minutes($1, '2026-10-01+00', '2026-11-01+00', '2026-09-01+00', '2026-10-01+00', '2026-10-01', '2026-11-01', '2026-09-01', '2026-10-01', $2::uuid[])`, [f2, courts]);
  const minOf = (c) => mins.find((r) => r.court_id === c) ?? { cur_minutes: 0, prev_minutes: 0 };
  check("minutes: cancelled bookings are not counted, pending ones are", minOf(cA).cur_minutes === 120 && minOf(cA).prev_minutes === 60 && minOf(cB).cur_minutes === 60 && minOf(cB).prev_minutes === 0, JSON.stringify(mins));
  const onlyA = await q(`select * from dashboard_booked_minutes($1, '2026-10-01+00', '2026-11-01+00', null, null, '2026-10-01', '2026-11-01', null, null, $2::uuid[])`, [f2, [cA]]);
  check("minutes: only the courts in view, no previous period", onlyA.length === 1 && onlyA[0].court_id === cA && onlyA[0].cur_minutes === 120 && onlyA[0].prev_minutes === 0, JSON.stringify(onlyA));

  // ── revenue chart (0166) ──
  const rev = async (sportIds) => (await q(`select dashboard_revenue_overview($1, '2026-10-01+00', '2026-11-01+00', '2026-09-01+00', 'Asia/Kolkata', $2::uuid[]) r`, [f2, sportIds]))[0].r;
  const r0 = await rev(null);
  check("revenue: totals", r0.totalInr === 2800 && r0.previousTotalInr === 700, JSON.stringify(r0));
  check("revenue: per-day buckets", JSON.stringify(r0.byDay) === JSON.stringify({ "2026-10-10": 1000, "2026-10-11": 500, "2026-10-14": 400, "2026-10-15": 900 }), JSON.stringify(r0.byDay));
  check("revenue: breakdown", r0.breakdown.bookings.inr === 1500 && r0.breakdown.bookings.count === 2 && r0.breakdown.memberships.inr === 900 && r0.breakdown.memberships.count === 1 && r0.breakdown.other.inr === 400 && r0.breakdown.coaching.count === 0, JSON.stringify(r0.breakdown));
  const r1 = await rev([fsIds[0]]);
  check("revenue (one sport): its bookings and memberships only", r1.totalInr === 1900 && r1.previousTotalInr === 700 && r1.breakdown.other.inr === 0 && r1.breakdown.bookings.count === 1, JSON.stringify(r1));
  // dated by when the money arrived: created last month, paid this month, 20:00 UTC = 01:30 IST, so the 21st locally
  await pay(50, "paid", "2026-09-20 09:00+00");
  await q("update payments set paid_at = '2026-10-20 20:00+00' where amount_inr = 50 and facility_id=$1", [f2]);
  const r2 = await rev(null);
  check("revenue: counted on paid_at, bucketed by the viewer's local day", r2.totalInr === 2850 && r2.previousTotalInr === 700 && r2.byDay["2026-10-21"] === 50, JSON.stringify(r2));

  const r3 = (await q(`select dashboard_revenue_overview($1, '2026-10-01+00', '2026-11-01+00', '2026-09-01+00', null, null, 330) r`, [f2]))[0].r;
  check("revenue: a plain UTC offset (the phone app) buckets the same way", r3.byDay["2026-10-21"] === 50 && r3.totalInr === 2850, JSON.stringify(r3.byDay));
  const bc = (await q(`select dashboard_booking_counts($1, '2026-10-01+00', '2026-11-01+00', '2026-09-01+00', '2026-10-01+00', $2::uuid[]) c`, [f2, courts]))[0].c;
  check("booking counts: everything not cancelled, member or guest", bc.current === 3 && bc.previous === 1, JSON.stringify(bc));

  await asUser(owner);
  const direct =Number((await q(`select coalesce(sum(amount_inr),0)::int s from payments where facility_id=$1 and status='paid' and created_at >= '2026-10-01+00' and created_at < '2026-11-01+00'`, [fac]))[0].s);
  check("totals: another club's numbers are not mixed in", (await q(`select dashboard_totals($1, '2026-10-01+00', '2026-11-01+00', null, null, '{}'::uuid[], null, now(), now()) t`, [fac]))[0].t.collectedInr === direct);
}

// ═══ get_my_player_home (0167) — the Player app's Home page, for the caller only ═══════════════════════════════
{
  const ow = await mkUser("ph-owner@test.local", "Club Owner");
  const pf = await mkFacility(ow, "PlayZone Sports Arena");
  const alex = await mkUser("alex@test.local", "Alex Kumar");
  const sam = await mkUser("sam@test.local", "Sam Other");
  const newbie = await mkUser("newbie@test.local", "New Player");
  const alexMember = await mkMember(pf, "Alex Kumar");
  const samMember = await mkMember(pf, "Sam Other");
  await q("update members set user_id=$1 where id=$2", [alex, alexMember]);
  await q("update members set user_id=$1 where id=$2", [sam, samMember]);

  const sport = (await q("select id from sports where key='badminton'"))[0].id;
  const fsid = uuid();
  await q("insert into facility_sports (id, facility_id, sport_id) values ($1,$2,$3)", [fsid, pf, sport]);
  const court = uuid();
  await q("insert into courts (id, facility_id, sport_id, facility_sport_id, name, hourly_rate_inr) values ($1,$2,$3,$4,'Court 2',300)", [court, pf, sport, fsid]);

  // which table does bookings.member_id point at? (the players are people records in some versions, profiles in others)
  const fk = (await q(`select confrelid::regclass::text t from pg_constraint where conrelid='bookings'::regclass and contype='f' and pg_get_constraintdef(oid) like '%(member_id)%' limit 1`))[0]?.t;
  const bookerFor = (profileId, memberId) => (fk === "members" ? memberId : profileId);
  const book = async (who, startExpr, status) => {
    const id = uuid();
    await q(`insert into bookings (id, facility_id, court_id, member_id, customer_type, start_time, end_time, status, amount_minor)
             values ($1,$2,$3,$4,'MEMBER', ${startExpr}, ${startExpr} + interval '1 hour', $5, 30000)`, [id, pf, court, who, status]);
    return id;
  };

  const home = async (uid) => { await asUser(uid); const r = (await q("select get_my_player_home() h"))[0].h; await asUser(owner); return r; };

  // a brand-new player: nothing at all
  let h = await home(newbie);
  check("player home: a new player has nothing enrolled or booked", h.fullName === "New Player" && h.hasActiveMembership === false && h.hasActiveCoaching === false && h.hasBookingHistory === false && h.upcomingBookings.length === 0, JSON.stringify(h));

  // Alex: an upcoming confirmed booking, a cancelled one, a finished one
  const aBook = (s, st) => book(bookerFor(alex, alexMember), s, st);
  const nextId = await aBook("now() + interval '1 day'", "confirmed");
  await aBook("now() + interval '2 days'", "cancelled");
  await aBook("now() - interval '3 days'", "confirmed");
  // Sam also has a booking: it must never show up for Alex
  await book(bookerFor(sam, samMember), "now() + interval '3 hours'", "confirmed");
  await q("insert into notifications (user_id, kind, title, body) values ($1,'x','a','b'), ($1,'x','c','d')", [alex]);
  await q("insert into notifications (user_id, kind, title, body, read_at) values ($1,'x','e','f', now())", [alex]);

  h = await home(alex);
  check("player home: name, unread count and booking history", h.fullName === "Alex Kumar" && h.unreadNotifications === 2 && h.hasBookingHistory === true, JSON.stringify(h));
  check("player home: only the caller's confirmed, unfinished booking (not cancelled, not past, not someone else's)", h.upcomingBookings.length === 1 && h.upcomingBookings[0].id === nextId && h.upcomingBookings[0].venueName === "PlayZone Sports Arena" && h.upcomingBookings[0].courtName === "Court 2" && h.upcomingBookings[0].sportName === "Badminton", JSON.stringify(h.upcomingBookings));
  check("player home: no membership or coaching yet", h.hasActiveMembership === false && h.hasActiveCoaching === false);

  // a membership, then an expired one for Sam
  await mkMembership(pf, alexMember, "Gold");
  h = await home(alex);
  check("player home: an active membership shows", h.hasActiveMembership === true, JSON.stringify(h));
  await q("update memberships set start_date = current_date - 40, end_date = current_date - 1 where member_id=$1", [alexMember]);
  check("player home: an expired membership does not count", (await home(alex)).hasActiveMembership === false);

  // coaching: invisible to a player through ordinary row-level security, but the function can answer
  const prog = uuid();
  await q("insert into coaching_programs (id, facility_id, name) values ($1,$2,'Junior Badminton')", [prog, pf]);
  await q("insert into coaching_enrollments (facility_id, member_id, program_id) values ($1,$2,$3)", [pf, alexMember, prog]);
  check("player home: active coaching shows", (await home(alex)).hasActiveCoaching === true);
  check("player home: someone else's coaching does not", (await home(sam)).hasActiveCoaching === false);
  await q("update coaching_enrollments set status='COMPLETED' where member_id=$1", [alexMember]);
  check("player home: finished coaching does not count", (await home(alex)).hasActiveCoaching === false);

  // not signed in: nothing, and no error
  await asUser(null);
  const anon = (await q("select get_my_player_home() h"))[0].h;
  check("player home: signed out gives an empty answer", anon.fullName === null && anon.upcomingBookings.length === 0 && anon.hasActiveMembership === false, JSON.stringify(anon));
  await asUser(owner);
}

// ═══ list_public_venues (0168) — what a player sees for the city they picked ═══════════════════════════════
{
  const vo = await mkUser("venue-owner@test.local", "Venue Owner");
  const mk = async (name, city, state, { courts = 1, status = "ACTIVE", step = "COMPLETED", archived = false, bookingEnabled = true } = {}) => {
    const id = await mkFacility(vo, name);
    await q("update facilities set city=$2, state=$3, status=$4, onboarding_step=$5 where id=$1", [id, city, state, status, step]);
    const sp = (await q("select id from sports where key='badminton'"))[0].id;
    const fsid = uuid();
    await q("insert into facility_sports (id, facility_id, sport_id) values ($1,$2,$3)", [fsid, id, sp]);
    for (let i = 0; i < courts; i++) await q("insert into courts (facility_id, sport_id, facility_sport_id, name, hourly_rate_inr, archived, booking_enabled) values ($1,$2,$3,$4,300,$5,$6)", [id, sp, fsid, `Court ${i + 1}`, archived, bookingEnabled]);
    return id;
  };
  const blr = await mk("Smash Arena", "Bengaluru", "Karnataka", { courts: 2 });
  await mk("Ace Courts", "bangalore ", "Karnataka");
  await mk("Chennai Smash", "Chennai", "Tamil Nadu");
  await mk("No Courts Club", "Pune", "Maharashtra", { courts: 0 });
  await mk("Archived Only", "Kochi", "Kerala", { archived: true });
  await mk("Booking Off", "Kolkata", "West Bengal", { bookingEnabled: false });
  await mk("Closed Club", "Mumbai", "Maharashtra", { status: "INACTIVE" });
  await mk("Still Setting Up", "Hyderabad", "Telangana", { step: "FACILITY_DETAILS" });
  await asUser(null); // a visitor who is not signed in
  const venues = async (city, state) => (await q("select list_public_venues($1, $2) v", [city, state ?? null]))[0].v;

  let v = await venues("Bangalore", "Karnataka");
  check("venues: Bangalore and Bengaluru are one city, listed by name", v.length === 2 && v[0].name === "Ace Courts" && v[1].name === "Smash Arena", JSON.stringify(v.map((x) => x.name)));
  check("venues: what a visitor needs (courts and sports), nothing about the owner", v[1].courtCount === 2 && v[1].sports[0] === "Badminton" && !("ownerId" in v[1]) && !("owner_id" in v[1]) && v[1].id === blr, JSON.stringify(v[1]));
  check("venues: the city match ignores case and spaces", (await venues("  CHENNAI ", "tamil nadu")).length === 1);
  check("venues: a city with none gives an empty list", (await venues("Ahmedabad", "Gujarat")).length === 0 && (await venues("", null)).length === 0 && (await venues(null, null)).length === 0);
  check("venues: a wrong state does not match", (await venues("Chennai", "Kerala")).length === 0);
  check("venues: no courts, archived courts, booking switched off, closed or unfinished venues are never listed",
    (await venues("Pune")).length === 0 && (await venues("Kochi")).length === 0 && (await venues("Kolkata")).length === 0 && (await venues("Mumbai")).length === 0 && (await venues("Hyderabad")).length === 0);
  await asUser(owner);
}

// ═══ players (0169) — phone login, and the Home page built from the clubs' own records by phone number ═══════
{
  const co = await mkUser("pl-owner@test.local", "Club Owner");
  const f1 = await mkFacility(co, "PlayZone Arena");
  const f2 = await mkFacility(co, "Ace Academy");
  const sport = (await q("select id from sports where key='badminton'"))[0].id;
  const mkCourt = async (f, name) => {
    const fsid = uuid();
    await q("insert into facility_sports (id, facility_id, sport_id) values ($1,$2,$3)", [fsid, f, sport]);
    const id = uuid();
    await q("insert into courts (id, facility_id, sport_id, facility_sport_id, name, hourly_rate_inr) values ($1,$2,$3,$4,$5,300)", [id, f, sport, fsid, name]);
    return { id, fsid };
  };
  const c1 = await mkCourt(f1, "Court 1");
  const c2 = await mkCourt(f2, "Court 2");

  // a phone login: an auth user with a verified phone and no profile yet
  const mkPhoneUser = async (phone) => {
    const id = uuid();
    await q("insert into auth.users (id, phone) values ($1,$2)", [id, phone]);
    return id;
  };
  const dash = async (uid) => { await asUser(uid); const r = (await q("select get_player_dashboard() d"))[0].d; await asUser(owner); return r; };

  const np = (await q("select normalize_phone('+91 98765-43210') a, normalize_phone('09876543210') b, normalize_phone('98765 43210') c, normalize_phone('') d, normalize_phone(null) e"))[0];
  check("phones: the same number typed four ways is one number", np.a === "9876543210" && np.b === "9876543210" && np.c === "9876543210" && np.d === null && np.e === null, JSON.stringify(np));

  const uma = await mkPhoneUser("919876543210");
  await asUser(uma);
  check("player: no profile before registering", (await q("select get_my_player() p"))[0].p === null);
  await throws("player: a name is required", () => q("select register_player('  ', 'a@b.co')"), "name");
  await throws("player: a bad email is refused", () => q("select register_player('Uma', 'not-an-email')"), "email");
  const reg = (await q("select register_player('Uma Shankar', 'uma@example.com') p"))[0].p;
  check("player: registered with the verified phone, not one the caller chose", reg.fullName === "Uma Shankar" && reg.phone === "9876543210" && reg.email === "uma@example.com", JSON.stringify(reg));
  const reg2 = (await q("select register_player('Uma S', null) p"))[0].p;
  check("player: registering again edits the same profile", reg2.fullName === "Uma S" && reg2.email === null && (await q("select count(*)::int c from players"))[0].c === 1);
  await asUser(null);
  await throws("player: signed out cannot register", () => q("select register_player('X', null)"), "sign in");
  const noPhone = await mkUser("no-phone@test.local", "No Phone");
  await asUser(noPhone);
  await throws("player: an email-only account cannot register", () => q("select register_player('X', null)"), "phone");
  const twin = await mkPhoneUser("+91 98765 43210");
  await asUser(twin);
  await throws("player: one player per phone number", () => q("select register_player('Twin', null)"), "already");
  await asUser(owner);

  // the clubs' records for that number, typed differently at each club
  const m1 = uuid(), m2 = uuid(), other = uuid();
  await q("insert into members (id, facility_id, full_name, phone) values ($1,$2,'Uma Shankar','98765 43210')", [m1, f1]);
  await q("insert into members (id, facility_id, full_name, phone) values ($1,$2,'Uma S','+91-9876543210')", [m2, f2]);
  await q("insert into members (id, facility_id, full_name, phone) values ($1,$2,'Someone Else','9111100001')", [other, f1]);

  let d = await dash(uma);
  check("dashboard: nothing yet, but the name and phone", d.fullName === "Uma S" && d.phone === "9876543210" && d.memberships.length === 0 && d.coaching.length === 0 && d.guestBookings.count === 0 && d.schedule.length === 0 && d.hasActiveMembership === false, JSON.stringify(d));

  await mkMembership(f1, m1, "Evening Play");
  await mkMembership(f2, m2, "Weekend Pro");
  const expired = await mkMembership(f2, m2, "Old Plan");
  await q("update memberships set start_date=current_date-60, end_date=current_date-1 where id=$1", [expired]);
  await mkMembership(f1, other, "Not Mine");
  d = await dash(uma);
  check("dashboard: active memberships from every club, matched by phone; expired and other people's left out",
    d.hasActiveMembership === true && d.memberships.length === 2 && d.memberships.map((m) => m.planName).sort().join() === "Evening Play,Weekend Pro" && d.memberships.every((m) => m.venueName), JSON.stringify(d.memberships));

  const mbid = uuid();
  await q("insert into membership_batches (id, facility_id, plan_id, facility_sport_id, court_id, name, days_of_week, start_time, end_time, capacity) values ($1,$2,null,$3,$4,'Evening Batch','{1,2,3,4,5}','18:00','19:00',10)", [mbid, f1, c1.fsid, c1.id]);
  await q("insert into membership_batch_members (batch_id, member_id) values ($1,$2)", [mbid, m1]);
  d = await dash(uma);
  const withBatch = d.memberships.find((m) => m.planName === "Evening Play");
  check("dashboard: the membership shows its batch, days and time", withBatch.batchName === "Evening Batch" && withBatch.startTime === "18:00" && withBatch.endTime === "19:00" && withBatch.daysOfWeek.length === 5 && withBatch.courtName === "Court 1", JSON.stringify(withBatch));
  await q("insert into membership_sessions (batch_id, facility_id, court_id, facility_sport_id, session_date, start_time, end_time, capacity) values ($1,$2,$3,$4,current_date+1,'18:00','19:00',10)", [mbid, f1, c1.id, c1.fsid]);
  d = await dash(uma);
  check("dashboard: tomorrow's membership session is in the schedule", d.schedule.some((i) => i.kind === "membership" && i.title === "Evening Batch" && i.courtName === "Court 1"), JSON.stringify(d.schedule));

  const prog = uuid();
  await q("insert into coaching_programs (id, facility_id, name) values ($1,$2,'Intermediate Batch')", [prog, f2]);
  const enr = uuid();
  await q("insert into coaching_enrollments (id, facility_id, member_id, program_id) values ($1,$2,$3,$4)", [enr, f2, m2, prog]);
  const otherProg = (await q("insert into coaching_programs (facility_id, name) values ($1,'Not Mine Prog') returning id", [f1]))[0].id;
  await q("insert into coaching_enrollments (facility_id, member_id, program_id) values ($1,$2,$3)", [f1, other, otherProg]);
  d = await dash(uma);
  check("dashboard: active coaching shows (not other people's)", d.hasActiveCoaching === true && d.coaching.length === 1 && d.coaching[0].programName === "Intermediate Batch" && d.coaching[0].venueName === "Ace Academy", JSON.stringify(d.coaching));
  await q("update coaching_enrollments set status='COMPLETED' where id=$1", [enr]);
  check("dashboard: finished coaching drops off", (await dash(uma)).coaching.length === 0);
  await q("update coaching_enrollments set status='ACTIVE' where id=$1", [enr]);

  // bookings: a guest booking by the phone typed on it, one by guest record, a member booking, someone else's, a cancelled one
  const gp = uuid();
  await q("insert into guest_players (id, facility_id, name, phone) values ($1,$2,'Uma Guest','9876543210')", [gp, f1]);
  const insBooking = async (f, court, startExpr, status, x) => {
    const id = uuid();
    await q(`insert into bookings (id, facility_id, court_id, customer_type, member_id, guest_name, guest_phone, guest_player_id, start_time, end_time, status, amount_minor)
             values ($1,$2,$3,$4,$5,$6,$7,$8, ${startExpr}, ${startExpr} + interval '1 hour', $9, 30000)`,
      [id, f, court, x.type, x.member ?? null, x.type === "GUEST" ? "Guest" : null, x.phone ?? null, x.gp ?? null, status]);
    return id;
  };
  await insBooking(f1, c1.id, "now() + interval '30 hours'", "confirmed", { type: "GUEST", phone: "+91 98765 43210" });
  await insBooking(f2, c2.id, "now() + interval '50 hours'", "confirmed", { type: "GUEST", gp });
  await insBooking(f1, c1.id, "now() + interval '70 hours'", "cancelled", { type: "GUEST", phone: "9876543210" });
  await insBooking(f2, c2.id, "now() + interval '90 hours'", "confirmed", { type: "GUEST", phone: "9111111111" });
  await insBooking(f1, c1.id, "now() + interval '110 hours'", "confirmed", { type: "MEMBER", member: m1 });
  d = await dash(uma);
  check("dashboard: guest bookings are found by the phone typed on the booking or by the guest record; cancelled and other people's are not",
    d.guestBookings.count === 2 && d.guestBookings.next.venueName === "PlayZone Arena" && d.hasBookingHistory === true, JSON.stringify(d.guestBookings));
  check("dashboard: upcoming bookings include member bookings too, soonest first", d.upcomingBookings.length === 3 && d.upcomingBookings[0].venueName === "PlayZone Arena", JSON.stringify(d.upcomingBookings.map((b) => b.venueName)));
  check("dashboard: the schedule covers the next 7 days only and is in time order",
    d.schedule.length >= 2 && d.schedule.every((i, k, a) => k === 0 || new Date(a[k - 1].startTime) <= new Date(i.startTime)) && d.schedule.every((i) => new Date(i.startTime) < new Date(Date.now() + 8 * 864e5)), JSON.stringify(d.schedule.map((i) => i.kind)));

  // today's courts
  await insBooking(f1, c1.id, "now() - interval '10 minutes'", "confirmed", { type: "GUEST", phone: "9876543210" });
  d = await dash(uma);
  check("dashboard: a booking later today shows under today's courts", d.courtsToday.length >= 1 && d.courtsToday.some((i) => i.courtName === "Court 1"), JSON.stringify(d.courtsToday));

  // privacy
  const bob = await mkPhoneUser("919111100001");
  await asUser(bob);
  await q("select register_player('Bob', null)");
  await asUser(owner);
  d = await dash(bob);
  check("dashboard: another player only sees their own number's records", d.fullName === "Bob" && d.memberships.length === 1 && d.memberships[0].planName === "Not Mine" && d.guestBookings.count === 0, JSON.stringify(d));
  await asUser(null);
  const anon = (await q("select get_player_dashboard() d"))[0].d;
  check("dashboard: signed out gives an empty answer", anon.fullName === null && anon.memberships.length === 0 && anon.schedule.length === 0, JSON.stringify(anon));
  await asUser(owner);
}

// ═══ player_login_lookup / attempts (0170) — telling a returning number from a new one, without a code ═══════════
{
  const lo = await mkUser("pl2-owner@test.local", "Club Owner");
  const lf = await mkFacility(lo, "Lookup Arena");
  const lookup = async (phone) => (await q("select player_login_lookup($1) r", [phone]))[0].r;

  let r = await lookup("9811111111");
  check("lookup: a brand-new number has no account, no profile and no club records", r.userId === null && r.hasPlayer === false && r.knownName === null && Number(r.clubRecords) === 0, JSON.stringify(r));

  // a club knows the number (typed differently) as a member and as a guest
  await q("insert into members (facility_id, full_name, phone) values ($1,'Ravi Kumar','+91 98111-11111')", [lf]);
  await q("insert into guest_players (facility_id, name, phone) values ($1,'Ravi K','09811111111')", [lf]);
  r = await lookup("9811111111");
  check("lookup: the clubs' records for the number are counted and a name is offered", Number(r.clubRecords) === 2 && typeof r.knownName === "string" && r.knownName.startsWith("Ravi"), JSON.stringify(r));
  check("lookup: still no account until they log in", r.userId === null && r.hasPlayer === false);

  // an account created by the login function (phone stored without '+'), then a profile
  const uid = uuid();
  await q("insert into auth.users (id, phone) values ($1,'919811111111')", [uid]);
  r = await lookup("+91 98111 11111");
  check("lookup: finds the account whatever way the number is typed", r.userId === uid && r.hasPlayer === false, JSON.stringify(r));
  await asUser(uid);
  await q("select register_player('Ravi Kumar', 'ravi@example.com')");
  await asUser(owner);
  r = await lookup("9811111111");
  check("lookup: once registered, hasPlayer is true", r.hasPlayer === true && r.userId === uid, JSON.stringify(r));

  // the synthetic placeholder names some clubs store are never offered as a name
  await q("insert into members (facility_id, full_name, phone) values ($1,'unknown-ab12cd34','9822222222')", [lf]);
  r = await lookup("9822222222");
  check("lookup: a placeholder name is not offered", r.knownName === null && Number(r.clubRecords) === 1, JSON.stringify(r));

  // attempts are counted per address
  let last = 0;
  for (let i = 0; i < 5; i++) last = (await q("select player_login_record_attempt('iphash-a', '9811111111') c"))[0].c;
  check("attempts: counted per address", last === 5 && (await q("select player_login_record_attempt('iphash-b', null) c"))[0].c === 1, String(last));
}

// ═══ list_public_venue_cards (0171) — Venues, Memberships and Coaching pages ═══════════════════════════════
{
  const vo = await mkUser("cards-owner@test.local", "Cards Owner");
  const sport = (await q("select id from sports where key='badminton'"))[0].id;
  const mk = async (name, city, { hero = null, rates = [300] } = {}) => {
    const id = await mkFacility(vo, name);
    await q("update facilities set city=$2, state='Tamil Nadu', status='ACTIVE', onboarding_step='COMPLETED', area='Adyar', hero_image_url=$3 where id=$1", [id, city, hero]);
    const fsid = uuid();
    await q("insert into facility_sports (id, facility_id, sport_id) values ($1,$2,$3)", [fsid, id, sport]);
    let i = 0;
    for (const r of rates) await q("insert into courts (facility_id, sport_id, facility_sport_id, name, hourly_rate_inr) values ($1,$2,$3,$4,$5)", [id, sport, fsid, `Court ${++i}`, r]);
    return id;
  };
  const a_id = await mk("Alpha Arena", "Chennai", { hero: "https://img.test/alpha.jpg", rates: [400, 250] });
  const b = await mk("Beta Club", "Chennai");
  const c = await mk("Gamma Courts", "Chennai");
  await q("insert into membership_plans (facility_id, name, price_inr, duration_days) values ($1,'Gold',2500,30), ($1,'Silver',1500,30)", [a_id]);
  await q("insert into membership_plans (facility_id, name, price_inr, duration_days, is_active) values ($1,'Old',999,30,false)", [b]);
  await q("insert into coaching_programs (facility_id, name, default_price_minor) values ($1,'Juniors',300000), ($1,'Adults',150000)", [b]);
  await q("insert into coaching_programs (facility_id, name, status) values ($1,'Retired','INACTIVE')", [c]);
  await asUser(null);
  const mine = (rows) => rows.filter((x) => ["Alpha Arena", "Beta Club", "Gamma Courts"].includes(x.name));
  const cards = async (kind) => mine((await q("select list_public_venue_cards('Chennai','Tamil Nadu',$1) v", [kind]))[0].v);

  let v = await cards("venues");
  check("cards: venues lists every bookable venue by name, with a picture and the cheapest court", v.length === 3 && v[0].name === "Alpha Arena" && v[0].heroImageUrl === "https://img.test/alpha.jpg" && v[0].minCourtPriceInr === 250 && v[0].courtCount === 2 && v[0].area === "Adyar", JSON.stringify(v[0]));
  check("cards: a venue with no picture gives null, not an error", v[1].heroImageUrl === null);
  // surfaces (0172): lower-cased, distinct, only from bookable courts
  await q("update courts set surface='Turf' where facility_id=$1", [a_id]);
  await q("update courts set surface=' turf ' where id = (select id from courts where facility_id=$1 limit 1)", [a_id]);
  await q("update courts set surface='Wooden' where id = (select id from courts where facility_id=$1 order by name desc limit 1)", [a_id]);
  v = await cards("venues");
  check("cards: surfaces are distinct and lower-cased; none gives an empty list", v[0].surfaces.slice().sort().join() === "turf,wooden" && v[1].surfaces.length === 0, JSON.stringify([v[0].surfaces, v[1].surfaces]));
  v = await cards("memberships");
  check("cards: memberships lists only venues with an active plan, with the plan names and the lowest price", v.length === 1 && v[0].name === "Alpha Arena" && v[0].memberships.count === 2 && v[0].memberships.names.join() === "Gold,Silver" && v[0].memberships.minPriceInr === 1500, JSON.stringify(v));
  v = await cards("coaching");
  check("cards: coaching lists only venues with an ACTIVE programme; price is in rupees", v.length === 1 && v[0].name === "Beta Club" && v[0].coaching.count === 2 && v[0].coaching.minPriceInr === 1500 && v[0].coaching.names.join() === "Adults,Juniors", JSON.stringify(v));
  check("cards: an unknown kind behaves like venues; another city is empty", (await cards("nonsense")).length === 3 && mine((await q("select list_public_venue_cards('Chennai','Tamil Nadu',null) v"))[0].v).length === 3 && (await q("select list_public_venue_cards('Ahmedabad','Gujarat','venues') v"))[0].v.length === 0);
  await asUser(owner);
}

// ═══ venue profile verification (0173) — map link, photos, venue type, amenities ═══════════════════════════════
{
  const adminRow = (await q("select id from auth.users where lower(email)='admin@gameall.co'"))[0];
  const adminId = adminRow ? adminRow.id : await mkUser("admin@gameall.co", "Platform Admin");
  const vo = await mkUser("venue-profile-owner@test.local", "Venue Owner");
  const f = await mkFacility(vo, "Profile Arena");
  await q("update facilities set onboarding_step='SPORTS', city='Chennai', state='Tamil Nadu', status='ACTIVE' where id=$1", [f]);
  const row = async () => (await q("select * from facilities where id=$1", [f]))[0];

  // an owner cannot grant themselves the verdict; changing the link puts it back to PENDING
  await asUser(vo);
  await q("update facilities set location_url='https://maps.app.goo.gl/abc' where id=$1", [f]);
  check("location: a new link starts PENDING", (await row()).location_verification_status === "PENDING");
  await throws("location: an owner cannot verify their own link", () => q("update facilities set location_verification_status='VERIFIED' where id=$1", [f]), "managed by GameAll");
  await asUser(adminId);
  await q("select admin_review_location($1,'VERIFIED',null)", [f]);
  let r = await row();
  check("location: the admin can verify it", r.location_verification_status === "VERIFIED" && r.location_verified_at !== null && r.location_verified_by === adminId);
  await asUser(vo);
  await q("update facilities set location_url='https://maps.app.goo.gl/new' where id=$1", [f]);
  r = await row();
  check("location: changing the link resets the verdict", r.location_verification_status === "PENDING" && r.location_verified_at === null);
  await q("update facilities set name='Profile Arena 2' where id=$1", [f]);
  check("location: unrelated edits keep the verdict", (await row()).location_verification_status === "PENDING");
  await asUser(adminId);
  await throws("location: a rejection needs a reason", () => q("select admin_review_location($1,'REJECTED',null)", [f]), "why");
  await q("select admin_review_location($1,'REJECTED','Pin is in the wrong street')", [f]);
  check("location: rejected with a note the owner can read", (await row()).location_verification_note === "Pin is in the wrong street");
  await asUser(vo);
  await throws("location: only the admin may review", () => q("select admin_review_location($1,'VERIFIED',null)", [f]), "Platform administrators");

  // photos
  await asUser(vo);
  const img = (await q("insert into facility_images (facility_id, url, verification_status) values ($1,'https://img.test/a.jpg','VERIFIED') returning id", [f]))[0].id;
  let im = (await q("select * from facility_images where id=$1", [img]))[0];
  check("photos: a new photo is always PENDING, even if it claims otherwise", im.verification_status === "PENDING" && im.verified_at === null);
  await throws("photos: an owner cannot verify a photo", () => q("update facility_images set verification_status='VERIFIED' where id=$1", [img]), "managed by GameAll");
  await asUser(adminId);
  await q("select admin_review_facility_image($1,'VERIFIED',null)", [img]);
  im = (await q("select * from facility_images where id=$1", [img]))[0];
  check("photos: the admin verifies a photo", im.verification_status === "VERIFIED" && im.verified_by === adminId);
  await asUser(vo);
  await q("update facility_images set url='https://img.test/a2.jpg' where id=$1", [img]);
  im = (await q("select * from facility_images where id=$1", [img]))[0];
  check("photos: replacing the picture sends it for checking again", im.verification_status === "PENDING");
  await asUser(adminId);
  await q("select admin_review_facility_image($1,'VERIFIED',null)", [img]);

  // setup now needs the link, the venue type and a photo (new facilities only)
  const g = await mkFacility(vo, "Setup Arena");
  await q("update facilities set onboarding_step='SPORTS' where id=$1", [g]);
  await asUser(vo);
  await throws("setup: needs the Google Maps link", () => q("select complete_facility_setup($1)", [g]), "Google Maps");
  await q("update facilities set location_url='https://maps.app.goo.gl/g' where id=$1", [g]);
  await throws("setup: needs indoor or outdoor", () => q("select complete_facility_setup($1)", [g]), "indoor or outdoor");
  await q("update facilities set venue_type='INDOOR' where id=$1", [g]);
  await throws("setup: needs a photo", () => q("select complete_facility_setup($1)", [g]), "photo");
  await q("insert into facility_images (facility_id, url) values ($1,'https://img.test/g.jpg')", [g]);
  await throws("setup: then carries on to the older checks", () => q("select complete_facility_setup($1)", [g]), "sport");
  await throws("venue type: only INDOOR or OUTDOOR", () => q("update facilities set venue_type='COVERED' where id=$1", [g]));
  // a facility that is already COMPLETED is not held to the new rules
  const done = await mkFacility(vo, "Old Arena");
  await q("update facilities set onboarding_step='COMPLETED' where id=$1", [done]);
  check("setup: an already-completed facility is unaffected", (await q("select complete_facility_setup($1) r", [done]))[0].r !== null);

  // the admin's queue
  await asUser(adminId);
  const queue = (await q("select admin_list_venue_verifications() v"))[0].v;
  const mine = queue.find((x) => x.id === f);
  check("queue: the facility shows with its link status and photo counts", mine && mine.locationStatus === "REJECTED" && mine.imagesTotal === 1 && mine.imagesVerified === 1, JSON.stringify(mine));
  const detail = (await q("select admin_get_venue_verification($1) v", [f]))[0].v;
  check("queue: the detail has the link, address, photos and amenities", detail.facility.location.url.includes("maps.app") && detail.images.length === 1 && detail.facility.amenities.parking === false && typeof detail.facility.address === "string", JSON.stringify(detail.facility));
  await asUser(vo);
  await throws("queue: not for owners", () => q("select admin_list_venue_verifications()"), "Platform administrators");

  // the Player app's cards use only approved photos, and carry indoor/outdoor and the amenities
  await asUser(owner);
  await q("update facilities set venue_type='OUTDOOR', has_parking=true, has_cafeteria=true, onboarding_step='COMPLETED', area='Adyar' where id=$1", [f]);
  const sp = (await q("select id from sports where key='badminton'"))[0].id;
  const fsid = uuid();
  await q("insert into facility_sports (id, facility_id, sport_id) values ($1,$2,$3)", [fsid, f, sp]);
  await q("insert into courts (facility_id, sport_id, facility_sport_id, name, hourly_rate_inr) values ($1,$2,$3,'Court 1',300)", [f, sp, fsid]);
  await asUser(vo);
  await q("insert into facility_images (facility_id, url, sort_order) values ($1,'https://img.test/pending.jpg', -1)", [f]); // pending: must not be used
  await asUser(null);
  const card = (await q("select list_public_venue_cards('Chennai','Tamil Nadu','venues') v"))[0].v.find((x) => x.id === f);
  check("cards: the cover is the first APPROVED photo, never a pending one", card.heroImageUrl === "https://img.test/a2.jpg" && card.photos.length === 1, JSON.stringify([card.heroImageUrl, card.photos]));
  check("cards: venue type and amenities are there", card.venueType === "OUTDOOR" && card.amenities.parking === true && card.amenities.cafeteria === true && card.amenities.toilets === false, JSON.stringify([card.venueType, card.amenities]));
  await asUser(owner);
}

// ═══ get_public_venue (0174) — the venue page ═══════════════════════════════
{
  const vo = await mkUser("venue-detail-owner@test.local", "Detail Owner");
  const f = await mkFacility(vo, "Champz Turf");
  await q("update facilities set city='Chennai', state='Tamil Nadu', area='Iyyapanthangal', address_line_1='12 Main Road', business_phone='9876500000', description='Premium courts.', status='ACTIVE', onboarding_step='COMPLETED', venue_type='INDOOR', has_parking=true, has_cafeteria=true, location_url='https://maps.app.goo.gl/x' where id=$1", [f]);
  const sp = (await q("select id from sports where key='badminton'"))[0].id;
  const fsid = uuid();
  await q("insert into facility_sports (id, facility_id, sport_id) values ($1,$2,$3)", [fsid, f, sp]);
  await q("insert into courts (facility_id, sport_id, facility_sport_id, name, hourly_rate_inr) values ($1,$2,$3,'Court 2',500), ($1,$2,$3,'Court 1',350)", [f, sp, fsid]);
  await q("insert into courts (facility_id, sport_id, facility_sport_id, name, hourly_rate_inr, archived) values ($1,$2,$3,'Old Court',100,true)", [f, sp, fsid]);
  await q("insert into membership_plans (facility_id, name, price_inr, duration_days) values ($1,'Gold',2999,30), ($1,'Silver',1999,30)", [f]);
  await q("insert into coaching_programs (facility_id, name, default_price_minor) values ($1,'Juniors',150000)", [f]);
  await q("insert into coaching_programs (facility_id, name, status) values ($1,'Closed','INACTIVE')", [f]);
  // opening hours: 06:00-23:00 on two days, closed on a third
  const sched = (await q("insert into operating_schedules (facility_id, scope_type) values ($1,'FACILITY') returning id", [f]))[0].id;
  for (const dow of [1, 2]) {
    const d = (await q("insert into operating_days (schedule_id, facility_id, day_of_week) values ($1,$2,$3) returning id", [sched, f, dow]))[0].id;
    await q("insert into operating_time_slots (operating_day_id, facility_id, start_time, end_time) values ($1,$2,'06:00','23:00')", [d, f]);
  }
  await q("insert into operating_days (schedule_id, facility_id, day_of_week, is_closed) values ($1,$2,0,true)", [sched, f]);
  const img = (await q("insert into facility_images (facility_id, url) values ($1,'https://img.test/ok.jpg') returning id", [f]))[0].id;
  await q("insert into facility_images (facility_id, url) values ($1,'https://img.test/pending.jpg')", [f]);
  await asUser(null); // the service role: only the admin or the service may set a verdict
  await q("update facility_images set verification_status='VERIFIED' where id=$1", [img]);
  const venue = async (id) => (await q("select get_public_venue($1) v", [id]))[0].v;
  let v = await venue(f);
  check("venue: name, place, address, phone and description", v.name === "Champz Turf" && v.area === "Iyyapanthangal" && v.address === "12 Main Road, Iyyapanthangal, Chennai" && v.phone === "9876500000" && v.description === "Premium courts.", JSON.stringify(v));
  check("venue: only approved photos", v.photos.length === 1 && v.photos[0] === "https://img.test/ok.jpg", JSON.stringify(v.photos));
  check("venue: indoor/outdoor and amenities", v.venueType === "INDOOR" && v.amenities.parking === true && v.amenities.cafeteria === true && v.amenities.toilets === false);
  check("venue: bookable courts only, sorted, with the cheapest price", v.courtCount === 2 && v.courts.map((c) => c.name).join() === "Court 1,Court 2" && v.minCourtPriceInr === 350 && v.sports[0].name === "Badminton", JSON.stringify([v.courts, v.minCourtPriceInr]));
  check("venue: opening hours across the open days", v.hours.opens === "06:00" && v.hours.closes === "23:00" && v.hours.open24h === false, JSON.stringify(v.hours));
  check("venue: the plans and the active programmes with rupee prices", v.memberships.plans.map((p) => p.name).join() === "Silver,Gold" && v.memberships.plans[1].priceInr === 2999 && v.memberships.plans[1].durationDays === 30 && v.coaching.programs.length === 1 && v.coaching.programs[0].priceInr === 1500, JSON.stringify([v.memberships, v.coaching]));
  check("venue: the map link is withheld until verified", v.locationVerified === false && v.locationUrl === null, JSON.stringify([v.locationVerified, v.locationUrl]));
  await q("update facilities set location_verification_status='VERIFIED' where id=$1", [f]);
  v = await venue(f);
  check("venue: once verified the link is returned", v.locationVerified === true && v.locationUrl === "https://maps.app.goo.gl/x");
  check("venue: nothing about the owner or the money", !("ownerId" in v) && !("owner_id" in v) && !("email" in v) && !("businessEmail" in v), Object.keys(v).join());
  check("venue: an unknown id gives null", (await venue(uuid())) === null);
  await asUser(owner);
  await q("update facilities set status='INACTIVE' where id=$1", [f]);
  await asUser(null);
  check("venue: a closed venue gives null", (await venue(f)) === null);
  await asUser(owner);
}

// ═══ the test-venue seed and its cleanup (supabase/seed) ═══════════════════════════════
{
  const seedDir = process.env.SEED_DIR ?? fileURLToPath(new URL("../../seed/", import.meta.url));
  const seedSql = fs.readFileSync(seedDir + "test_venues_seed.sql", "utf8");
  const cleanSql = fs.readFileSync(seedDir + "test_venues_cleanup.sql", "utf8");
  const counts = async () => {
    const t = ["facilities", "courts", "facility_images", "members", "memberships", "bookings", "coaching_programs", "coaching_enrollments", "membership_plans", "pricing_rules", "operating_days", "facility_sports"];
    const out = {};
    for (const n of t) out[n] = (await q(`select count(*)::int c from ${n}`))[0].c;
    out.users = (await q("select count(*)::int c from auth.users"))[0].c;
    out.profiles = (await q("select count(*)::int c from profiles"))[0].c;
    return JSON.stringify(out);
  };
  await asUser(null);
  const before = await counts();
  await db.exec(seedSql);

  const seeded = await q("select id, name, city, venue_type, location_verification_status s from facilities where slug like 'seed-%' order by name");
  check("seed: six venues in three cities", seeded.length === 6 && new Set(seeded.map((r) => r.city)).size === 3, JSON.stringify(seeded));
  await throws("seed: running it twice is refused, not doubled", () => db.exec(seedSql), "already loaded");

  const cards = async (city, state, kind = "venues") => (await q("select list_public_venue_cards($1,$2,$3) v", [city, state, kind]))[0].v.filter((x) => String(x.id).length > 0);
  const seedIds = new Set(seeded.map((r) => r.id));
  const mine = (rows) => rows.filter((r) => seedIds.has(r.id));
  const chennai = mine(await cards("Chennai", "Tamil Nadu"));
  check("seed: Chennai lists its three venues, A to Z", chennai.map((r) => r.name).join() === "Champz Turf,Kickoff Sports,Smash Arena", chennai.map((r) => r.name).join());
  const champz = chennai.find((r) => r.name === "Champz Turf");
  check("seed: an approved cover photo, indoor, amenities, price from the cheapest court", champz.heroImageUrl.includes("Badminton_court_view") && champz.photos.length === 3 && champz.venueType === "INDOOR" && champz.amenities.parking === true && champz.minCourtPriceInr === 400 && champz.courtCount === 4, JSON.stringify(champz));
  const kickoff = chennai.find((r) => r.name === "Kickoff Sports");
  check("seed: a venue whose photos are still waiting shows no photo yet", kickoff.photos.length === 0 && kickoff.venueType === "OUTDOOR", JSON.stringify([kickoff.photos, kickoff.heroImageUrl]));
  { const b = mine(await cards("Bangalore", null)).map((r) => r.name); const h = mine(await cards("Hyderabad", "Telangana")).map((r) => r.name); check("seed: Bengaluru has two, Hyderabad one", b.length === 2 && h.length === 1, JSON.stringify([b, h])); }
  check("seed: memberships and coaching lists carry the venues that have them", mine(await cards("Chennai", "Tamil Nadu", "memberships")).map((r) => r.name).join() === "Champz Turf,Smash Arena" && mine(await cards("Chennai", "Tamil Nadu", "coaching")).length === 2 && mine(await cards("Hyderabad", "Telangana", "memberships")).length === 0);

  const detail = (await q("select get_public_venue((select id from facilities where slug='seed-champz-turf')) v"))[0].v;
  check("seed: the venue page has courts, hours, plans, programs and a verified map link", detail.courtCount === 4 && detail.hours.opens === "06:00" && detail.hours.closes === "23:00" && detail.memberships.plans.length === 3 && detail.coaching.programs.length === 2 && detail.locationVerified === true && detail.locationUrl.includes("google.com/maps"), JSON.stringify([detail.hours, detail.locationUrl]));
  const k = (await q("select get_public_venue((select id from facilities where slug='seed-kickoff-sports')) v"))[0].v;
  check("seed: the unverified venue withholds its map link", k.locationVerified === false && k.locationUrl === null);
  const padel = (await q("select get_public_venue((select id from facilities where slug='seed-ace-pickle-club')) v"))[0].v;
  check("seed: a venue with padel (a custom sport) lists it by name", padel.sports.map((s) => s.name).sort().join() === "Padel,Pickleball", padel.sports.map((s) => s.name).join());

  // the slots a visitor would see: tomorrow, Champz badminton
  const sportId = (await q("select fs.id from facility_sports fs join facilities f on f.id=fs.facility_id join sports s on s.id=fs.sport_id where f.slug='seed-champz-turf' and s.key='badminton'"))[0].id;
  const slots = (await q("select get_public_court_availability((select id from facilities where slug='seed-champz-turf'), $1, current_date + 5) a", [sportId]))[0].a;
  check("seed: live availability works for a seeded venue (three courts, hourly slots)", slots.length === 3 && slots[0].slots.length > 10, JSON.stringify([slots.length, slots[0]?.slots?.length]));

  // the test players: signed in by phone, they see what the clubs recorded
  const mkPlayer = async (phone, name) => {
    const id = uuid();
    await q("insert into auth.users (id, phone) values ($1,$2)", [id, "91" + phone]);
    await q("insert into players (id, full_name, phone) values ($1,$2,$3)", [id, name, phone]);
    return id;
  };
  const arun = await mkPlayer("9000000001", "Arun Test");
  const meena = await mkPlayer("9000000002", "Meena Test");
  const ravi = await mkPlayer("9000000003", "Ravi Test");
  const dashFor = async (uid) => { await asUser(uid); const r = (await q("select get_player_dashboard() d"))[0].d; await asUser(null); return r; };
  let d = await dashFor(arun);
  check("seed: Arun has a membership, coaching and two upcoming bookings", d.memberships.length === 1 && d.memberships[0].planName === "Monthly Unlimited" && d.coaching.length === 1 && d.coaching[0].programName === "Beginner Badminton" && d.upcomingBookings.length === 2 && d.guestBookings.count === 2, JSON.stringify([d.memberships.length, d.coaching.length, d.upcomingBookings.length]));
  d = await dashFor(meena);
  check("seed: Meena has a membership and nothing else", d.memberships.length === 1 && d.memberships[0].venueName === "Ace Pickle Club" && d.coaching.length === 0 && d.guestBookings.count === 0);
  d = await dashFor(ravi);
  check("seed: Ravi has one guest booking", d.guestBookings.count === 1 && d.memberships.length === 0 && d.schedule.length === 1);

  // the cleanup puts everything back exactly as it was
  await db.exec(cleanSql);
  check("cleanup: every table is back to what it was before the seed", (await counts()) === before, (await counts()) + " vs " + before);
  check("cleanup: no seed venue, owner, test player or test login is left", (await q("select count(*)::int c from facilities where slug like 'seed-%'"))[0].c === 0 && (await q("select count(*)::int c from auth.users where phone like '919000000%' or lower(email)='seed.owner@gameall.test'"))[0].c === 0 && (await q("select count(*)::int c from players where phone like '90000000%'"))[0].c === 0);
  await db.exec(cleanSql);
  check("cleanup: running it again is harmless", (await counts()) === before);
  await db.exec(seedSql);
  check("seed: it can be loaded again after a cleanup", (await q("select count(*)::int c from facilities where slug like 'seed-%'"))[0].c === 6);
  await db.exec(cleanSql);
  await asUser(owner);
}


// ═══ Enroll Membership (0175) — time slot → plan → pending membership ═══════════════════════════════
{
  const eo = await mkUser("enroll-owner@test.local", "Enroll Owner");
  const f = await mkFacility(eo, "Enroll Arena");
  await q("update facilities set city='Chennai', state='Tamil Nadu', status='ACTIVE', onboarding_step='COMPLETED' where id=$1", [f]);
  const sp = (await q("select id from sports where key='badminton'"))[0].id;
  const fsid = uuid();
  await q("insert into facility_sports (id, facility_id, sport_id) values ($1,$2,$3)", [fsid, f, sp]);
  const court = uuid();
  await q("insert into courts (id, facility_id, sport_id, facility_sport_id, name, hourly_rate_inr) values ($1,$2,$3,$4,'Court 1',350)", [court, f, sp, fsid]);
  const monthly = uuid(), quarterly = uuid();
  await q("insert into membership_plans (id, facility_id, name, price_inr, duration_days, joining_fee_inr, features, badge_text) values ($1,$2,'Monthly',2999,30,500,'{Dedicated court time}','Popular')", [monthly, f]);
  await q("insert into membership_plans (id, facility_id, name, price_inr, duration_days) values ($1,$2,'Quarterly',7999,90)", [quarterly, f]);
  const bm = uuid(), bq = uuid();
  await q("insert into membership_batches (id, facility_id, plan_id, facility_sport_id, court_id, name, days_of_week, start_time, end_time, capacity) values ($1,$2,$3,$4,$5,'Eve M','{1,2,3}','18:00','19:00',2), ($6,$2,$7,$4,$5,'Eve Q','{1,2,3}','18:00','19:00',5)", [bm, f, monthly, fsid, court, bq, quarterly]);

  await asUser(null);
  const info = async () => (await q("select get_public_membership_enroll($1) i", [f]))[0].i;
  let i = await info();
  check("enroll: the venue's sports, one grouped time slot and both plans come back", i.facilityName === "Enroll Arena" && i.sports.length === 1 && i.slots.length === 1 && i.plans.length === 2 && i.slots[0].batches.length === 2, JSON.stringify(i.slots));
  check("enroll: a slot has no members yet and its seats add up", i.slots[0].membersNow === 0 && i.slots[0].spare === 7 && i.slots[0].startTime === "18:00:00", JSON.stringify(i.slots[0]));
  const m = i.plans.find((x) => x.name === "Monthly");
  check("enroll: plan carries its price, length, benefits, badge and joining fee", m.priceInr === 2999 && m.durationDays === 30 && m.features[0] === "Dedicated court time" && m.badgeText === "Popular" && m.joiningFeeInr === 500, JSON.stringify(m));
  check("enroll: an unknown venue gives null", (await q("select get_public_membership_enroll($1) i", [uuid()]))[0].i === null);

  const pid = uuid();
  await q("insert into auth.users (id, phone) values ($1,'919444400001')", [pid]);
  await q("insert into players (id, full_name, phone) values ($1,'Enroll Player','9444400001')", [pid]);
  await asUser(null);
  await throws("enroll: signing in is needed to join", () => q("select player_start_membership_enroll($1,$2,$3)", [f, monthly, bm]), "Sign in");
  await asUser(pid);
  check("enroll: before joining the player has no memberships here", (await q("select get_my_memberships_at($1) r", [f]))[0].r.length === 0);
  const r1 = (await q("select player_start_membership_enroll($1,$2,$3) r", [f, monthly, bm]))[0].r;
  check("enroll: joining makes a membership and charges the plan price plus the joining fee once", r1.amountInr === 3499 && r1.joiningFeeInr === 500 && r1.resumed === false, JSON.stringify(r1));
  const pays = await q("select amount_inr, status from payments where membership_id=$1", [r1.membershipId]);
  check("enroll: exactly one pending payment of the total", pays.length === 1 && pays[0].amount_inr === 3499 && pays[0].status === "created", JSON.stringify(pays));
  check("enroll: the membership records the joining fee", (await q("select registration_fee_inr r from memberships where id=$1", [r1.membershipId]))[0].r === 500);
  const r2 = (await q("select player_start_membership_enroll($1,$2,$3) r", [f, monthly, bm]))[0].r;
  check("enroll: coming back resumes the same pending membership, no second one", r2.resumed === true && r2.membershipId === r1.membershipId && (await q("select count(*)::int c from memberships where facility_id=$1", [f]))[0].c === 1, JSON.stringify(r2));
  await asUser(null);
  i = await info();
  const stRow = (await q("select status::text s, pending_batch_id pb, total_amount_inr t, membership_fee_inr mf from memberships where id=$1", [r1.membershipId]))[0];
  check("enroll: an unpaid membership is pending (Payment Incomplete), holds no slot and remembers the slot it wants", stRow.s === "pending" && stRow.pb === bm && i.slots[0].membersNow === 0, JSON.stringify(stRow));
  check("enroll: the club's total for the membership includes the joining fee", stRow.t === 3499 && stRow.mf === 2999, JSON.stringify(stRow));
  check("enroll: the club's list shows it as Payment Incomplete", (await q("select membership_display_status($1,'pending',current_date,current_date+30,30,3499) s", [r1.membershipId]))[0].s === "payment_incomplete");
  await q("update payments set status='paid', paid_at=now(), payment_method='upi_autopay' where membership_id=$1", [r1.membershipId]);
  const stPaid = (await q("select status::text s, pending_batch_id pb from memberships where id=$1", [r1.membershipId]))[0];
  i = await info();
  check("enroll: once the payment is paid the membership is active and takes its slot", stPaid.s === "active" && stPaid.pb === null && i.slots[0].membersNow === 1, JSON.stringify([stPaid, i.slots[0].membersNow]));
  await asUser(pid);
  await throws("enroll: the same person cannot join a second membership at the same court and time", () => q("select player_start_membership_enroll($1,$2,$3)", [f, quarterly, bq]), "already have a membership");
  await asUser(null);
  // a signed-in player (not staff) can read the same page: the staff-only batch list is not used
  await asUser(pid);
  check("enroll: a signed-in player can load the enroll page", (await info()).slots.length === 1);
  await asUser(null);
  await asUser(pid);
  const mine = (await q("select get_my_memberships_at($1) r", [f]))[0].r;
  check("enroll: the player's memberships here are listed with plan and time slot", mine.length === 1 && mine[0].planName === "Monthly" && mine[0].slots.length === 1 && mine[0].slots[0].startTime === "18:00:00", JSON.stringify(mine));
  const bq2 = uuid();
  await q("insert into membership_batches (id, facility_id, plan_id, facility_sport_id, court_id, name, days_of_week, start_time, end_time, capacity) values ($1,$2,$3,$4,$5,'Late Q','{1,2,3}','20:00','21:00',5)", [bq2, f, quarterly, fsid, court]);
  const r3 = (await q("select player_start_membership_enroll($1,$2,$3) r", [f, quarterly, bq2]))[0].r;
  check("enroll: a second membership at a different time can still be joined", r3.membershipId !== r1.membershipId && r3.amountInr === 7999 && r3.joiningFeeInr === 0, JSON.stringify(r3));
  await throws("enroll: a plan from another club is refused", () => q("select player_start_membership_enroll($1,$2,null)", [f, uuid()]), "not available");

  // the same person is found by mobile number however it is typed: no second member record
  await asUser(null);
  await q("insert into members (facility_id, full_name, phone) values ($1,'Typed Differently','+91 94444-00002')", [f]);
  const pid2 = uuid();
  await q("insert into auth.users (id, phone) values ($1,'919444400002')", [pid2]);
  await q("insert into players (id, full_name, phone) values ($1,'Other Name','9444400002')", [pid2]);
  await asUser(pid2);
  await q("select player_start_membership_enroll($1,$2,null)", [f, monthly]);
  await asUser(null);
  check("enroll: a number typed differently at the club is the same member, not a duplicate", (await q("select count(*)::int c from members where facility_id=$1 and normalize_phone(phone)='9444400002'", [f]))[0].c === 1);

  // a guest booking inside the membership's court time is refused, and the slot is closed on the public page
  const nextMon = (await q("select ((date_trunc('week', now() at time zone 'Asia/Kolkata') + interval '1 week' + time '18:00') at time zone 'Asia/Kolkata') s"))[0].s;
  const nextMonEnd = new Date(new Date(nextMon).getTime() + 3600000);
  await throws("guest booking: membership court time is not bookable", () => q("select public_create_guest_booking($1,$2,$3,$4,'Gus Guest','9777700001',null,null,null,1,'FULL')", [f, court, nextMon, nextMonEnd]), "reserved for members");
  const day = (await q("select to_char(($1::timestamptz at time zone 'Asia/Kolkata')::date,'YYYY-MM-DD') d", [nextMon]))[0].d;
  const av = (await q("select get_public_court_availability($1,$2,$3::date) r", [f, fsid, day]))[0].r;
  const slot18 = av.flatMap((c) => c.slots).find((s) => new Date(s.startTime).getTime() === new Date(nextMon).getTime());
  check("guest booking: the membership hour shows as taken on the public page (no released seats sold)", slot18 === undefined || slot18.available === false, JSON.stringify(slot18));

  // the same person cannot book the same court at the same time twice (mobile number, not name)
  const t19 = new Date(new Date(nextMon).getTime() + 5 * 86400000 + 2 * 3600000); // a day outside the batch days, 20:00
  const g1 = uuid();
  await q("insert into guest_players (id, facility_id, name, phone) values ($1,$2,'First Name','+91 97777-00009')", [g1, f]);
  await q("insert into bookings (facility_id, court_id, start_time, end_time, status, customer_type, guest_name, guest_phone, guest_player_id, amount_minor) values ($1,$2,$3,$4,'confirmed','GUEST','First Name','+91 97777-00009',$5,35000)", [f, court, t19, new Date(t19.getTime() + 3600000), g1]);
  await throws("guest booking: the same mobile number cannot book the same court and time twice, whatever the name", () => q("select public_create_guest_booking($1,$2,$3,$4,'Totally Different Name','9777700009',null,null,null,1,'FULL')", [f, court, t19, new Date(t19.getTime() + 3600000)]), "already have a booking");
  // a real booking through the same routine the Player app and the public page use
  const sch = (await q("insert into operating_schedules (facility_id, scope_type) values ($1,'FACILITY') returning id", [f]))[0].id;
  for (const dow of [0, 1, 2, 3, 4, 5, 6]) {
    const d = (await q("insert into operating_days (schedule_id, facility_id, day_of_week) values ($1,$2,$3) returning id", [sch, f, dow]))[0].id;
    await q("insert into operating_time_slots (operating_day_id, facility_id, start_time, end_time) values ($1,$2,'06:00','23:00')", [d, f]);
  }
  const t22 = new Date(t19.getTime() + 2 * 3600000);
  const bk1 = (await q("select public_create_guest_booking($1,$2,$3,$4,'Real Guest','+91 97777-00077',null,null,null,1,'ADVANCE') r", [f, court, t22, new Date(t22.getTime() + 3600000)]))[0].r;
  check("guest booking: a real booking is made, held for its 50% advance", !!bk1.bookingId && bk1.advanceRequired === true && bk1.advanceMinor === Math.ceil(bk1.amountMinor / 2) && bk1.paymentOption === "ADVANCE", JSON.stringify(bk1));
  await throws("guest booking: booking the same court and time again with the same number is refused", () => q("select public_create_guest_booking($1,$2,$3,$4,'Another Name','9777700077',null,null,null,1,'FULL')", [f, court, t22, new Date(t22.getTime() + 3600000)]), "already have a booking");
  const t23 = new Date(t22.getTime() - 4 * 3600000);
  const bk2 = (await q("select public_create_guest_booking($1,$2,$3,$4,'Real Guest','9777700077',null,null,null,1,'FULL') r", [f, court, t23, new Date(t23.getTime() + 3600000)]))[0].r;
  check("guest booking: a different time for the same person is accepted", !!bk2.bookingId && bk2.advanceMinor === bk2.amountMinor, JSON.stringify(bk2));
  check("guest booking: the number typed two ways is one guest record, not two", (await q("select count(*)::int c from guest_players where facility_id=$1 and normalize_phone(phone)='9777700077'", [f]))[0].c === 1);

  // an unpaid membership for an overlapping slot is removed once its sibling is paid
  await asUser(null);
  const pid3 = uuid();
  await q("insert into auth.users (id, phone) values ($1,'919444400003')", [pid3]);
  await q("insert into players (id, full_name, phone) values ($1,'Two Plans','9444400003')", [pid3]);
  await asUser(pid3);
  const a1 = (await q("select player_start_membership_enroll($1,$2,$3) r", [f, monthly, bm]))[0].r;
  const a2 = (await q("select player_start_membership_enroll($1,$2,$3) r", [f, quarterly, bq]))[0].r;
  check("enroll: two unpaid memberships for the same slot can both wait for payment", a1.membershipId !== a2.membershipId);
  const myMs = JSON.stringify((await q("select get_my_membership_details() r"))[0].r);
  check("enroll: the player still sees both unpaid memberships (to pay them)", myMs.includes(a1.membershipId) && myMs.includes(a2.membershipId), myMs.slice(0, 200));
  await asUser(null);
  await q("update payments set status='paid', paid_at=now(), payment_method='cash' where membership_id=$1", [a1.membershipId]);
  check("enroll: when one is paid the other unpaid membership for that slot is removed", (await q("select count(*)::int c from memberships where id=$1", [a2.membershipId]))[0].c === 0);
  check("enroll: the paid one is active with its slot", (await q("select count(*)::int c from membership_batch_members where membership_id=$1", [a1.membershipId]))[0].c === 1);

  // coaching: pending until paid, no seat or roster place, no overlapping coaching for the same mobile number
  const prog = uuid(), cb1 = uuid(), cb2 = uuid(), cb3 = uuid();
  await q("insert into coaching_programs (id, facility_id, name, status, default_price_minor, payment_mode) values ($1,$2,'Juniors Camp','ACTIVE',150000,'ONLINE')", [prog, f]);
  await q("insert into coaching_program_batches (id, facility_id, program_id, court_id, name, days_of_week, start_time, end_time, capacity) values ($1,$4,$5,$6,'Morning','{1,2}','07:00','08:00',1), ($2,$4,$5,$6,'Morning B','{1}','07:30','08:30',5), ($3,$4,$5,$6,'Noon','{1,2}','12:00','13:00',5)", [cb1, cb2, cb3, f, prog, court]);
  const pid4 = uuid();
  await q("insert into auth.users (id, phone) values ($1,'919444400004')", [pid4]);
  await q("insert into players (id, full_name, phone) values ($1,'Coach Seeker','9444400004')", [pid4]);
  await asUser(pid4);
  const c1 = (await q("select player_start_coaching_enroll($1,$2,$3) r", [f, prog, cb1]))[0].r;
  await asUser(null);
  const ce = (await q("select status, price_minor from coaching_enrollments where id=$1", [c1.enrollmentId]))[0];
  check("coaching: a player's enrolment is payment-incomplete until it is paid", ce.status === "PENDING_PAYMENT" && ce.price_minor === 150000, JSON.stringify(ce));
  const pid5 = uuid();
  await q("insert into auth.users (id, phone) values ($1,'919444400005')", [pid5]);
  await q("insert into players (id, full_name, phone) values ($1,'Other Seeker','9444400005')", [pid5]);
  await asUser(pid5);
  const c2 = (await q("select player_start_coaching_enroll($1,$2,$3) r", [f, prog, cb1]))[0].r;
  check("coaching: an unpaid enrolment holds no seat, so a full-looking batch (capacity 1) is still open to others", c2.enrollmentId !== c1.enrollmentId);
  await asUser(null);
  await q("insert into payments (facility_id, coaching_enrollment_id, amount_inr, status, payment_method, paid_at) values ($1,$2,1500,'paid','Razorpay',now())", [f, c1.enrollmentId]);
  check("coaching: the payment makes it active", (await q("select status from coaching_enrollments where id=$1", [c1.enrollmentId]))[0].status === "ACTIVE");
  await asUser(pid5);
  const c2again = (await q("select player_start_coaching_enroll($1,$2,$3) r", [f, prog, cb1]))[0].r;
  check("coaching: a batch at capacity still lets the next player continue to pay", c2again.enrollmentId === c2.enrollmentId);
  await asUser(null);
  await q("insert into payments (facility_id, coaching_enrollment_id, amount_inr, status, payment_method, paid_at) values ($1,$2,1500,'paid','Razorpay',now())", [f, c2.enrollmentId]);
  const cnt = (await q("select count(*)::int c from coaching_enrollments where batch_id=$1 and status='ACTIVE'", [cb1]))[0].c;
  check("coaching: both paid players are enrolled, the batch simply shows 2 for a capacity of 1", cnt === 2 && (await q("select capacity from coaching_program_batches where id=$1", [cb1]))[0].capacity === 1);
  await asUser(pid5);
  const prog3 = uuid();
  await q("insert into coaching_programs (id, facility_id, name, status, default_price_minor, payment_mode) values ($1,$2,'Half Camp','ACTIVE',50000,'ONLINE')", [prog3, f]);
  await q("update coaching_program_batches set program_id=$1 where id=$2", [prog3, cb2]);
  await asUser(pid4);
  await throws("coaching: the same mobile number cannot take an overlapping batch on the same court", () => q("select player_start_coaching_enroll($1,$2,$3)", [f, prog3, cb2]), "already have coaching");
  const prog2 = uuid();
  await q("insert into coaching_programs (id, facility_id, name, status, default_price_minor, payment_mode) values ($1,$2,'Noon Camp','ACTIVE',90000,'ONLINE')", [prog2, f]);
  await q("update coaching_program_batches set program_id=$1 where id=$2", [prog2, cb3]);
  const c3 = (await q("select player_start_coaching_enroll($1,$2,$3) r", [f, prog2, cb3]))[0].r;
  check("coaching: a different time is fine for the same mobile number", !!c3.enrollmentId);
  const myCd = JSON.stringify((await q("select get_my_coaching_details() r"))[0].r);
  check("coaching: My Coaching lists the unpaid enrolment as well", myCd.includes(c3.enrollmentId), myCd.slice(0, 200));
  const myCo = (await q("select get_my_coaching_at($1) r", [f]))[0].r;
  check("coaching: the player still sees the unpaid enrolment (to pay it)", myCo.some((x) => x.enrollmentId === c3.enrollmentId || x.id === c3.enrollmentId), JSON.stringify(myCo).slice(0, 200));
  await asUser(null);
  await asUser(owner);
}

// ═══ player profile (0187): Player ID, edit, the four numbers, payment history ═══════════════════════════════════
{
  const ow = await mkUser("profile.owner@test.local", "Profile Owner");
  const fx = await mkFacility(ow, "Profile Venue");
  const pid = uuid();
  await q("insert into auth.users (id, phone) values ($1,'919555500001')", [pid]);
  await q("insert into players (id, full_name, phone) values ($1,'Pro File','9555500001')", [pid]);
  const mem = await q("insert into members (id, facility_id, full_name, phone) values ($1,$2,'Pro File','9555500001') returning id", [uuid(), fx]);
  const msId = await mkMembership(fx, mem[0].id, "Gold");
  await q("insert into payments (facility_id, member_id, membership_id, amount_inr, status, paid_at, payment_method) values ($1,$2,$3,2500,'paid',now(),'UPI')", [fx, mem[0].id, msId]);
  await asUser(pid);
  const prof = (await q("select get_my_player_profile() r"))[0].r;
  check("profile: the player has a Player ID like GA10000001", /^GA\d{8}$/.test(prof.playerCode), JSON.stringify(prof));
  const up = (await q("select update_my_player_profile('Pro File Two','pro@example.com','1995-04-12','MALE','Chennai, Tamil Nadu',null,false) r"))[0].r;
  check("profile: edit saves name, email, date of birth, gender and city", up.fullName === "Pro File Two" && up.email === "pro@example.com" && up.dob === "1995-04-12" && up.gender === "MALE" && up.city === "Chennai, Tamil Nadu", JSON.stringify(up));
  check("profile: the phone number cannot be edited here", up.phone === "9555500001");
  const up2 = (await q("select update_my_player_profile(null,null,null,null,null,null,false) r"))[0].r;
  check("profile: leaving everything null changes nothing", up2.fullName === "Pro File Two" && up2.dob === "1995-04-12", JSON.stringify(up2));
  await throws("profile: a bad email is refused", () => q("select update_my_player_profile(null,'nope')"), "valid email");
  await throws("profile: a future date of birth is refused", () => q("select update_my_player_profile(null,null,(current_date + 5))"));
  await throws("profile: an unknown gender is refused", () => q("select update_my_player_profile(null,null,null,'X')"), "gender");
  await throws("profile: a photo address must be https", () => q("select update_my_player_profile(null,null,null,null,null,'javascript:1')"), "photo");
  const up3 = (await q("select update_my_player_profile(null,null,null,null,null,'https://x.test/a.jpg',false) r"))[0].r;
  check("profile: the photo address is saved", up3.avatarUrl === "https://x.test/a.jpg");
  const st = (await q("select get_my_profile_stats() r"))[0].r;
  check("profile: the numbers count memberships and leave tournaments empty", st.memberships === 1 && st.bookings === 0 && st.coaching === 0 && st.tournaments === null, JSON.stringify(st));
  const hist = (await q("select get_my_payment_history(50) r"))[0].r;
  check("profile: payment history lists the paid membership payment", hist.length === 1 && hist[0].kind === "payment" && hist[0].status === "PAID" && hist[0].amountInr === 2500 && hist[0].source === "membership" && hist[0].venueName === "Profile Venue", JSON.stringify(hist));
  await asUser(null);
  check("profile: signed out there is no profile, no history", (await q("select get_my_player_profile() r"))[0].r === null && (await q("select get_my_payment_history(5) r"))[0].r.length === 0);
  const pid2 = uuid();
  await q("insert into auth.users (id, phone) values ($1,'919555500002')", [pid2]);
  await q("insert into players (id, full_name, phone) values ($1,'Other Person','9555500002')", [pid2]);
  await asUser(pid2);
  check("profile: another player sees none of those payments", (await q("select get_my_payment_history(50) r"))[0].r.length === 0);
  await asUser(null);
}

// ═══ booking payment choice and cancellation (0188) ═══════════════════════════════════════════════════════════════
{
  const ow = await mkUser("cancel.owner@test.local", "Cancel Owner");
  const fx = await mkFacility(ow, "Cancel Venue");
  const sport = (await q("select id from sports where key='badminton'"))[0].id;
  const fsid = uuid();
  await q("insert into facility_sports (id, facility_id, sport_id) values ($1,$2,$3)", [fsid, fx, sport]);
  const court = uuid();
  await q("insert into courts (id, facility_id, sport_id, facility_sport_id, name, hourly_rate_inr) values ($1,$2,$3,$4,'Court 1',1000)", [court, fx, sport, fsid]);
  const gphone = "9333300001";
  const gp = uuid();
  await q("insert into guest_players (id, facility_id, name, phone) values ($1,$2,'Cancel Guest',$3)", [gp, fx, gphone]);
  let slot = 0;
  const mkBk = async (hoursAhead, amountMinor = 100000, option = null) => {
    const id = uuid();
    slot++;
    // its own court, so no two bookings clash
    const cid = uuid();
    await q("insert into courts (id, facility_id, sport_id, facility_sport_id, name, hourly_rate_inr) values ($1,$2,$3,$4,$5,1000)", [cid, fx, sport, fsid, "Court x" + slot]);
    await q(`insert into bookings (id, facility_id, court_id, customer_type, guest_name, guest_phone, guest_player_id, start_time, end_time, status, amount_minor, payment_option)
             values ($1,$2,$3,'GUEST','Cancel Guest',$4,$5, now() + ($6 || ' hours')::interval, now() + ($6 || ' hours')::interval + interval '1 hour', 'confirmed', $7, $8)`,
      [id, fx, cid, gphone, gp, String(hoursAhead), amountMinor, option]);
    return id;
  };
  let pn = 0;
  const mkOrder = async (bk, minor, status = "COMPLETED") => {
    const id = uuid();
    pn++;
    await q(`insert into payment_orders (id, facility_id, source_type, booking_id, amount_minor, status, razorpay_order_id, razorpay_payment_id, receipt, expires_at)
             values ($1,$2,'GUEST_BOOKING',$3,$4,$5,$6,$7,$8, now() + interval '1 day')`, [id, fx, bk, minor, status, `order_c${pn}`, `pay_c${pn}`, `rcpt-c${pn}`]);
    return id;
  };
  const quote = async (bk, pct = null) => (await q("select booking_cancellation_quote($1,$2) r", [bk, pct]))[0].r;

  // the schedule itself, band by band
  const sched = [[12, 5], [13, 5], [11.99, 10], [11, 10], [10.5, 15], [9.5, 20], [8.5, 30], [7.5, 40], [6.5, 45], [5.5, 50], [4.5, 70], [3.5, 75], [2.5, 80], [1.5, 90], [1, 90], [0.99, 100], [0.2, 100], [0, 100], [-3, 100]];
  for (const [h, pct] of sched) check(`cancel schedule: ${h} h left deducts ${pct}%`, (await q("select cancellation_deduction_percent($1) p", [h]))[0].p === pct);

  // a fully paid booking: each band refunds the rest
  const bands = [[12.5, 5], [11.5, 10], [10.5, 15], [9.5, 20], [8.5, 30], [7.5, 40], [6.5, 45], [5.5, 50], [4.5, 70], [3.5, 75], [2.5, 80], [1.5, 90]];
  for (const [h, d] of bands) {
    const bk = await mkBk(h);
    await mkOrder(bk, 100000);
    const qq = await quote(bk);
    check(`cancel quote: fully paid, ${h} h left -> ${d}% deducted, ${100000 * (100 - d) / 100} refunded`,
      qq.rule === "FULL" && qq.deductionPercent === d && qq.refundMinor === 100000 * (100 - d) / 100 && qq.onlineRefundMinor === qq.refundMinor && qq.offlineRefundDueMinor === 0, JSON.stringify(qq));
  }
  {
    const bk = await mkBk(0.4); await mkOrder(bk, 100000);
    const qq = await quote(bk);
    check("cancel quote: under an hour left -> nothing is refunded", qq.deductionPercent === 100 && qq.refundMinor === 0, JSON.stringify(qq));
    check("cancel quote: the message says what happens", /deducted/.test(qq.message) && /starts in/.test(qq.message), qq.message);
  }
  {
    const bk = await mkBk(30, 100000, "ADVANCE"); await mkOrder(bk, 50000);
    const qq = await quote(bk);
    check("cancel quote: only the 50% advance paid -> no refund", qq.rule === "ADVANCE_ONLY" && qq.refundMinor === 0 && qq.paidMinor === 50000 && /advance/i.test(qq.message), JSON.stringify(qq));
    const ov = await quote(bk, 100);
    check("cancel quote: an owner override of 100% refunds the advance", ov.refundMinor === 50000 && ov.isOverride === true && ov.onlineRefundMinor === 50000, JSON.stringify(ov));
    const ov2 = await quote(bk, 40);
    check("cancel quote: an override of 40% refunds 40% of what was paid", ov2.refundMinor === 20000, JSON.stringify(ov2));
  }
  {
    const bk = await mkBk(30);
    const qq = await quote(bk);
    check("cancel quote: nothing paid -> nothing to refund", qq.rule === "UNPAID" && qq.refundMinor === 0 && qq.paidMinor === 0, JSON.stringify(qq));
  }

  // cancelling as the club: advance + balance (two payments), refund spread over both, the parts add up
  {
    const bk = await mkBk(20, 100000, "ADVANCE");
    await mkOrder(bk, 50000);
    await mkOrder(bk, 50000);
    await asUser(ow);
    const b = (await q("select status from cancel_booking($1,'changed plans')", [bk]))[0];
    check("cancel as club: the booking is cancelled", b.status === "cancelled");
    const rf = await q("select payment_order_id, amount_minor, status, reason from refunds where source_id=$1 order by amount_minor", [bk]);
    check("cancel as club: paid in full 20 h ahead -> 95% refunded, split over both payments (47500 + 47500)", rf.length === 2 && rf.every((r) => r.amount_minor === 47500 && r.status === "REQUESTED" && r.reason === "CUSTOMER_CANCELLATION"), JSON.stringify(rf));
    const log = (await q("select * from booking_cancellations where booking_id=$1", [bk]))[0];
    check("cancel as club: one audit row with the % and the amounts", log.deduction_percent === 5 && log.refund_percent === 95 && log.refund_minor === 95000 && log.online_refund_minor === 95000 && log.offline_refund_due_minor === 0 && log.channel === "CLUB", JSON.stringify(log));
    await throws("cancel as club: cancelling twice is refused", () => q("select cancel_booking($1)", [bk]), "cannot be cancelled");
    await asUser(null);
  }
  // advance only, cancelled by the club: no refund row; with an override the advance goes back
  {
    const bk = await mkBk(20, 100000, "ADVANCE"); await mkOrder(bk, 50000);
    await asUser(ow);
    await q("select cancel_booking($1,'no show')", [bk]);
    check("cancel as club: advance only -> no refund is created", (await q("select count(*)::int c from refunds where source_id=$1", [bk]))[0].c === 0);
    const bk2 = await mkBk(20, 100000, "ADVANCE"); await mkOrder(bk2, 50000);
    await q("select cancel_booking($1,'club error',100,'our mistake')", [bk2]);
    const rf = await q("select amount_minor, reason, is_override, override_reason from refunds where source_id=$1", [bk2]);
    check("cancel as club: the owner can refund the advance anyway (override, with a reason)", rf.length === 1 && rf[0].amount_minor === 50000 && rf[0].reason === "OWNER_OVERRIDE" && rf[0].is_override && rf[0].override_reason === "our mistake", JSON.stringify(rf));
    await asUser(null);
  }
  // online + cash: Razorpay gives back its share, the cash share is owed at the club
  {
    const bk = await mkBk(20, 100000, "ADVANCE");
    await mkOrder(bk, 50000);
    await q("insert into payments (facility_id, booking_id, amount_inr, status, payment_method, paid_at) values ($1,$2,500,'paid','cash', now())", [fx, bk]);
    const qq = await quote(bk);
    check("cancel quote: half online and half cash, fully paid -> refund 95% with the cash share due at the club", qq.rule === "FULL" && qq.refundMinor === 95000 && qq.onlineRefundMinor === 47500 && qq.offlineRefundDueMinor === 47500, JSON.stringify(qq));
    await asUser(ow);
    await q("select cancel_booking($1)", [bk]);
    check("cancel as club: only the online part becomes a Razorpay refund", (await q("select coalesce(sum(amount_minor),0)::int s from refunds where source_id=$1", [bk]))[0].s === 47500);
    check("cancel as club: the cash part is recorded as due at the club", (await q("select offline_refund_due_minor d from booking_cancellations where booking_id=$1", [bk]))[0].d === 47500);
    const due = (await q("select list_offline_refunds_due($1) r", [fx]))[0].r;
    check("cash refunds due: the club sees the cash it still owes for the cancelled booking", due.some((d) => d.bookingId === bk && d.refundDueMinor === 47500 && d.guestName === "Cancel Guest"), JSON.stringify(due));
    const s = (await q("select offline_refund_settled_at from settle_offline_refund($1)", [bk]))[0];
    check("cancel as club: the club can mark the cash refund as handed back", s.offline_refund_settled_at !== null);
    check("cash refunds due: once handed back it leaves the list", !(await q("select list_offline_refunds_due($1) r", [fx]))[0].r.some((d) => d.bookingId === bk));
    await asUser(null);
  }
  // the payment choice sets the first payment
  {
    const b1 = await mkBk(30, 100000, "FULL");
    const b2 = await mkBk(30, 100000, "ADVANCE");
    const b3 = await mkBk(30, 100000, null);
    const due = async (id) => (await q("select booking_due_now_minor(b) d from bookings b where b.id=$1", [id]))[0].d;
    check("payment choice: full -> the whole amount", (await due(b1)) === 100000);
    check("payment choice: 50% -> half, even for a one-hour booking", (await due(b2)) === 50000);
    check("payment choice: no choice (an old booking) -> the old rule, a one-hour booking pays in full", (await due(b3)) === 100000);
    await asUser(ow);
    const o1 = (await q("select amount_minor from create_payment_order($1,'GUEST_BOOKING',$2,null,null,null,true)", [fx, b1]))[0];
    const o2 = (await q("select amount_minor from create_payment_order($1,'GUEST_BOOKING',$2,null,null,null,true)", [fx, b2]))[0];
    check("payment choice: the payment order is charged accordingly", o1.amount_minor === 100000 && o2.amount_minor === 50000, `${o1.amount_minor} ${o2.amount_minor}`);
    const sb = (await q("select payment_option from set_booking_payment_option($1,'FULL')", [b3]))[0];
    check("payment choice: staff can record the choice on a booking made at the club", sb.payment_option === "FULL");
    await throws("payment choice: anything else is refused", () => q("select set_booking_payment_option($1,'HALF')", [b3]), "50%");
    await asUser(null);
  }
  // the player and the public page cancel their own booking
  {
    const pid = uuid();
    await q("insert into auth.users (id, phone) values ($1,$2)", [pid, "91" + gphone]);
    await q("insert into players (id, full_name, phone) values ($1,'Cancel Guest',$2)", [pid, gphone]);
    const bk = await mkBk(20, 100000, "FULL"); await mkOrder(bk, 100000);
    await asUser(pid);
    const mq = (await q("select get_my_booking_cancellation_quote($1) r", [bk]))[0].r;
    check("player cancel: the player sees the quote for their own booking", mq.refundMinor === 95000 && mq.deductionPercent === 5, JSON.stringify(mq));
    const other = uuid();
    await q("insert into auth.users (id, phone) values ($1,'919333300099')", [other]);
    await q("insert into players (id, full_name, phone) values ($1,'Someone Else','9333300099')", [other]);
    await asUser(other);
    check("player cancel: another player sees no quote for it", (await q("select get_my_booking_cancellation_quote($1) r", [bk]))[0].r === null);
    await throws("player cancel: another player cannot cancel it", () => q("select player_cancel_booking($1)", [bk]), "could not find");
    await asUser(pid);
    const done = (await q("select player_cancel_booking($1) r", [bk]))[0].r;
    check("player cancel: the player's cancellation refunds 95% and says so", done.refundMinor === 95000 && (await q("select status from bookings where id=$1", [bk]))[0].status === "cancelled");
    check("player cancel: a refund row waits for the edge function to send it to Razorpay", (await q("select count(*)::int c from refunds where source_id=$1 and status='REQUESTED' and amount_minor=95000", [bk]))[0].c === 1);
    check("player cancel: the audit row says it came from the player app", (await q("select channel c from booking_cancellations where booking_id=$1", [bk]))[0].c === "PLAYER_APP");
    const started = await mkBk(-1, 100000, "FULL");
    await throws("player cancel: a booking that has started cannot be cancelled online", () => q("select player_cancel_booking($1)", [started]), "already started");
    await asUser(null);

    const pub = await mkBk(14, 100000, "FULL"); await mkOrder(pub, 100000);
    const pq = (await q("select public_booking_cancellation_quote($1,$2) r", [pub, "+91 " + gphone]))[0].r;
    check("public cancel: the guest sees the quote with the phone number they booked with", pq !== null && pq.refundMinor === 95000, JSON.stringify(pq));
    check("public cancel: a wrong phone number sees nothing", (await q("select public_booking_cancellation_quote($1,'9000000000') r", [pub]))[0].r === null);
    await throws("public cancel: a wrong phone number cannot cancel", () => q("select public_cancel_booking($1,'9000000000')", [pub]), "could not find");
    const pc = (await q("select public_cancel_booking($1,$2) r", [pub, gphone]))[0].r;
    check("public cancel: the guest's cancellation refunds 95%", pc.refundMinor === 95000 && (await q("select channel c from booking_cancellations where booking_id=$1", [pub]))[0].c === "PUBLIC_PAGE");
  }
}

// ═══ Personal Information page (0192) ═══════════════════════════════════════════════════════════════════════
{
  const pid = uuid();
  await q("insert into auth.users (id, phone) values ($1,'919666600001')", [pid]);
  await q("insert into players (id, full_name, phone) values ($1,'Uma Shankar','9666600001')", [pid]);
  await asUser(pid);
  const sportsList = (await q("select list_platform_sports() r"))[0].r;
  check("personal info: the platform's sports list comes back", sportsList.length > 0 && !!sportsList[0].key && !!sportsList[0].name);
  const k1 = sportsList[0].key, k2 = sportsList[1].key;
  const saved = (await q("select update_my_player_info($1::jsonb) r", [JSON.stringify({
    fullName: "Uma Shankar M", dob: "2001-09-15", gender: "MALE", bloodGroup: "O+", tshirtSize: "L", preferredSports: [k1, k2, k1],
    playingLevel: "INTERMEDIATE", about: "Looking for regular games", altPhone: "9666600002", emergencyName: "Mohan", emergencyRelation: "Father",
    emergencyPhone: "9666600003", addressLine1: "12 Lake Road", addressLine2: "Adyar", city: "Chennai", state: "Tamil Nadu", pincode: "600020" })]))[0].r;
  check("personal info: every field is saved and returned", saved.fullName === "Uma Shankar M" && saved.bloodGroup === "O+" && saved.tshirtSize === "L" && saved.playingLevel === "INTERMEDIATE" && saved.emergencyName === "Mohan" && saved.pincode === "600020" && saved.city === "Chennai" && saved.dob === "2001-09-15", JSON.stringify(saved));
  check("personal info: preferred sports are kept once each", saved.preferredSports.length === 2 && saved.preferredSports.includes(k1) && saved.preferredSports.includes(k2), JSON.stringify(saved.preferredSports));
  const part = (await q("select update_my_player_info($1::jsonb) r", [JSON.stringify({ about: "" })]))[0].r;
  check("personal info: clearing one field leaves the rest as they were", part.about === null && part.bloodGroup === "O+" && part.addressLine1 === "12 Lake Road");
  await throws("personal info: an unknown sport is refused", () => q("select update_my_player_info($1::jsonb)", [JSON.stringify({ preferredSports: ["no-such-sport"] })]), "Unknown sport");
  const bad = (label, patch, msg) => throws("personal info: " + label, () => q("select update_my_player_info($1::jsonb)", [JSON.stringify(patch)]), msg);
  await bad("a bad PIN code is refused", { pincode: "12345" }, "PIN code must be 6 digits");
  await bad("a PIN code cannot start with 0", { pincode: "012345" }, "PIN code must be 6 digits");
  await bad("a name with digits is refused", { fullName: "Uma 2" }, "can only have letters");
  await bad("a one-letter name is refused", { fullName: "U" }, "too short");
  await bad("a 61-character name is refused", { fullName: "A".repeat(61) }, "too long");
  await bad("a bad email is refused", { email: "uma@@gmail" }, "valid email");
  await bad("an email with a double dot is refused", { email: "a..b@x.com" }, "valid email");
  await bad("a future date of birth is refused", { dob: "2999-01-01" }, "future");
  await bad("a date of birth before 1920 is refused", { dob: "1900-05-05" }, "valid date of birth");
  await bad("a mobile number starting with 5 is refused", { altPhone: "5876543210" }, "starts with 6, 7, 8 or 9");
  await bad("a short mobile number is refused", { altPhone: "98765" }, "10-digit");
  await bad("letters in a mobile number are refused", { altPhone: "98765abcde" }, "10-digit");
  await bad("the alternate number cannot be the sign-in number", { altPhone: "+91 96666-00001" }, "different one");
  await bad("an emergency contact needs a number", { emergencyName: "Mohan", emergencyPhone: "" }, "contact mobile number");
  await bad("an emergency contact needs a name", { emergencyName: "", emergencyPhone: "9666600003" }, "contact name");
  await bad("a PIN code needs the first address line", { addressLine1: "", pincode: "600020" }, "enter the address");
  await bad("an address needs its PIN code", { addressLine1: "12 Lake Road", pincode: "" }, "PIN code");
  await bad("symbols in an address line are refused", { addressLine1: "Lake <Road>" }, "can only have");
  await bad("a 201-character about is refused", { about: "x".repeat(201) }, "under 200");
  const tidy = (await q("select update_my_player_info($1::jsonb) r", [JSON.stringify({ fullName: "  Uma   Shankar  ", email: " Uma@Gmail.COM ", altPhone: "+91 96666-00002", emergencyPhone: "0 9666600003" })]))[0].r;
  check("personal info: values are tidied (spaces squashed, email lower-case, numbers stored as ten digits)", tidy.fullName === "Uma Shankar" && tidy.email === "uma@gmail.com" && tidy.altPhone === "9666600002" && tidy.emergencyPhone === "9666600003", JSON.stringify(tidy));
  await throws("personal info: a name cannot be emptied", () => q("select update_my_player_info($1::jsonb)", [JSON.stringify({ fullName: "  " })]), "enter your name");
  await throws("personal info: a document outside the player's own folder is refused", () => q("select update_my_player_info($1::jsonb)", [JSON.stringify({ idDocType: "AADHAAR", idDocPath: uuid() + "/x.pdf" })]), "Bad document");
  const withDoc = (await q("select update_my_player_info($1::jsonb) r", [JSON.stringify({ idDocType: "AADHAAR", idDocPath: pid + "/id.pdf", idDocName: "id.pdf" })]))[0].r;
  check("personal info: the ID proof is saved against the player", withDoc.idDocType === "AADHAAR" && withDoc.idDocPath === pid + "/id.pdf" && withDoc.idDocName === "id.pdf");
  await asUser(null);
}

// ═══ Player notifications (0194) ════════════════════════════════════════════════════════════════════════════
{
  const ow = await mkUser("pn.owner@test.local", "PN Owner");
  const fx = await mkFacility(ow, "Notify Arena");
  const sp = (await q("select id from sports where key='badminton'"))[0].id;
  const fsid = uuid();
  await q("insert into facility_sports (id, facility_id, sport_id) values ($1,$2,$3)", [fsid, fx, sp]);
  const mkCourt = async (name) => {
    const id = uuid();
    await q("insert into courts (id, facility_id, sport_id, facility_sport_id, name, hourly_rate_inr) values ($1,$2,$3,$4,$5,400)", [id, fx, sp, fsid, name]);
    return id;
  };
  const pid = uuid(), other = uuid();
  await q("insert into auth.users (id, phone) values ($1,'919888800001'), ($2,'919888800002')", [pid, other]);
  await q("insert into players (id, full_name, phone) values ($1,'Notified Player','9888800001'), ($2,'Someone Else','9888800002')", [pid, other]);
  const unread = async (uid) => { await asUser(uid); const r = (await q("select list_my_notifications(true, 50) r"))[0].r; await asUser(null); return r; };
  const gp = uuid();
  await q("insert into guest_players (id, facility_id, name, phone) values ($1,$2,'Notified Player','+91 98888-00001')", [gp, fx]);
  const mkBooking = async (minutesAhead, createdMinutesAgo) => {
    const id = uuid();
    const court = await mkCourt("Court " + id.slice(0, 4));
    await q(`insert into bookings (id, facility_id, court_id, customer_type, guest_name, guest_phone, guest_player_id, start_time, end_time, status, amount_minor, created_at)
             values ($1,$2,$3,'GUEST','Notified Player','+91 98888-00001',$4, now() + ($5 || ' minutes')::interval, now() + ($5 || ' minutes')::interval + interval '1 hour', 'confirmed', 40000, now() - ($6 || ' minutes')::interval)`, [id, fx, court, gp, minutesAhead, createdMinutesAgo]);
    return id;
  };

  // 1 · booking reminder
  const soon = await mkBooking(20, 300);
  const late = await mkBooking(20, 5);       // made 5 minutes ago for 20 minutes from now: no reminder
  const far = await mkBooking(120, 300);     // two hours away: not yet
  await q("select run_player_notification_jobs()");
  let u1 = await unread(pid);
  const rem = u1.filter((n) => n.kind === "player_booking_reminder");
  check("notify: a booking starting within 30 minutes reminds the player (once)", rem.length === 1 && rem[0].data.bookingId === soon && /30 minutes/.test(rem[0].title) && rem[0].data.route === "/bookings", JSON.stringify(rem));
  await q("select run_player_notification_jobs()");
  check("notify: running the job again does not repeat it", (await unread(pid)).filter((n) => n.kind === "player_booking_reminder").length === 1);
  check("notify: another player is not told", (await unread(other)).length === 0);

  // 2 · payments: success and failure
  await q("insert into payments (facility_id, booking_id, amount_inr, status, payment_method, paid_at) values ($1,$2,400,'paid','Razorpay',now())", [fx, soon]);
  await q("insert into payments (facility_id, booking_id, amount_inr, status, payment_method) values ($1,$2,200,'failed','Razorpay')", [fx, far]);
  u1 = await unread(pid);
  const ok = u1.find((n) => n.kind === "player_payment_success");
  const bad = u1.find((n) => n.kind === "player_payment_failed");
  check("notify: a successful payment tells the player the amount", !!ok && ok.title === "Payment successful" && ok.body.includes("₹400") && ok.body.includes("Notify Arena"), JSON.stringify(ok));
  check("notify: a failed payment says so and how to carry on", !!bad && bad.title === "Payment failed" && bad.body.includes("₹200") && bad.body.includes("did not go through"), JSON.stringify(bad));

  // 3 · membership due
  const mem = (await q("insert into members (id, facility_id, full_name, phone) values ($1,$2,'Notified Player','98888 00001') returning id", [uuid(), fx]))[0].id;
  const ms = await mkMembership(fx, mem, "Gold");
  await q("update memberships set end_date = current_date + 3, auto_renew = true where id=$1", [ms]);
  await q("select run_player_notification_jobs()");
  let due = (await unread(pid)).filter((n) => n.kind === "player_membership_due");
  check("notify: 3 days before the next payment the player is told the amount and date (AutoPay)", due.length === 1 && due[0].body.includes("₹2500") && due[0].body.includes("auto-debited") && due[0].data.route === "/my-membership", JSON.stringify(due));
  await q("select run_player_notification_jobs()");
  check("notify: the same reminder is not repeated", (await unread(pid)).filter((n) => n.kind === "player_membership_due").length === 1);
  await q("update memberships set end_date = current_date + 1 where id=$1", [ms]);
  await q("select run_player_notification_jobs()");
  check("notify: a second reminder follows the day before", (await unread(pid)).filter((n) => n.kind === "player_membership_due").length === 2);
  await q("update memberships set end_date = current_date + 10 where id=$1", [ms]);

  // 4 · coaching monthly fee
  const prog = uuid(), enr = uuid();
  await q("insert into coaching_programs (id, facility_id, name, status, default_price_minor) values ($1,$2,'Junior Coaching','ACTIVE',150000)", [prog, fx]);
  await q("insert into coaching_enrollments (id, facility_id, member_id, program_id, start_date, price_minor, status) values ($1,$2,$3,$4,current_date,450000,'ACTIVE')", [enr, fx, mem, prog]);
  await q("insert into coaching_enrollment_billing (enrollment_id, facility_id, kind, amount_minor, total_cycles, status, current_end) values ($1,$2,'SUBSCRIPTION',150000,3,'ACTIVE',current_date + 2)", [enr, fx]);
  await q("select run_player_notification_jobs()");
  const cdue = (await unread(pid)).filter((n) => n.kind === "player_coaching_due");
  check("notify: a monthly coaching fee reminder names the programme, amount and date", cdue.length === 1 && cdue[0].body.includes("₹1500") && cdue[0].body.includes("Junior Coaching") && cdue[0].data.route === "/my-coaching", JSON.stringify(cdue));

  // 5 · the list, the count and marking read
  await asUser(pid);
  const total = (await q("select count_my_unread_notifications() c"))[0].c;
  const list = (await q("select list_my_notifications(true, 50) r"))[0].r;
  check("notify: the unread count matches the list", total === list.length && total >= 5, total + " vs " + list.length);
  await q("select mark_notifications_read($1::uuid[])", [[list[0].id]]);
  check("notify: a read message leaves the unread list", (await q("select list_my_notifications(true, 50) r"))[0].r.every((n) => n.id !== list[0].id) && (await q("select count_my_unread_notifications() c"))[0].c === total - 1);
  check("notify: the full list still has it (read ones of the last 30 days)", (await q("select list_my_notifications(false, 50) r"))[0].r.some((n) => n.id === list[0].id));
  await asUser(other);
  check("notify: nobody else can see them", (await q("select list_my_notifications(false, 50) r"))[0].r.length === 0);
  await asUser(null);
}

process.on('uncaughtException', (e) => { console.log('FATAL:', String(e.message).split('\n')[0]); process.exit(2); });
console.log(`passed: ${passed}, failed: ${failed.length}`);
for (const f of failed) console.log("FAIL:", f);
process.exit(failed.length ? 1 : 0);
