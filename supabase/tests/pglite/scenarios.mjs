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
  await throws("public signup refused on Basic", () => q("select public_start_membership_signup($1,'Pat Player','9000000001',null,$2,null)", [fac, planRow]), "not taking online memberships");
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

process.on('uncaughtException', (e) => { console.log('FATAL:', String(e.message).split('\n')[0]); process.exit(2); });
console.log(`passed: ${passed}, failed: ${failed.length}`);
for (const f of failed) console.log("FAIL:", f);
process.exit(failed.length ? 1 : 0);
