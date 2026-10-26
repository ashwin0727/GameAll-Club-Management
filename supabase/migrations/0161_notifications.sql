-- ═══════════════════════════════════════════════════════════════════════════
-- Notifications — in-app (web bell, Flutter list) and phone push.
--
-- One row per person per message in `notifications`. Database triggers write the ones that follow an event (a membership is
-- created or paid, a student is added, a payment fails); `run_notification_jobs()` writes the timed ones (a guest slot
-- starts / ends in 5 minutes, the monthly report reminder, lapsed memberships). The notification-worker edge function runs
-- that job every minute and pushes anything not yet pushed through Firebase Cloud Messaging to the person's devices.
--
-- Who gets a message: the facility owner and every active staff member whose role can open the related page. People can
-- switch categories off in Settings (profiles.notification_prefs: bookings / payments / memberships / reports).
-- ═══════════════════════════════════════════════════════════════════════════

create table if not exists notifications (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  facility_id uuid references facilities (id) on delete cascade,
  kind        text not null,
  title       text not null,
  body        text not null,
  data        jsonb not null default '{}'::jsonb,
  dedupe_key  text,
  created_at  timestamptz not null default now(),
  read_at     timestamptz,
  pushed_at   timestamptz
);
create unique index if not exists notifications_dedupe_idx on notifications (user_id, dedupe_key) where dedupe_key is not null;
create index if not exists notifications_user_idx on notifications (user_id, created_at desc);
create index if not exists notifications_unpushed_idx on notifications (created_at) where pushed_at is null;

alter table notifications enable row level security;
drop policy if exists notifications_select_own on notifications;
create policy notifications_select_own on notifications for select using (user_id = auth.uid());

-- A phone (or browser) that can receive push messages for a user.
create table if not exists device_tokens (
  token      text primary key,
  user_id    uuid not null references auth.users (id) on delete cascade,
  platform   text not null default 'android',
  created_at timestamptz not null default now(),
  last_seen  timestamptz not null default now()
);
create index if not exists device_tokens_user_idx on device_tokens (user_id);
alter table device_tokens enable row level security;   -- no policies: only the functions below and the service role

-- ── Client calls ───────────────────────────────────────────────────────────────
create or replace function mark_notifications_read(p_ids uuid[] default null)
returns integer
language plpgsql security definer set search_path = public
as $$
declare
  n integer;
begin
  update notifications set read_at = now()
   where user_id = auth.uid() and read_at is null and (p_ids is null or id = any (p_ids));
  get diagnostics n = row_count;
  return n;
end;
$$;
grant execute on function mark_notifications_read(uuid[]) to authenticated;

create or replace function register_device_token(p_token text, p_platform text default 'android')
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if auth.uid() is null or nullif(btrim(p_token), '') is null then
    return;
  end if;
  insert into device_tokens (token, user_id, platform) values (p_token, auth.uid(), coalesce(p_platform, 'android'))
  on conflict (token) do update set user_id = excluded.user_id, platform = excluded.platform, last_seen = now();
end;
$$;
grant execute on function register_device_token(text, text) to authenticated;

create or replace function unregister_device_token(p_token text)
returns void
language sql security definer set search_path = public
as $$ delete from device_tokens where token = p_token and user_id = auth.uid(); $$;
grant execute on function unregister_device_token(text) to authenticated;

-- ── Who should hear about it ───────────────────────────────────────────────────
-- The owner, or an active staff member whose role holds the permission, in a facility whose plan includes that page.
create or replace function _user_can(p_facility uuid, p_user uuid, p_key text)
returns boolean
language sql stable security definer set search_path = public
as $$
  select (
    exists (select 1 from facilities f where f.id = p_facility and f.owner_id = p_user)
    or exists (
      select 1 from facility_users fu
      where fu.facility_id = p_facility and fu.user_id = p_user and fu.status = 'ACTIVE'
        and (
          fu.role = 'owner'
          or exists (select 1 from role_permissions rp where rp.role_id = effective_role_id(p_facility, p_user) and rp.permission_key = p_key)
        )
    )
  ) and permission_in_plan(p_facility, p_key);
$$;

-- Settings switch for a kind of message. A switch that was never set counts as on.
create or replace function _notification_enabled(p_user uuid, p_kind text)
returns boolean
language sql stable security definer set search_path = public
as $$
  select coalesce(
    (select (pr.notification_prefs ->> (case
        when p_kind like 'guest_booking%' then 'bookings'
        when p_kind like '%payment%' or p_kind like '%not_renewed%' then 'payments'
        when p_kind = 'monthly_report' then 'reports'
        else 'memberships' end))::boolean
     from profiles pr where pr.id = p_user),
    true);
$$;

