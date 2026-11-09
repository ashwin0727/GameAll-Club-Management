-- ═══════════════════════════════════════════════════════════════════════════
-- Player app: database load and abuse protection.
--
-- Every signed-in player's Home, My Membership, My Coaching and Guest Booking pages find "their" rows by PHONE NUMBER
-- (normalize_phone(...) = the player's phone), at every club. Without an index on that expression each call scans the whole members /
-- guest_players / bookings table, so the cost of one page view grows with the whole platform, not with the player. This adds the
-- expression indexes those lookups need, bounds how long a player call may run, and gives the edge functions a shared rate limiter.
--
--   1. expression indexes   members / guest_players / bookings by normalize_phone(...) (it is IMMUTABLE, so it can be indexed), plus the
--                           child lookups the details pages do per enrolment / booking
--   2. statement_timeout    every player-facing and public (anon) read function gets a ceiling, so one slow call (a bad plan, a very
--                           large account) cannot hold a connection for long; Postgres cancels it and the app shows its "try again"
--   3. check_rate_limit     a fixed-window counter the edge functions call before doing expensive work (Razorpay calls, bookings,
--                           payment links): `select check_rate_limit('sync:<user>:<id>', 20, 60)` → false when over the limit.
--                           Service role only. Old windows are removed as it goes.
-- ═══════════════════════════════════════════════════════════════════════════

-- 1 · indexes ─────────────────────────────────────────────────────────────────
create index if not exists members_phone_norm_idx on members (normalize_phone(phone)) where phone is not null;
create index if not exists guest_players_phone_norm_idx on guest_players (normalize_phone(phone)) where phone is not null;
create index if not exists bookings_guest_phone_norm_idx on bookings (normalize_phone(guest_phone)) where customer_type = 'GUEST' and guest_phone is not null;
create index if not exists bookings_guest_player_start_idx on bookings (guest_player_id, start_time desc) where guest_player_id is not null;
create index if not exists coaching_sessions_batch_start_idx on coaching_sessions (batch_id, start_at) where batch_id is not null;
create index if not exists coaching_enrollments_member_status_idx on coaching_enrollments (member_id, status);
create index if not exists payments_enrollment_status_idx on payments (coaching_enrollment_id, status) where coaching_enrollment_id is not null;

-- 2 · ceilings ────────────────────────────────────────────────────────────────
do $$
declare
  r record;
begin
  -- the signed-in player's own reads
  for r in
    select p.oid::regprocedure as sig
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname = any (array[
         'get_player_dashboard', 'get_my_player_home', 'get_my_membership_details', 'get_my_coaching_details',
         'get_my_guest_bookings', 'get_my_payment_receipt', 'player_booking_payment_context'
       ])
  loop
    execute format('alter function %s set statement_timeout = %L', r.sig, '8s');
  end loop;

  -- the public (anonymous) listing and enrolment reads: the cheapest way to hurt the database is to hammer these, so they are tighter
  for r in
    select p.oid::regprocedure as sig
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname = any (array[
         'list_public_venue_cards', 'list_public_coaching_programs', 'get_public_venue', 'get_public_court_availability',
         'get_public_membership_enroll', 'get_public_coaching_enroll'
       ])
  loop
    execute format('alter function %s set statement_timeout = %L', r.sig, '5s');
  end loop;
end;
$$;

-- 3 · a shared rate limiter for the edge functions ───────────────────────────
create table if not exists api_rate_limits (
  bucket text not null,
  window_start timestamptz not null,
  hits integer not null default 0,
  primary key (bucket, window_start)
);
alter table api_rate_limits enable row level security;
-- no policies: nobody but the service role (which bypasses RLS) reads or writes it
revoke all on api_rate_limits from public, anon, authenticated;

-- true when this call is allowed, false when [p_bucket] has used up [p_limit] calls in the current [p_window_seconds] window
create or replace function check_rate_limit(p_bucket text, p_limit integer, p_window_seconds integer default 60)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_window timestamptz;
  v_hits integer;
begin
  if coalesce(p_bucket, '') = '' or p_limit < 1 or p_window_seconds < 1 then
    raise exception 'check_rate_limit needs a bucket, a limit and a window.' using errcode = '22023';
  end if;
  v_window := to_timestamp(floor(extract(epoch from now()) / p_window_seconds) * p_window_seconds);
  insert into api_rate_limits (bucket, window_start, hits) values (p_bucket, v_window, 1)
  on conflict (bucket, window_start) do update set hits = api_rate_limits.hits + 1
  returning hits into v_hits;
  -- housekeeping: now and then drop windows that are long over (about 1 call in 50)
  if random() < 0.02 then
    delete from api_rate_limits where window_start < now() - interval '1 hour';
  end if;
  return v_hits <= p_limit;
end;
$$;
revoke all on function check_rate_limit(text, integer, integer) from public, anon, authenticated;
grant execute on function check_rate_limit(text, integer, integer) to service_role;
