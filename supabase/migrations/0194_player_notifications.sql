-- ═══════════════════════════════════════════════════════════════════════════
-- Player app notifications.
--
-- The notifications table, the device tokens and the push worker (0161) already serve the club app; a player is an auth user too,
-- so the same table holds their messages and the same worker pushes them through Firebase to their phone. What is new here is
-- WHO gets a message and WHEN:
--
--   a court booking starts within 30 minutes           (timed job; once per booking)
--   a membership's next payment is 1 to 3 days away    (timed job; "₹X will be auto-debited on <date>" or "is due on <date>")
--   a coaching programme's monthly fee is 1-3 days away (timed job)
--   any payment succeeds or fails                       (trigger on payments; plus a failed online booking payment and an
--                                                        AutoPay that stopped)
--
-- A player is found from the club's record by MOBILE NUMBER (last ten digits), the same way their bookings and memberships are.
-- Every message carries a dedupe key, so a player is told once however often the job runs.
-- Client calls: list_my_notifications(), count_my_unread_notifications() (mark_notifications_read already exists).
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function _notify_players(
  p_phone text, p_facility uuid, p_kind text, p_title text, p_body text, p_data jsonb, p_dedupe text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  u uuid;
begin
  if normalize_phone(p_phone) is null then return; end if;
  for u in select pl.id from players pl where normalize_phone(pl.phone) = normalize_phone(p_phone) loop
    insert into notifications (user_id, facility_id, kind, title, body, data, dedupe_key)
    values (u, p_facility, p_kind, p_title, p_body, coalesce(p_data, '{}'::jsonb), p_dedupe)
    on conflict (user_id, dedupe_key) where dedupe_key is not null do nothing;
  end loop;
end;
$$;
revoke all on function _notify_players(text, uuid, text, text, text, jsonb, text) from public, anon, authenticated;


-- ── payments: success / failure ──────────────────────────────────────────
create or replace function trg_notify_player_payment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text := new.status::text;
  v_phone text;
  v_what text;
  v_route text;
  v_venue text;
  v_amt text := '₹' || coalesce(new.amount_inr, 0)::text;
  v_name text;
  v_when text;
begin
  if v_status not in ('paid', 'failed') then return new; end if;
  if tg_op = 'UPDATE' and old.status::text = v_status then return new; end if;

  select f.name into v_venue from facilities f where f.id = new.facility_id;

  if new.booking_id is not null then
    select coalesce(nullif(b.guest_phone, ''), gp.phone, mb.phone), c.name,
           to_char(b.start_time at time zone coalesce(f.timezone, 'Asia/Kolkata'), 'DD Mon, HH12:MI AM')
      into v_phone, v_name, v_when
      from bookings b
      left join guest_players gp on gp.id = b.guest_player_id
      left join members mb on mb.id = b.member_id
      left join courts c on c.id = b.court_id
      left join facilities f on f.id = b.facility_id
     where b.id = new.booking_id;
    v_what := 'your ' || coalesce(v_name, 'court') || ' booking on ' || coalesce(v_when, 'the booked time');
    v_route := '/bookings';
  elsif new.membership_id is not null then
    select mb.phone, coalesce(mp.name, ms.name, 'membership') into v_phone, v_name
      from memberships ms join members mb on mb.id = ms.member_id left join membership_plans mp on mp.id = ms.plan_id
     where ms.id = new.membership_id;
    v_what := 'your ' || coalesce(v_name, 'membership') || ' membership';
    v_route := '/my-membership';
  elsif new.coaching_enrollment_id is not null then
    select mb.phone, coalesce(cp.name, 'coaching') into v_phone, v_name
      from coaching_enrollments e join members mb on mb.id = e.member_id left join coaching_programs cp on cp.id = e.program_id
     where e.id = new.coaching_enrollment_id;
    v_what := 'your ' || coalesce(v_name, 'coaching') || ' coaching';
    v_route := '/my-coaching';
  else
    return new;
  end if;

  if v_status = 'paid' then
    perform _notify_players(v_phone, new.facility_id, 'player_payment_success', 'Payment successful',
      'We received ' || v_amt || ' for ' || v_what || coalesce(' at ' || v_venue, '') || '.',
      jsonb_build_object('route', v_route, 'paymentId', new.id), 'player_payment_success:' || new.id);
  else
    perform _notify_players(v_phone, new.facility_id, 'player_payment_failed', 'Payment failed',
      'Your payment of ' || v_amt || ' for ' || v_what || coalesce(' at ' || v_venue, '') || ' did not go through. Please try again, or contact the club.',
      jsonb_build_object('route', v_route, 'paymentId', new.id), 'player_payment_failed:' || new.id);
  end if;
  return new;
end;
$$;
drop trigger if exists payments_notify_player on payments;
create trigger payments_notify_player after insert or update of status on payments
  for each row execute function trg_notify_player_payment();


-- ── an online court-booking payment that failed (there is no payments row for a failed attempt) ──
create or replace function trg_notify_player_order_failed()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text;
  v_court text;
  v_when text;
  v_venue text;
begin
  if new.status::text <> 'FAILED' or (tg_op = 'UPDATE' and old.status::text = 'FAILED') then return new; end if;
  if new.booking_id is null then return new; end if;
  select coalesce(nullif(b.guest_phone, ''), gp.phone, mb.phone), c.name, f.name,
         to_char(b.start_time at time zone coalesce(f.timezone, 'Asia/Kolkata'), 'DD Mon, HH12:MI AM')
    into v_phone, v_court, v_venue, v_when
    from bookings b
    left join guest_players gp on gp.id = b.guest_player_id
    left join members mb on mb.id = b.member_id
    left join courts c on c.id = b.court_id
    left join facilities f on f.id = b.facility_id
   where b.id = new.booking_id;
  perform _notify_players(v_phone, new.facility_id, 'player_payment_failed', 'Payment failed',
    'Your payment of ₹' || round(new.amount_minor / 100.0)::text || ' for your ' || coalesce(v_court, 'court') || ' booking on '
      || coalesce(v_when, 'the booked time') || coalesce(' at ' || v_venue, '') || ' did not go through. Please try again, or contact the club.',
    jsonb_build_object('route', '/bookings', 'bookingId', new.booking_id), 'player_order_failed:' || new.id);
  return new;
end;
$$;
drop trigger if exists payment_orders_notify_player_failed on payment_orders;
create trigger payment_orders_notify_player_failed after insert or update of status on payment_orders
  for each row execute function trg_notify_player_order_failed();


-- ── an AutoPay that stopped (a charge kept failing) ──────────────────────
create or replace function trg_notify_player_membership_autopay_halted()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text;
  v_plan text;
  v_venue text;
begin
  if new.status::text <> 'halted' or old.status::text is not distinct from 'halted' then return new; end if;
  select mb.phone, coalesce(mp.name, ms.name, 'membership'), f.name into v_phone, v_plan, v_venue
    from memberships ms join members mb on mb.id = ms.member_id left join membership_plans mp on mp.id = ms.plan_id
    left join facilities f on f.id = ms.facility_id
   where ms.id = new.membership_id;
  perform _notify_players(v_phone, new.facility_id, 'player_payment_failed', 'AutoPay could not be charged',
    'The payment for your ' || coalesce(v_plan, 'membership') || ' membership' || coalesce(' at ' || v_venue, '')
      || ' failed and AutoPay has stopped. Please pay at the club or set up AutoPay again.',
    jsonb_build_object('route', '/my-membership', 'membershipId', new.membership_id),
    'player_sub_halted:' || new.id || ':' || coalesce(new.charge_count, 0));
  return new;
end;
$$;
drop trigger if exists membership_subscriptions_notify_player_halted on membership_subscriptions;
create trigger membership_subscriptions_notify_player_halted after update of status on membership_subscriptions
  for each row execute function trg_notify_player_membership_autopay_halted();

create or replace function trg_notify_player_coaching_autopay_halted()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text;
  v_prog text;
  v_venue text;
begin
  if new.status <> 'HALTED' or old.status is not distinct from 'HALTED' then return new; end if;
  select mb.phone, coalesce(cp.name, 'coaching'), f.name into v_phone, v_prog, v_venue
    from coaching_enrollments e join members mb on mb.id = e.member_id left join coaching_programs cp on cp.id = e.program_id
    left join facilities f on f.id = e.facility_id
   where e.id = new.enrollment_id;
  perform _notify_players(v_phone, new.facility_id, 'player_payment_failed', 'AutoPay could not be charged',
    'The monthly payment for ' || coalesce(v_prog, 'your coaching') || coalesce(' at ' || v_venue, '')
      || ' failed and AutoPay has stopped. Please pay at the club or set up AutoPay again.',
    jsonb_build_object('route', '/my-coaching', 'enrollmentId', new.enrollment_id),
    'player_coaching_halted:' || new.id || ':' || coalesce(new.charge_count, 0));
  return new;
end;
$$;
drop trigger if exists coaching_billing_notify_player_halted on coaching_enrollment_billing;
create trigger coaching_billing_notify_player_halted after update of status on coaching_enrollment_billing
  for each row execute function trg_notify_player_coaching_autopay_halted();


-- ── the timed ones ───────────────────────────────────────────────────────
-- Safe to call as often as you like (every message has a dedupe key). The notification worker calls it every minute.
create or replace function run_player_notification_jobs()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_bucket integer;
  n_booking integer := 0;
  n_member integer := 0;
  n_coach integer := 0;
begin
  -- 1 · a court booking starts within 30 minutes. A booking made less than 30 minutes before it starts gets no reminder.
  for r in
    select b.id, b.facility_id, f.name as venue, c.name as court, b.start_time,
           to_char(b.start_time at time zone coalesce(f.timezone, 'Asia/Kolkata'), 'HH12:MI AM') as at_time,
           coalesce(nullif(b.guest_phone, ''), gp.phone, mb.phone) as phone
      from bookings b
      join facilities f on f.id = b.facility_id
      left join courts c on c.id = b.court_id
      left join guest_players gp on gp.id = b.guest_player_id
      left join members mb on mb.id = b.member_id
     where b.status::text = 'confirmed'
       and b.start_time > now() and b.start_time <= now() + interval '30 minutes'
       and b.created_at <= b.start_time - interval '30 minutes'
  loop
    perform _notify_players(r.phone, r.facility_id, 'player_booking_reminder', 'Your game starts in 30 minutes',
      coalesce(r.venue, 'Your venue') || coalesce(' · ' || r.court, '') || ' · ' || r.at_time || '. Have a great game!',
      jsonb_build_object('route', '/bookings', 'bookingId', r.id), 'player_booking_reminder:' || r.id);
    n_booking := n_booking + 1;
  end loop;

  -- 2 · a membership's next payment date is 1 to 3 days away: told once at "3 days" and once at "1 day"
  for r in
    select ms.id, ms.facility_id, ms.end_date, mb.phone, f.name as venue,
           coalesce(mp.name, ms.name, 'membership') as plan_name,
           (ms.end_date - (now() at time zone coalesce(f.timezone, 'Asia/Kolkata'))::date) as diff,
           coalesce(ms.auto_renew, false) as autopay,
           coalesce(s.amount_inr, ms.monthly_price_inr, mp.price_inr, 0) as amount
      from memberships ms
      join members mb on mb.id = ms.member_id
      join facilities f on f.id = ms.facility_id
      left join membership_plans mp on mp.id = ms.plan_id
      left join membership_subscriptions s on s.membership_id = ms.id
     where ms.status::text = 'active'
       and ms.end_date - (now() at time zone coalesce(f.timezone, 'Asia/Kolkata'))::date between 1 and 3
  loop
    continue when coalesce(r.amount, 0) <= 0;
    v_bucket := case when r.diff <= 1 then 1 else 3 end;
    perform _notify_players(
      r.phone, r.facility_id, 'player_membership_due',
      case when r.autopay then 'Membership payment coming up' else 'Membership payment due soon' end,
      case when r.autopay
        then '₹' || r.amount::text || ' will be auto-debited on ' || to_char(r.end_date, 'DD Mon YYYY') || ' for your ' || r.plan_name || ' membership' || coalesce(' at ' || r.venue, '') || '.'
        else 'Your ' || r.plan_name || ' membership' || coalesce(' at ' || r.venue, '') || ' is due on ' || to_char(r.end_date, 'DD Mon YYYY') || '. Please pay ₹' || r.amount::text || ' to continue.'
      end,
      jsonb_build_object('route', '/my-membership', 'membershipId', r.id),
      'player_membership_due:' || r.id || ':' || r.end_date::text || ':' || v_bucket);
    n_member := n_member + 1;
  end loop;

  -- 3 · a coaching programme's monthly fee (AutoPay) is 1 to 3 days away
  for r in
    select b.id, b.facility_id, b.current_end, b.amount_minor, mb.phone, f.name as venue, coalesce(cp.name, 'coaching') as prog,
           (b.current_end - (now() at time zone coalesce(f.timezone, 'Asia/Kolkata'))::date) as diff
      from coaching_enrollment_billing b
      join coaching_enrollments e on e.id = b.enrollment_id and e.status = 'ACTIVE'
      join members mb on mb.id = e.member_id
      join facilities f on f.id = b.facility_id
      left join coaching_programs cp on cp.id = e.program_id
     where b.kind = 'SUBSCRIPTION' and b.status in ('AUTHENTICATED', 'ACTIVE', 'PENDING')
       and b.current_end is not null
       and b.current_end - (now() at time zone coalesce(f.timezone, 'Asia/Kolkata'))::date between 1 and 3
  loop
    v_bucket := case when r.diff <= 1 then 1 else 3 end;
    perform _notify_players(
      r.phone, r.facility_id, 'player_coaching_due', 'Coaching payment coming up',
      '₹' || round(r.amount_minor / 100.0)::text || ' will be auto-debited on ' || to_char(r.current_end, 'DD Mon YYYY') || ' for ' || r.prog || coalesce(' at ' || r.venue, '') || '.',
      jsonb_build_object('route', '/my-coaching', 'billingId', r.id),
      'player_coaching_due:' || r.id || ':' || r.current_end::text || ':' || v_bucket);
    n_coach := n_coach + 1;
  end loop;

  return jsonb_build_object('bookingReminders', n_booking, 'membershipReminders', n_member, 'coachingReminders', n_coach);
end;
$$;
revoke all on function run_player_notification_jobs() from public, anon, authenticated;
grant execute on function run_player_notification_jobs() to service_role;


-- ── what the Player app reads ────────────────────────────────────────────
-- Newest first. p_unread_only = true is the bell's popup (read messages are not listed); false also lists the read ones of the last 30 days.
create or replace function list_my_notifications(p_unread_only boolean default true, p_limit integer default 50)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', n.id, 'kind', n.kind, 'title', n.title, 'body', n.body, 'data', n.data,
           'createdAt', n.created_at, 'readAt', n.read_at) order by n.created_at desc), '[]'::jsonb)
    from (
      select * from notifications x
       where x.user_id = auth.uid()
         and (x.read_at is null or (not p_unread_only and x.created_at > now() - interval '30 days'))
       order by x.created_at desc
       limit greatest(1, least(coalesce(p_limit, 50), 200))
    ) n;
$$;
revoke all on function list_my_notifications(boolean, integer) from public, anon;
grant execute on function list_my_notifications(boolean, integer) to authenticated;

create or replace function count_my_unread_notifications()
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::integer from notifications n where n.user_id = auth.uid() and n.read_at is null;
$$;
revoke all on function count_my_unread_notifications() from public, anon;
grant execute on function count_my_unread_notifications() to authenticated;

notify pgrst, 'reload schema';