create or replace function _notify(
  p_facility uuid, p_permission text, p_kind text, p_title text, p_body text, p_data jsonb, p_dedupe text
) returns void
language plpgsql security definer set search_path = public
as $$
declare
  u uuid;
begin
  for u in
    select f.owner_id from facilities f where f.id = p_facility
    union
    select fu.user_id from facility_users fu where fu.facility_id = p_facility and fu.status = 'ACTIVE'
  loop
    if u is not null and _user_can(p_facility, u, p_permission) and _notification_enabled(u, p_kind) then
      insert into notifications (user_id, facility_id, kind, title, body, data, dedupe_key)
      values (u, p_facility, p_kind, p_title, p_body, coalesce(p_data, '{}'::jsonb), case when p_dedupe is null then null else p_dedupe end)
      on conflict (user_id, dedupe_key) where dedupe_key is not null do nothing;
    end if;
  end loop;
end;
$$;

-- ── 3 · A membership has been created ───────────────────────────────────────────
-- Renewals are saved as a new membership for the same member, so only a member's first one counts as "created".
create or replace function trg_notify_membership_created()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_name text;
begin
  if exists (select 1 from memberships m where m.facility_id = new.facility_id and m.member_id = new.member_id and m.id <> new.id) then
    return new;
  end if;
  select full_name into v_name from members where id = new.member_id;
  perform _notify(new.facility_id, 'MEMBERSHIPS_VIEW', 'membership_created', 'Membership',
    coalesce(v_name, 'Member') || ' has been successfully created',
    jsonb_build_object('membershipId', new.id, 'route', '/memberships'), 'membership_created:' || new.id);
  return new;
end;
$$;
drop trigger if exists memberships_notify_created on memberships;
create trigger memberships_notify_created after insert on memberships for each row execute function trg_notify_membership_created();

-- ── 4 · 6 · 7 · 8 · 9 · payments ─────────────────────────────────────────────────
create or replace function trg_notify_payment()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_member text;
  v_mname text;
  v_renewal boolean;
  v_student text;
  v_program text;
begin
  if new.status::text = 'paid' and (tg_op = 'INSERT' or old.status::text is distinct from 'paid') then
    if new.membership_id is not null then
      select mb.full_name, ms.name,
             exists (select 1 from payments p where p.membership_id = new.membership_id and p.id <> new.id and p.status::text = 'paid')
             or exists (select 1 from memberships o where o.facility_id = ms.facility_id and o.member_id = ms.member_id and o.id <> ms.id and o.created_at < ms.created_at)
        into v_member, v_mname, v_renewal
        from memberships ms left join members mb on mb.id = ms.member_id
        where ms.id = new.membership_id;
      perform _notify(new.facility_id, 'MEMBERSHIPS_VIEW', 'membership_payment_received', 'Membership',
        coalesce(v_member, 'Member') || ' – Payment for ' || coalesce(v_mname, 'membership') || ' received successfully',
        jsonb_build_object('membershipId', new.membership_id, 'route', '/memberships'), 'membership_payment_received:' || new.id);
      if v_renewal then
        perform _notify(new.facility_id, 'MEMBERSHIPS_VIEW', 'membership_renewed', 'Membership',
          coalesce(v_member, 'Member') || ' has been successfully Renewed',
          jsonb_build_object('membershipId', new.membership_id, 'route', '/memberships'), 'membership_renewed:' || new.id);
      end if;
    elsif new.coaching_enrollment_id is not null then
      if exists (select 1 from payments p where p.coaching_enrollment_id = new.coaching_enrollment_id and p.id <> new.id and p.status::text = 'paid') then
        select mb.full_name, cp.name into v_student, v_program
          from coaching_enrollments e left join members mb on mb.id = e.member_id left join coaching_programs cp on cp.id = e.program_id
          where e.id = new.coaching_enrollment_id;
        perform _notify(new.facility_id, 'COACHING_STUDENTS_VIEW', 'coaching_renewed', 'Coaching',
          coalesce(v_student, 'Student') || ' has been Renewed Successfully to the ' || coalesce(v_program, 'program'),
          jsonb_build_object('enrollmentId', new.coaching_enrollment_id, 'route', '/coaching/students'), 'coaching_renewed:' || new.id);
      end if;
    end if;
  elsif new.status::text = 'failed' and (tg_op = 'INSERT' or old.status::text is distinct from 'failed') then
    if new.membership_id is not null then
      select mb.full_name, ms.name into v_member, v_mname
        from memberships ms left join members mb on mb.id = ms.member_id where ms.id = new.membership_id;
      perform _notify(new.facility_id, 'MEMBERSHIPS_VIEW', 'membership_payment_failed', 'Membership',
        coalesce(v_member, 'Member') || ' – Payment for ' || coalesce(v_mname, 'membership') || ' is Failed. Kindly contact for the Payment Updates.',
        jsonb_build_object('membershipId', new.membership_id, 'route', '/memberships'), 'membership_payment_failed:' || new.id);
    elsif new.coaching_enrollment_id is not null then
      select mb.full_name, cp.name into v_student, v_program
        from coaching_enrollments e left join members mb on mb.id = e.member_id left join coaching_programs cp on cp.id = e.program_id
        where e.id = new.coaching_enrollment_id;
      perform _notify(new.facility_id, 'COACHING_STUDENTS_VIEW', 'coaching_payment_failed', 'Coaching',
        coalesce(v_student, 'Student') || ' – Payment for ' || coalesce(v_program, 'program') || ' is Failed. Kindly Contact for the Payment Updates.',
        jsonb_build_object('enrollmentId', new.coaching_enrollment_id, 'route', '/coaching/students'), 'coaching_payment_failed:' || new.id);
    end if;
  end if;
  return new;
