// Shared connection + fixture helpers for the DB integration suite.
//
// Two connection kinds:
//   superuser()      — the local `postgres` role; bypasses RLS. Used for
//                      fixtures and for calling functions the app would call
//                      under the service role (webhook path).
//   authed(userId)   — runs as `authenticated` with request.jwt.claims set,
//                      so auth.uid() and every RLS policy behave exactly as
//                      they do for a signed-in facility user.
//
// Each test file truncates the tables it touches in a beforeAll (see
// resetCore). Concurrency tests need real commits, so they cannot wrap in a
// rollback — they rely on that truncate.

import { Client } from "@db/postgres";

const CONN = Deno.env.get("SUPABASE_DB_URL") ??
  "postgresql://postgres:postgres@127.0.0.1:54322/postgres";

export async function superuser(): Promise<Client> {
  const c = new Client(CONN);
  await c.connect();
  return c;
}

export async function authed(userId: string): Promise<Client> {
  const c = new Client(CONN);
  await c.connect();
  await c.queryArray({
    text: "select set_config('request.jwt.claims', $1, false)",
    args: [JSON.stringify({ sub: userId, role: "authenticated" })],
  });
  await c.queryArray("set role authenticated");
  return c;
}

/** Truncate every app table the suite writes to. Cheap; keeps files independent. */
export async function resetCore(su: Client): Promise<void> {
  await su.queryArray(`
    truncate table
      refunds, settlement_exceptions, payments, payment_orders,
      razorpay_webhook_events, public_booking_attempts,
      membership_session_bookings, membership_sessions,
      membership_batch_members, membership_batches,
      bookings, memberships, membership_plans,
      operating_time_slots, operating_days, operating_schedules,
      courts, facility_sports, guest_players,
      facility_users, facilities
    restart identity cascade
  `);
  await su.queryArray(
    `delete from auth.users where email like 'u_%@test.local'`,
  );
}

let seq = 0;
const uniq = () => `${Date.now().toString(36)}${(seq++).toString(36)}`;

export async function makeUser(su: Client): Promise<string> {
  const id = crypto.randomUUID();
  const email = `u_${uniq()}@test.local`;
  await su.queryArray({
    text: `insert into auth.users
             (id, instance_id, aud, role, email, encrypted_password,
              email_confirmed_at, created_at, updated_at,
              raw_app_meta_data, raw_user_meta_data)
           values ($1, '00000000-0000-0000-0000-000000000000',
              'authenticated', 'authenticated', $2, '', now(), now(), now(),
              '{}'::jsonb, $3::jsonb)`,
    args: [id, email, JSON.stringify({ full_name: "Test User" })],
  });
  await su.queryArray({
    text: `insert into profiles (id, full_name, email)
           values ($1, 'Test User', $2) on conflict (id) do nothing`,
    args: [id, email],
  });
  return id;
}

export async function makeFacility(su: Client, ownerId: string): Promise<string> {
  const id = crypto.randomUUID();
  await su.queryArray({
    text: `insert into facilities (id, name, slug, owner_id, timezone, currency)
           values ($1, 'Test Facility', $2, $3, 'Asia/Kolkata', 'INR')`,
    args: [id, `f-${uniq()}`, ownerId],
  });
  await su.queryArray({
    text: `insert into facility_users (facility_id, user_id, role)
           values ($1, $2, 'owner')`,
    args: [id, ownerId],
  });
  return id;
}

export interface Court {
  facilitySportId: string;
  courtId: string;
}

/** A court open 24h, every day, ₹300/hr. */
export async function makeOpenCourt(su: Client, facilityId: string): Promise<Court> {
  const sportId = (await su.queryObject<{ id: string }>(
    "select id from sports where key = 'badminton'",
  )).rows[0].id;

  await su.queryArray({
    text: `insert into facility_sports (facility_id, sport_id)
           values ($1, $2) on conflict (facility_id, sport_id) do nothing`,
    args: [facilityId, sportId],
  });
  const facilitySportId = (await su.queryObject<{ id: string }>({
    text: `select id from facility_sports where facility_id = $1 and sport_id = $2`,
    args: [facilityId, sportId],
  })).rows[0].id;

  const courtId = crypto.randomUUID();
  await su.queryArray({
    text: `insert into courts (id, facility_id, sport_id, facility_sport_id, name, hourly_rate_inr)
           values ($1, $2, $3, $4, $5, 300)`,
    args: [courtId, facilityId, sportId, facilitySportId, `Court ${uniq()}`],
  });

  const scheduleId = crypto.randomUUID();
  await su.queryArray({
    text: `insert into operating_schedules (id, facility_id, scope_type)
           values ($1, $2, 'FACILITY')`,
    args: [scheduleId, facilityId],
  });
  for (let dow = 0; dow < 7; dow++) {
    await su.queryArray({
      text: `insert into operating_days (schedule_id, facility_id, day_of_week, is_24_hours)
             values ($1, $2, $3, true)`,
      args: [scheduleId, facilityId, dow],
    });
  }

  return { facilitySportId, courtId };
}

/** Tomorrow 18:00–19:00 in Asia/Kolkata, as UTC ISO strings. */
export function tomorrowSlot(): { start: string; end: string } {
  const d = new Date();
  d.setUTCDate(d.getUTCDate() + 1);
  // 18:00 IST == 12:30 UTC
  const start = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate(), 12, 30, 0));
  const end = new Date(start.getTime() + 60 * 60 * 1000);
  return { start: start.toISOString(), end: end.toISOString() };
}

export async function closeAll(...clients: Client[]): Promise<void> {
  await Promise.all(clients.map((c) => c.end().catch(() => {})));
}
