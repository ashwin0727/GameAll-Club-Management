// Runs the QA dataset (seed → verify → cleanup) against every migration applied to an in-memory Postgres (PGlite): no Docker, no real
// database. It proves the scripts in supabase/scripts/ apply cleanly and that the data has the shape the test plan promises.
//
//   cd supabase/tests/pglite && npm install && node qa_seed_check.mjs
import { PGlite } from "@electric-sql/pglite";
import { btree_gist } from "@electric-sql/pglite/contrib/btree_gist";
import { pgcrypto } from "@electric-sql/pglite/contrib/pgcrypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

process.on("unhandledRejection", (e) => { console.log("FATAL:", String((e && e.message) || e).split("\n")[0]); process.exit(2); });

const migrations = fileURLToPath(new URL("../../migrations", import.meta.url));
const scripts = fileURLToPath(new URL("../../scripts", import.meta.url));
const db = new PGlite({ extensions: { btree_gist, pgcrypto } });
const notices = [];
await db.exec(`
  create role anon nologin; create role authenticated nologin; create role service_role nologin; create role supabase_admin nologin;
  create schema if not exists auth;
  create table auth.users (id uuid primary key default gen_random_uuid(), email text unique, encrypted_password text, email_confirmed_at timestamptz,
    phone text, raw_user_meta_data jsonb default '{}'::jsonb, raw_app_meta_data jsonb default '{}'::jsonb, created_at timestamptz default now(),
    updated_at timestamptz default now(), banned_until timestamptz, last_sign_in_at timestamptz, instance_id uuid, aud text, role text,
    confirmation_token text, recovery_token text, email_change_token_new text, email_change text);
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
console.log("applying migrations…");
for (const f of fs.readdirSync(migrations).filter((f) => f.endsWith(".sql")).sort()) {
  try { await db.exec(fs.readFileSync(path.join(migrations, f), "utf8").replace(/^﻿/, "")); }
  catch (e) { console.log("MIGRATION FAILED", f, String(e.message).split("\n")[0]); process.exit(1); }
}
const q = async (sql, params = []) => (await db.query(sql, params)).rows;
// the e-mail the seed script is set to (so the test account always matches whatever you put in the script)
const OWNER = fs.readFileSync(path.join(scripts, "seed_qa_edge_cases.sql"), "utf8").match(/v_owner_email\s+text\s+:= '([^']+)'/)[1];
const PHONE = "9876543210";
const ownerId = crypto.randomUUID();
await q(`insert into auth.users (id, email, email_confirmed_at) values ($1,$2,now())`, [ownerId, OWNER]);
await q(`insert into profiles (id, full_name, email) values ($1,'QA Owner',$2) on conflict (id) do nothing`, [ownerId, OWNER]);

let passed = 0; const failed = [];
const check = (name, cond, detail = "") => { if (cond) passed++; else failed.push(`${name} ${detail}`); };

async function run(file, tweak = (s) => s) {
  const sql = tweak(fs.readFileSync(path.join(scripts, file), "utf8"));
  const t = Date.now();
  await db.exec(sql);
  console.log(`ran ${file} in ${((Date.now() - t) / 1000).toFixed(1)} s`);
}

// ── seed (with the test player's phone set) ──
db.onNotification?.((n) => notices.push(n));
// while checking, a failed venue block must STOP the run so its message is shown (the real script only prints a notice and carries on)
const loud = (s) => s.replace(/raise notice ('[^']*(?:failed|skipped)[^']*')/g, "raise exception $1");
await run("seed_qa_edge_cases.sql", (s) => loud(s.replace("v_player_phone text    := '';", `v_player_phone text    := '${PHONE}';`)));

// ── what was built ──
const count = async (sql) => Number((await q(sql))[0].n);
const venues = await count(`select count(*) n from facilities where slug like 'qa-%' and slug not like 'qa-load-%'`);
check("25 hand-made venues", venues === 25, `got ${venues}`);
check("60 load venues", (await count(`select count(*) n from facilities where slug like 'qa-load-%'`)) === 60);

const names = async (kind, city = "Bangalore", state = "Karnataka") =>
  (await q(`select e->>'name' n from jsonb_array_elements(list_public_venue_cards($1,$2,$3)) e`, [city, state, kind])).map((r) => r.n);
const vl = await names("venues");
check("inactive venue hidden", !vl.some((n) => /Inactive/.test(n)));
check("half set-up venue hidden", !vl.some((n) => /Half Set Up/.test(n)));
check("no-bookable-court venue not in Venues", !vl.some((n) => /No Bookable Court/.test(n)));
check("multi-sport venue listed", vl.includes("QA Multi-Sport Arena"));
check("Bengaluru spelling merged into Bangalore", vl.includes("QA Bengaluru Spelling"));
check("Chennai venues not in Bangalore", !vl.includes("QA Chennai Courts"));
check("Chennai has 2", (await names("venues", "Chennai", "Tamil Nadu")).filter((n) => n.startsWith("QA")).length === 2);

const ml = await names("memberships");
check("no-bookable-court venue IS in Memberships", ml.includes("QA No Bookable Court"));
check("inactive venue not in Memberships", !ml.some((n) => /Inactive/.test(n)));
check("24x7 turf (no plans) not in Memberships", !ml.includes("QA 24x7 Turf"));
check("Hyderabad has no memberships", (await names("memberships", "Hyderabad", "Telangana")).length === 0);

// membership prices per length and per sport
const arena = (await q(`select e from jsonb_array_elements(list_public_venue_cards('Bangalore','Karnataka','memberships')) e where e->>'name'='QA Multi-Sport Arena'`))[0]?.e;
check("arena has per-sport plans", Array.isArray(arena?.memberships?.bySport) && arena.memberships.bySport.length >= 4, JSON.stringify(arena?.memberships?.bySport)?.slice(0, 200));
const bySport = Object.fromEntries((arena?.memberships?.bySport ?? []).map((s) => [s.sport, s.plans.map((p) => p.priceInr).sort((a, b) => a - b)]));
check("Padel plans 3200 + 17000", JSON.stringify(bySport["Padel"]) === JSON.stringify([3200, 17000]), JSON.stringify(bySport));
check("Football plans 2800 + 7500", JSON.stringify(bySport["Football"]) === JSON.stringify([2800, 7500]), JSON.stringify(bySport));
const budget = (await q(`select e from jsonb_array_elements(list_public_venue_cards('Bangalore','Karnataka','memberships')) e where e->>'name'='QA Budget Courts'`))[0]?.e;
const days = (budget?.memberships?.plans ?? []).map((p) => p.durationDays).sort((a, b) => a - b);
check("budget venue plan lengths 7,10,30,45 (inactive plan absent)", JSON.stringify(days) === JSON.stringify([7, 10, 30, 45]), JSON.stringify(days));
check("venue hours are returned", !!arena?.hours?.opens);

// coaching: latest programme per venue AND sport
const coaching = await q(`select e from jsonb_array_elements(list_public_coaching_programs('Bangalore','Karnataka')) e`);
const row = (venue, sport) => coaching.map((r) => r.e).find((e) => e.venue.name === venue && e.sport === sport);
check("arena badminton shows the NEWER Beginner programme", row("QA Multi-Sport Arena", "Badminton")?.name === "Badminton Beginner Program", row("QA Multi-Sport Arena", "Badminton")?.name);
check("arena has 4 sports of coaching", coaching.filter((r) => r.e.venue.name === "QA Multi-Sport Arena").length === 4);
check("football juniors has no coach", row("QA Multi-Sport Arena", "Football")?.coach == null);
check("padel pro clinic is 1-to-1 at 25,000", row("QA Multi-Sport Arena", "Other")?.priceMinor === 2500000 || row("QA Multi-Sport Arena", "Padel")?.priceMinor === 2500000);
check("early-bird discount applied (3,999 - 500)", row("QA Coaching Showcase", "Badminton")?.priceMinor === 349900, String(row("QA Coaching Showcase", "Badminton")?.priceMinor));
check("expired early bird = full price", row("QA Coaching Showcase", "Tennis")?.priceMinor === 450000, String(row("QA Coaching Showcase", "Tennis")?.priceMinor));
check("free trial is 0", row("QA Coaching Showcase", "Cricket")?.priceMinor === 0);
check("no pickleball row (ended / inactive)", !row("QA Coaching Showcase", "Pickleball"));
check("inactive venue has no coaching row", !coaching.some((r) => /Inactive/.test(r.e.venue.name)));
check("coach details travel", row("QA Multi-Sport Arena", "Badminton")?.coach?.name === "Arjun" && row("QA Multi-Sport Arena", "Badminton")?.coach?.experienceYears === 8);

// the venue's own enrolment answers (the Player app's fallback and the enrol pages)
const full = (await q(`select get_public_membership_enroll((select id from facilities where slug='qa-memberships-full')) j`))[0].j;
const spare = Object.fromEntries((full?.slots ?? []).map((s) => [s.startTime, s.spare]));
check("full slot has 0 seats, morning slot 3", spare["18:00:00"] === 0 && spare["06:00:00"] === 3, JSON.stringify(spare));
const show = (await q(`select get_public_coaching_enroll((select id from facilities where slug='qa-coaching-showcase')) j`))[0].j;
const closed = (show?.programs ?? []).find((p) => p.name === "Tennis Closed Enrolment");
check("closed enrolment programme says so", closed?.enrollmentOpen === false);

// bookings and maintenance
check("fully booked tomorrow = 16 bookings", (await count(`select count(*) n from bookings b join facilities f on f.id=b.facility_id where f.slug='qa-fully-booked' and (b.start_time at time zone 'Asia/Kolkata')::date = (now() at time zone 'Asia/Kolkata')::date + 1`)) === 16);
check("maintenance block exists", (await count(`select count(*) n from maintenance_blocks mb join facilities f on f.id=mb.facility_id where f.slug='qa-maintenance' and mb.status='ACTIVE'`)) === 1);

// the test player's payment states, as the Home function sees them
const player = crypto.randomUUID();
await q(`insert into auth.users (id, email, email_confirmed_at) values ($1,'qa.player@example.invalid',now())`, [player]);
await q(`insert into players (id, full_name, phone) values ($1,'QA Test Player',$2) on conflict (id) do update set phone = excluded.phone`, [player, PHONE]);
await q(`select set_config('request.jwt.claim.sub', $1, false)`, [player]);
let dash;
try { dash = (await q(`select get_player_dashboard() j`))[0].j; } catch (e) { failed.push("get_player_dashboard failed: " + e.message.split("\n")[0]); }
if (dash) {
  const mem = Object.fromEntries((dash.memberships ?? []).map((m) => [m.planName, m.paymentIncomplete]));
  check("paid + AutoPay-active memberships are NOT incomplete", mem["Badminton Monthly"] === false && mem["Badminton Quarterly"] === false, JSON.stringify(mem));
  check("unpaid / failed / part-paid / halted ARE incomplete", mem["Padel Monthly"] === true && mem["Football Monthly"] === true && mem["Tennis Monthly"] === true && mem["Pickleball Monthly"] === true, JSON.stringify(mem));
  check("expired and pending-status memberships are not listed", !("Badminton Yearly" in mem) && !("Padel Half-Year" in mem), JSON.stringify(mem));
  const pp = dash.pendingPayments ?? [];
  const state = (title) => pp.find((p) => (p.title ?? "").includes(title))?.state;
  check("Padel unpaid → PENDING", state("Padel") === "PENDING", JSON.stringify(pp.map((p) => [p.kind, p.title, p.state])));
  check("Football failed → FAILED", state("Football") === "FAILED");
  check("Pickleball halted AutoPay → FAILED", state("Pickleball") === "FAILED");
  check("Tennis part-paid → PENDING", state("Tennis") === "PENDING");
  check("3 unpaid upcoming guest bookings (+3 d, +4 d, +45 d) → 3 booking prompts", pp.filter((p) => p.kind === "booking").length === 3, String(pp.filter((p) => p.kind === "booking").length));
}


// ── Membership Details (get_my_membership_details) for the same player ──
let det;
try { det = (await q(`select get_my_membership_details() j`))[0].j; } catch (e) { failed.push("get_my_membership_details failed: " + e.message.split("\n")[0]); }
if (det) {
  const by = Object.fromEntries(det.map((d) => [d.planName, d]));
  check("details: the 6 ACTIVE memberships only (expired + pending excluded)", det.length === 6 && !by["Badminton Yearly"] && !by["Padel Half-Year"], Object.keys(by).join(","));
  check("details: membership ref MBR-QAM-00000n", /^MBR-QAM-\d{6}$/.test(det[0]?.membershipRef ?? ""), det[0]?.membershipRef);
  check("details: pay states", by["Badminton Monthly"]?.payState === "PAID" && by["Padel Monthly"]?.payState === "PENDING" && by["Football Monthly"]?.payState === "FAILED"
    && by["Tennis Monthly"]?.payState === "PENDING" && by["Pickleball Monthly"]?.payState === "FAILED" && by["Badminton Quarterly"]?.payState === "PAID",
    JSON.stringify(Object.fromEntries(Object.entries(by).map(([k, v]) => [k, v.payState]))));
  check("details: part payment shows paid 1000 of 2000", by["Tennis Monthly"]?.paidInr === 1000 && by["Tennis Monthly"]?.totalInr === 2000);
  check("details: venue block", by["Padel Monthly"]?.venue?.name === "QA Multi-Sport Arena" && !!by["Padel Monthly"]?.venue?.imageUrl);
  check("details: payments list", by["Badminton Monthly"]?.payments?.length === 1 && by["Badminton Monthly"]?.payments[0].status === "paid" && by["Badminton Monthly"]?.payments[0].amountInr === 1500);
  check("details: failed payment listed", by["Football Monthly"]?.payments?.[0]?.status === "failed");
  check("details: AutoPay status", by["Pickleball Monthly"]?.autopayStatus === "halted" && by["Badminton Quarterly"]?.autopayStatus === "active");
  check("details: plan price and duration", by["Badminton Quarterly"]?.priceInr === 4000 && by["Badminton Quarterly"]?.durationDays === 90);
  check("details: usage object present", by["Badminton Monthly"]?.usage && "sessionsUsed" in by["Badminton Monthly"].usage);
  check("details: bookings is an array", Array.isArray(by["Badminton Monthly"]?.bookings));
  // give the Monthly membership a batch slot and one session played today, then read the usage back
  const m = (await q(`select ms.id ms_id, ms.member_id, ms.facility_id from memberships ms where ms.name = 'Badminton Monthly' limit 1`))[0];
  const batch = (await q(`select id from membership_batches where facility_id = $1 and name = 'Badminton Morning' limit 1`, [m.facility_id]))[0];
  await q(`alter table membership_batch_members disable trigger membership_batch_members_eligible`);
  await q(`insert into membership_batch_members (batch_id, member_id, membership_id) values ($1,$2,$3)`, [batch.id, m.member_id, m.ms_id]);
  await q(`alter table membership_batch_members enable trigger membership_batch_members_eligible`);
  const court = (await q(`select id from courts where facility_id = $1 and name = 'Badminton Court 1'`, [m.facility_id]))[0].id;
  await q(`insert into bookings (facility_id, court_id, member_id, customer_type, start_time, end_time, status, amount_minor, currency, payment_status, party_size, created_by)
           values ($1, $2, $3, 'MEMBER', ((now() at time zone 'Asia/Kolkata')::date + time '06:00') at time zone 'Asia/Kolkata',
                   ((now() at time zone 'Asia/Kolkata')::date + time '07:00') at time zone 'Asia/Kolkata', 'completed', 0, 'INR', 'PAID', 2, $4)`, [m.facility_id, court, m.member_id, ownerId]);
  const det2 = (await q(`select get_my_membership_details() j`))[0].j.find((d) => d.planName === "Badminton Monthly");
  check("details: slot comes from the roster", det2?.slot?.batchName === "Badminton Morning" && det2?.slot?.court === "Badminton Court 1" && det2?.slot?.sport === "Badminton" && det2?.slot?.startTime === "06:00", JSON.stringify(det2?.slot));
  check("details: sessions total counts the slot's weekdays this month", Number(det2?.usage?.sessionsTotal) >= 1 && Number(det2?.usage?.sessionsTotal) <= 27, JSON.stringify(det2?.usage));
  check("details: today's completed booking counts as 1 used session", Number(det2?.usage?.sessionsUsed) === 1, JSON.stringify(det2?.usage));
  check("details: the booking is listed", det2?.bookings?.length === 1 && det2?.bookings[0].status === "completed", JSON.stringify(det2?.bookings));
  // a stranger, and nobody signed in, see nothing
  const stranger = crypto.randomUUID();
  await q(`insert into auth.users (id, email, email_confirmed_at) values ($1,'stranger@example.invalid',now())`, [stranger]);
  await q(`insert into players (id, full_name, phone) values ($1,'Stranger','9000012345') on conflict (id) do nothing`, [stranger]);
  await q(`select set_config('request.jwt.claim.sub', $1, false)`, [stranger]);
  const none = (await q(`select get_my_membership_details() j`))[0].j;
  check("details: another player sees none of it", none.length === 0, String(none.length));
  await q(`select set_config('request.jwt.claim.sub', '', false)`);
  const anon = (await q(`select get_my_membership_details() j`))[0].j;
  check("details: nobody signed in sees none of it", anon.length === 0);
}


// ── My Coaching (get_my_coaching_details) for the same player ──
await q(`select set_config('request.jwt.claim.sub', $1, false)`, [player]);
let cdet;
try { cdet = (await q(`select get_my_coaching_details() j`))[0].j; } catch (e) { failed.push("get_my_coaching_details failed: " + e.message.split("\n")[0]); }
if (cdet) {
  console.log("coaching details:", JSON.stringify(cdet.map((c) => [c.programName, c.status, c.feeType, c.payState, c.progress, c.coach?.name, c.batch?.name])));
  check("coaching details: returns a list", Array.isArray(cdet));
  check("coaching details: only ACTIVE / PAUSED enrolments", cdet.every((c) => ["ACTIVE", "PAUSED"].includes(c.status)));
  check("coaching details: every item has venue, progress and pay state", cdet.every((c) => c.venue?.name && c.progress && ["PAID", "PENDING", "FAILED"].includes(c.payState)));
  check("coaching details: reference CRS-xxx-xxxxxx", cdet.every((c) => /^CRS-[A-Z]{3}-[0-9A-F]{6}$/.test(c.enrollmentRef)), cdet[0]?.enrollmentRef);
  check("coaching details: percent is 0..100", cdet.every((c) => c.progress.percent >= 0 && c.progress.percent <= 100));
  check("coaching details: lists are arrays", cdet.every((c) => Array.isArray(c.upcoming) && Array.isArray(c.past) && Array.isArray(c.payments) && Array.isArray(c.notes)));
  check("coaching details: no rating is invented", cdet.every((c) => !c.coach || c.coach.rating === null));
}
await q(`select set_config('request.jwt.claim.sub', '', false)`);
try { const anon = (await q(`select get_my_coaching_details() j`))[0].j; check("coaching details: nobody signed in → empty", Array.isArray(anon) && anon.length === 0, JSON.stringify(anon)); } catch (e) { failed.push("coaching anon: " + e.message.split("\n")[0]); }

// real data for the coaching page: one enrolment with a coach, a batch, sessions (3 done, 1 cancelled, 2 to come), a payment and a note
{
  const ph = (await q(`select phone from players where id=$1`, [player]))[0].phone;
  const fac = (await q(`select id from facilities where slug='qa-coaching-showcase'`))[0].id;
  const mem = (await q(`insert into members (facility_id, full_name, phone, status) values ($1,'Coach Student',$2,'ACTIVE') returning id`, [fac, ph]))[0].id;
  const pr = (await q(`select cp.id program_id, b.id batch_id, b.court_id, b.coach_id from coaching_programs cp join coaching_program_batches b on b.program_id=cp.id where cp.facility_id=$1 and cp.name='Early Bird Monthly'`, [fac]))[0];
  const en = (await q(`insert into coaching_enrollments (facility_id, member_id, program_id, coach_id, batch_id, start_date, end_date, sessions_total, price_minor, fee_type, status)
                       values ($1,$2,$3,$4,$5,current_date-10,current_date+80,24,899900,'MONTHLY','ACTIVE') returning id`, [fac, mem, pr.program_id, pr.coach_id, pr.batch_id]))[0].id;
  await q(`insert into coaching_enrollment_billing (enrollment_id, facility_id, kind, status, amount_minor, total_cycles) values ($1,$2,'SUBSCRIPTION','ACTIVE',299900,3)`, [en, fac]);
  const offs = [[-9, "COMPLETED"], [-7, "COMPLETED"], [-5, "COMPLETED"], [-3, "CANCELLED"], [2, "SCHEDULED"], [4, "SCHEDULED"]];
  let k = 0;
  for (const [d, st] of offs) {
    k++;
    const s = (await q(`insert into coaching_sessions (facility_id, program_id, coach_id, court_id, start_at, end_at, status, batch_id)
                        values ($1,$2,$3,$4, date_trunc('day', now()) + ($5 || ' days')::interval + ($8 || ' hours')::interval, date_trunc('day', now()) + ($5 || ' days')::interval + (($8::int + 1) || ' hours')::interval, $6, $7) returning id`,
                       [fac, pr.program_id, pr.coach_id, pr.court_id, String(d), st, pr.batch_id, String(1 + k)]))[0].id;
    await q(`insert into coaching_session_students (session_id, enrollment_id, facility_id) values ($1,$2,$3)`, [s, en, fac]);
  }
  await q(`insert into payments (facility_id, member_id, coaching_enrollment_id, amount_inr, status, payment_method, paid_at) values ($1,$2,$3,2999,'paid','UPI', now() - interval '10 days')`, [fac, mem, en]);
  await q(`insert into student_progress_notes (facility_id, enrollment_id, coach_id, skill_or_goal, note, progress_status) values ($1,$2,$3,'Footwork','Good split-step timing; keep working on recovery.','ON_TRACK')`, [fac, en, pr.coach_id]);
  await q(`select set_config('request.jwt.claim.sub', $1, false)`, [player]);
  const c = (await q(`select get_my_coaching_details() j`))[0].j.find((x) => x.programName === "Early Bird Monthly");
  check("coaching details: the enrolment is listed", !!c);
  check("coaching details: progress 3 of 24 → 13%", c?.progress?.sessionsTotal === 24 && c?.progress?.sessionsAttended === 3 && c?.progress?.percent === 13, JSON.stringify(c?.progress));
  check("coaching details: upcoming (batch sessions included, max 6) and past (3 done + 1 cancelled)", c?.upcoming?.length >= 2 && c?.upcoming?.length <= 6 && c?.past?.length >= 4, `${c?.upcoming?.length}/${c?.past?.length}`);
  check("coaching details: the upcoming list is soonest first", c?.upcoming?.[0]?.startTime < c?.upcoming?.[1]?.startTime);
  check("coaching details: monthly fee — one charge ₹2,999 of ₹8,999, paid by AutoPay", c?.chargeInr === 2999 && c?.totalInr === 8999 && c?.feeType === "MONTHLY" && c?.payState === "PAID", JSON.stringify([c?.chargeInr, c?.totalInr, c?.feeType, c?.payState]));
  check("coaching details: coach and batch", c?.coach?.name === "Bare Bones" && c?.batch?.name === "Evening" && JSON.stringify(c?.batch?.daysOfWeek) === "[1,3,5]" && c?.batch?.startTime === "18:00", JSON.stringify([c?.coach, c?.batch]));
  check("coaching details: a coach with no rating shows none", c?.coach?.rating === null);
  check("coaching details: payment and note", c?.payments?.length === 1 && c?.payments?.[0]?.amountInr === 2999 && c?.notes?.length === 1 && c?.notes?.[0]?.skill === "Footwork", JSON.stringify([c?.payments, c?.notes]));
  check("coaching details: venue and sport", c?.venue?.name === "QA Coaching Showcase" && c?.sport === "Badminton", JSON.stringify([c?.venue?.name, c?.sport]));
  // another player sees nothing of it
  await q(`select set_config('request.jwt.claim.sub', '', false)`);
}
// ── Guest bookings page (get_my_guest_bookings) for the same player ──
{
  await q(`select set_config('request.jwt.claim.sub', $1, false)`, [player]);
  let gb;
  try { gb = (await q(`select get_my_guest_bookings() j`))[0].j; } catch (e) { failed.push("get_my_guest_bookings failed: " + e.message.split("\n")[0]); }
  if (gb) {
    console.log("guest bookings:", JSON.stringify({ up: gb.upcoming.length, done: gb.completed.length, cancelled: gb.cancelled.length }));
    check("guest bookings: has the three lists", Array.isArray(gb.upcoming) && Array.isArray(gb.completed) && Array.isArray(gb.cancelled));
    check("guest bookings: the seed's 3 unpaid upcoming bookings are listed, soonest first", gb.upcoming.length >= 3 && gb.upcoming.every((b, i, a) => i === 0 || a[i - 1].startTime <= b.startTime), String(gb.upcoming.length));
    check("guest bookings: every booking has ref, venue, court, sport, amount and pay state", [...gb.upcoming, ...gb.completed, ...gb.cancelled].every((b) => /^GBK-[A-Z]{3}-[0-9A-F]{5}$/.test(b.ref) && b.venue?.name && ["PAID", "PARTIAL", "PENDING"].includes(b.payState)), JSON.stringify(gb.upcoming[0]));
    check("guest bookings: counts are numbers", typeof gb.completedCount === "number" && typeof gb.cancelledCount === "number");
  }
  await q(`select set_config('request.jwt.claim.sub', '', false)`);
  try { const none = (await q(`select get_my_guest_bookings() j`))[0].j; check("guest bookings: nobody signed in sees none", none.upcoming.length === 0 && none.completed.length === 0 && none.cancelled.length === 0); } catch (e) { failed.push("guest anon: " + e.message.split("\n")[0]); }
}

// ── Payment receipt (get_my_payment_receipt): the payment progress → success page ──
{
  await q(`select set_config('request.jwt.claim.sub', $1, false)`, [player]);
  const msId = async (name) => (await q(`select id from memberships where name = $1 limit 1`, [name]))[0].id;
  const rc = async (kind, id) => (await q(`select get_my_payment_receipt($1, $2) j`, [kind, id]))[0].j;
  const paid = await rc("membership", await msId("Badminton Monthly"));
  check("receipt: paid membership is PAID with amount, receipt no and reference fields", paid?.state === "PAID" && paid?.paidInr === 1500 && paid?.amountInr === 1500 && /^RCP-[0-9A-F]{8}$/.test(paid?.receiptNo ?? ""), JSON.stringify(paid)?.slice(0, 240));
  check("receipt: membership details (ref, plan, dates, venue)", /^MBR-QAM-\d{6}$/.test(paid?.details?.membershipRef ?? "") && paid?.details?.planName === "Badminton Monthly" && paid?.venue?.name === "QA Multi-Sport Arena" && !!paid?.details?.startDate && !!paid?.details?.endDate, JSON.stringify(paid?.details)?.slice(0, 200));
  const pending = await rc("membership", await msId("Padel Monthly"));
  check("receipt: unpaid membership is PENDING, total 3200, nothing paid", pending?.state === "PENDING" && pending?.totalInr === 3200 && pending?.paidInr === 0 && pending?.balanceInr === 3200, JSON.stringify(pending)?.slice(0, 200));
  const failed = await rc("membership", await msId("Football Monthly"));
  check("receipt: failed payment is FAILED", failed?.state === "FAILED");
  const part = await rc("membership", await msId("Tennis Monthly"));
  check("receipt: part-paid is PENDING with balance 1000", part?.state === "PENDING" && part?.paidInr === 1000 && part?.balanceInr === 1000, JSON.stringify(part)?.slice(0, 160));
  const halted = await rc("membership", await msId("Pickleball Monthly"));
  check("receipt: AutoPay halted is FAILED", halted?.state === "FAILED" && halted?.autopay === true && halted?.autopayStatus === "halted");
  const auto = await rc("membership", await msId("Badminton Quarterly"));
  check("receipt: AutoPay active is PAID by mandate, method UPI AutoPay, amount = the plan's total", auto?.state === "PAID" && auto?.autopay === true && auto?.method === "UPI AutoPay" && auto?.amountInr === 4000, JSON.stringify(auto)?.slice(0, 220));

  // bookings
  const bk = async (offset, state) => (await q(`select b.id from bookings b where b.guest_phone = $1 and b.payment_status = $2 and (b.start_time at time zone 'Asia/Kolkata')::date = (now() at time zone 'Asia/Kolkata')::date + $3::int limit 1`, [PHONE, state, offset]))[0]?.id;
  const bPaid = await rc("booking", await bk(2, "PAID"));
  check("receipt: paid booking has court, sport, times and a GBK ref", bPaid?.state === "PAID" && bPaid?.details?.court === "Badminton Court 1" && bPaid?.details?.sport === "Badminton" && /^GBK-[A-Z]{3}-[0-9A-F]{5}$/.test(bPaid?.details?.bookingRef ?? ""), JSON.stringify(bPaid)?.slice(0, 260));
  const bPend = await rc("booking", await bk(3, "PENDING"));
  check("receipt: unpaid booking is PENDING for 400", bPend?.state === "PENDING" && bPend?.totalInr === 400 && bPend?.balanceInr === 400, JSON.stringify(bPend)?.slice(0, 200));

  // coaching: an enrolment the player paid, and one they did not
  const mem = (await q(`select id, facility_id from members where full_name = 'QA Test Player' limit 1`))[0];
  const prog = async (name) => (await q(`select id from coaching_programs where facility_id = $1 and name = $2`, [mem.facility_id, name]))[0].id;
  const e1 = (await q(`insert into coaching_enrollments (facility_id, member_id, program_id, start_date, price_minor, status) values ($1,$2,$3,current_date,299900,'ACTIVE') returning id`, [mem.facility_id, mem.id, await prog("Badminton Beginner Program")]))[0].id;
  await q(`insert into payments (facility_id, member_id, coaching_enrollment_id, amount_inr, status, payment_method, paid_at) values ($1,$2,$3,2999,'paid','UPI',now())`, [mem.facility_id, mem.id, e1]);
  const e2 = (await q(`insert into coaching_enrollments (facility_id, member_id, program_id, start_date, price_minor, status) values ($1,$2,$3,current_date,350000,'ACTIVE') returning id`, [mem.facility_id, mem.id, await prog("Tennis Starters")]))[0].id;
  const c1 = await rc("coaching", e1);
  check("receipt: paid coaching enrolment is PAID with programme, level and sport", c1?.state === "PAID" && c1?.paidInr === 2999 && c1?.details?.programName === "Badminton Beginner Program" && c1?.details?.level === "Beginner" && c1?.details?.sport === "Badminton", JSON.stringify(c1)?.slice(0, 300));
  const c2 = await rc("coaching", e2);
  check("receipt: unpaid coaching enrolment is PENDING for 3500", c2?.state === "PENDING" && c2?.totalInr === 3500, JSON.stringify(c2)?.slice(0, 200));

  // privacy
  const other = crypto.randomUUID();
  await q(`insert into auth.users (id, email, email_confirmed_at) values ($1,'receipt.other@example.invalid',now())`, [other]);
  await q(`insert into players (id, full_name, phone) values ($1,'Other','9000099999') on conflict (id) do nothing`, [other]);
  await q(`select set_config('request.jwt.claim.sub', $1, false)`, [other]);
  const stolen = await Promise.all([rc("membership", await msId("Badminton Monthly")), rc("coaching", e1), rc("booking", await bk(2, "PAID"))]);
  check("receipt: another player gets nothing for a membership, a coaching enrolment or a booking", stolen.every((x) => x === null), JSON.stringify(stolen).slice(0, 120));
  await q(`select set_config('request.jwt.claim.sub', '', false)`);
  check("receipt: nobody signed in gets nothing", (await rc("membership", await msId("Badminton Monthly"))) === null);
  await q(`select set_config('request.jwt.claim.sub', $1, false)`, [player]);
  check("receipt: unknown kind or id gives nothing", (await rc("nonsense", e1)) === null && (await rc("membership", crypto.randomUUID())) === null);
}

console.log("\nseed notices that mention a failure:");
const bad = notices.filter((n) => /failed|skipped|could not/i.test(n.message));
bad.forEach((n) => console.log("  ·", n.message));
check("no seed block failed", bad.filter((n) => /failed/i.test(n.message) && !/could not add auth user/i.test(n.message)).length === 0, bad.map((n) => n.message).join(" | "));

// ── idempotent: a second run adds nothing ──
const before = await count(`select count(*) n from facilities where slug like 'qa-%'`);
await run("seed_qa_edge_cases.sql", (s) => loud(s.replace("v_player_phone text    := '';", `v_player_phone text    := '${PHONE}';`)));
check("second run is idempotent (no extra venues)", (await count(`select count(*) n from facilities where slug like 'qa-%'`)) === before);

// ── cleanup removes everything ──
await run("cleanup_qa_edge_cases.sql");
check("cleanup removed every QA venue", (await count(`select count(*) n from facilities where slug like 'qa-%'`)) === 0);
check("cleanup removed QA plans / programmes / coaches", (await count(`select (select count(*) from membership_plans) + (select count(*) from coaching_programs) + (select count(*) from coaches) n`)) === 0);
check("cleanup removed QA coach logins", (await count(`select count(*) n from auth.users where email like 'coach.qa.%'`)) === 0);
check("cleanup removed the log table", (await q(`select to_regclass('public.qa_seed_log') r`))[0].r === null);

console.log(`\npassed: ${passed}, failed: ${failed.length}`);
failed.forEach((f) => console.log("  FAIL:", f));
process.exit(failed.length ? 1 : 0);