end;
$$;
drop trigger if exists payments_notify on payments;
create trigger payments_notify after insert or update of status on payments for each row execute function trg_notify_payment();

-- ── 5 · A student has been added to a program ────────────────────────────────────
create or replace function trg_notify_enrollment_created()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_student text;
  v_program text;
begin
  if new.program_id is null then
    return new;
  end if;
  select mb.full_name into v_student from members mb where mb.id = new.member_id;
  select cp.name into v_program from coaching_programs cp where cp.id = new.program_id;
  perform _notify(new.facility_id, 'COACHING_STUDENTS_VIEW', 'coaching_student_added', 'Coaching',
    coalesce(v_student, 'Student') || ' has been added to the ' || coalesce(v_program, 'program'),
    jsonb_build_object('enrollmentId', new.id, 'route', '/coaching/students'), 'coaching_student_added:' || new.id);
  return new;
end;
$$;
drop trigger if exists coaching_enrollments_notify_created on coaching_enrollments;
create trigger coaching_enrollments_notify_created after insert on coaching_enrollments for each row execute function trg_notify_enrollment_created();

-- ── 8 · 9 · AutoPay stopped (a charge kept failing) ─────────────────────────────────
create or replace function trg_notify_membership_subscription_halted()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_member text;
  v_mname text;
begin
  if new.status::text = 'halted' and old.status::text is distinct from 'halted' then
    select mb.full_name, ms.name into v_member, v_mname
      from memberships ms left join members mb on mb.id = ms.member_id where ms.id = new.membership_id;
    perform _notify(new.facility_id, 'MEMBERSHIPS_VIEW', 'membership_payment_failed', 'Membership',
      coalesce(v_member, 'Member') || ' – Payment for ' || coalesce(v_mname, 'membership') || ' is Failed. Kindly contact for the Payment Updates.',
      jsonb_build_object('membershipId', new.membership_id, 'route', '/memberships'), 'membership_sub_halted:' || new.id || ':' || coalesce(new.charge_count, 0));
  end if;
  return new;
end;
$$;
drop trigger if exists membership_subscriptions_notify_halted on membership_subscriptions;
create trigger membership_subscriptions_notify_halted after update of status on membership_subscriptions for each row execute function trg_notify_membership_subscription_halted();

create or replace function trg_notify_coaching_billing_halted()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_student text;
  v_program text;
begin
  if new.status = 'HALTED' and old.status is distinct from 'HALTED' then
    select mb.full_name, cp.name into v_student, v_program
      from coaching_enrollments e left join members mb on mb.id = e.member_id left join coaching_programs cp on cp.id = e.program_id
      where e.id = new.enrollment_id;
    perform _notify(new.facility_id, 'COACHING_STUDENTS_VIEW', 'coaching_payment_failed', 'Coaching',
      coalesce(v_student, 'Student') || ' – Payment for ' || coalesce(v_program, 'program') || ' is Failed. Kindly Contact for the Payment Updates.',
      jsonb_build_object('enrollmentId', new.enrollment_id, 'route', '/coaching/students'), 'coaching_billing_halted:' || new.id || ':' || coalesce(new.charge_count, 0));
  end if;
  return new;
end;
$$;
drop trigger if exists coaching_billing_notify_halted on coaching_enrollment_billing;
create trigger coaching_billing_notify_halted after update of status on coaching_enrollment_billing for each row execute function trg_notify_coaching_billing_halted();

-- ── 1 · 2 · 8 · 9 · 10 · The timed ones ────────────────────────────────────────────
-- Safe to call as often as you like: every message carries a dedupe key, so a person is told once.
create or replace function run_notification_jobs()
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  r record;
begin
  -- 1 · a guest booking starts in about 5 minutes (the window is wider than the one-minute schedule on purpose)
  for r in
    select b.id, b.facility_id, coalesce(gp.name, b.guest_name, 'Guest') as who
    from bookings b left join guest_players gp on gp.id = b.guest_player_id
    where b.customer_type = 'GUEST' and b.status::text = 'confirmed'
      and b.start_time > now() + interval '3 minutes' and b.start_time <= now() + interval '5 minutes'
  loop
    perform _notify(r.facility_id, 'GUEST_BOOKINGS_VIEW', 'guest_booking_starting', 'Guest Booking',
      r.who || ' is going to Start in 5 minutes', jsonb_build_object('bookingId', r.id, 'route', '/guest-bookings'), 'guest_booking_starting:' || r.id);
  end loop;

  -- 2 · a guest booking ends in about 5 minutes
  for r in
    select b.id, b.facility_id, coalesce(gp.name, b.guest_name, 'Guest') as who
    from bookings b left join guest_players gp on gp.id = b.guest_player_id
    where b.customer_type = 'GUEST' and b.status::text = 'confirmed'
      and b.end_time > now() + interval '3 minutes' and b.end_time <= now() + interval '5 minutes'
  loop
    perform _notify(r.facility_id, 'GUEST_BOOKINGS_VIEW', 'guest_booking_ending', 'Guest Booking',
      r.who || ' is going to End in 5 minutes', jsonb_build_object('bookingId', r.id, 'route', '/guest-bookings'), 'guest_booking_ending:' || r.id);
  end loop;

  -- 10 · the 1st of the month, from 9 AM facility time
  for r in
    select f.id, to_char((now() at time zone coalesce(f.timezone, 'Asia/Kolkata')), 'YYYY-MM') as ym
    from facilities f
    where f.onboarding_step::text = 'COMPLETED'
      and extract(day from (now() at time zone coalesce(f.timezone, 'Asia/Kolkata'))) = 1
      and extract(hour from (now() at time zone coalesce(f.timezone, 'Asia/Kolkata'))) >= 9
  loop
    perform _notify(r.id, 'REPORT_OVERVIEW_VIEW', 'monthly_report', 'Monthly report',
      'Kindly check the report to see how the facility is doing.', jsonb_build_object('route', '/reports'), 'monthly_report:' || r.ym);
  end loop;

  -- 8 · a membership ran out and was not renewed (looks back two days, told once)
  for r in
    select ms.id, ms.facility_id, ms.end_date, mb.full_name as member, ms.name as mname
    from memberships ms left join members mb on mb.id = ms.member_id
    where ms.status::text <> 'cancelled' and ms.end_date < current_date and ms.end_date >= current_date - 2
      and not exists (select 1 from memberships n where n.facility_id = ms.facility_id and n.member_id = ms.member_id and n.id <> ms.id and n.end_date > ms.end_date and n.status::text <> 'cancelled')
      and not exists (select 1 from membership_subscriptions s where s.membership_id = ms.id and s.status::text in ('active', 'authenticated'))
  loop
    perform _notify(r.facility_id, 'MEMBERSHIPS_VIEW', 'membership_not_renewed', 'Membership',
      coalesce(r.member, 'Member') || ' – Payment for ' || coalesce(r.mname, 'membership') || ' is Failed. Kindly contact for the Payment Updates.',
      jsonb_build_object('membershipId', r.id, 'route', '/memberships'), 'membership_not_renewed:' || r.id || ':' || r.end_date);
  end loop;

  -- 9 · a student's program ran out and was not renewed
  for r in
    select e.id, e.facility_id, e.end_date, mb.full_name as student, cp.name as program
    from coaching_enrollments e left join members mb on mb.id = e.member_id left join coaching_programs cp on cp.id = e.program_id
    where e.status = 'ACTIVE' and e.end_date is not null and e.end_date < current_date and e.end_date >= current_date - 2
      and not exists (select 1 from coaching_enrollment_billing b where b.enrollment_id = e.id and b.status in ('ACTIVE', 'AUTHENTICATED', 'PAID'))
      and not exists (select 1 from coaching_enrollments n where n.member_id = e.member_id and n.program_id is not distinct from e.program_id and n.id <> e.id and n.end_date > e.end_date)
  loop
    perform _notify(r.facility_id, 'COACHING_STUDENTS_VIEW', 'coaching_not_renewed', 'Coaching',
      coalesce(r.student, 'Student') || ' – Payment for ' || coalesce(r.program, 'program') || ' is Failed. Kindly Contact for the Payment Updates.',
      jsonb_build_object('enrollmentId', r.id, 'route', '/coaching/students'), 'coaching_not_renewed:' || r.id || ':' || r.end_date);
  end loop;

  return jsonb_build_object('ok', true);
end;
$$;
revoke all on function run_notification_jobs() from public, anon, authenticated;
grant execute on function run_notification_jobs() to service_role;
