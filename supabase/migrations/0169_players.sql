-- Player app: players, phone login, and everything a player sees after signing in.
--
-- A player signs in with a phone number and a one-time code (Supabase phone auth), then gives a name and an email once. That creates
-- a row in `players`, separate from club staff and from the clubs' own people records (members / guest_players).
--
-- Clubs never see the Player app. They take a player's phone number when they create a membership, a coaching enrolment or a guest
-- booking, so the phone number is the link: when a player signs in, every club record with the same phone number is theirs. Nothing is
-- copied or written into the clubs' tables; the link is worked out each time from the verified phone number, so a membership added at
-- a club tomorrow shows up in the app tomorrow, and a number that is not the player's never matches.
--
-- Two functions are public:
--   register_player(name, email)  create / update the signed-in player's profile (the phone comes from the verified login, never from the
--                                 caller, so nobody can register a number they have not proved)
--   get_player_dashboard()        the whole Home page for the signed-in player: active memberships, active coaching, guest bookings,
--                                 the coming week's schedule and today's courts


-- The same person typed as "98765 43210", "+91 98765-43210" or "09876543210": compare the last ten digits.
create or replace function normalize_phone(p text)
returns text
language sql
immutable
as $$
  select case
    when d = '' then null
    when length(d) > 10 then right(d, 10)
    else d
  end
  from (select regexp_replace(coalesce(p, ''), '\D', '', 'g') as d) x;
$$;


-- A player signs up with a phone number and has no email address at that point. The sign-up trigger used to build a profile row for every
-- new login (name = email), which cannot work for a phone login (email is required) and is not wanted for a player anyway: players have
-- their own table below, and profiles stay for club owners and staff.
create or replace function handle_new_user() returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if nullif(trim(coalesce(new.email, '')), '') is null then
    return new;
  end if;
  insert into public.profiles (id, full_name, email, role)
  values (
    new.id,
    coalesce(nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''), new.email),
    new.email,
    case when new.raw_user_meta_data ->> 'account_type' = 'owner' then 'admin'::role
         else 'member'::role end
  )
  on conflict (id) do nothing;
  return new;
end;
$$;


create table if not exists players (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text not null check (trim(full_name) <> ''),
  phone text not null check (length(phone) >= 7),   -- normalized (see normalize_phone)
  email text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists players_phone_idx on players (phone);

alter table players enable row level security;
drop policy if exists "players_select_own" on players;
create policy "players_select_own" on players for select using (id = auth.uid());
drop policy if exists "players_update_own" on players;
create policy "players_update_own" on players for update using (id = auth.uid()) with check (id = auth.uid());

drop trigger if exists players_set_updated_at on players;
create trigger players_set_updated_at before update on players for each row execute function set_updated_at();


-- ─────────────────────────────────────────────────────────────────────────
-- register_player: first sign-in (or editing the profile later).
-- ─────────────────────────────────────────────────────────────────────────
create or replace function register_player(p_full_name text, p_email text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  verified_phone text;
  clean_phone text;
  clean_email text := nullif(trim(coalesce(p_email, '')), '');
begin
  if uid is null then
    raise exception 'Please sign in first.' using errcode = '28000';
  end if;
  if trim(coalesce(p_full_name, '')) = '' then
    raise exception 'Please enter your name.' using errcode = '23514';
  end if;
  if clean_email is not null and clean_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Please enter a valid email address.' using errcode = '23514';
  end if;

  -- the phone number that was verified by the one-time code
  select u.phone into verified_phone from auth.users u where u.id = uid;
  clean_phone := normalize_phone(verified_phone);
  if clean_phone is null or length(clean_phone) < 7 then
    raise exception 'Sign in with your phone number to create a player profile.' using errcode = '28000';
  end if;

  -- one player per phone number
  if exists (select 1 from players p where p.phone = clean_phone and p.id <> uid) then
    raise exception 'This phone number already belongs to another player.' using errcode = '23505';
  end if;

  insert into players (id, full_name, phone, email)
  values (uid, trim(p_full_name), clean_phone, clean_email)
  on conflict (id) do update
    set full_name = excluded.full_name,
        email = excluded.email,
        phone = excluded.phone;

  return (select jsonb_build_object('id', p.id, 'fullName', p.full_name, 'phone', p.phone, 'email', p.email)
            from players p where p.id = uid);
end;
$$;
revoke all on function register_player(text, text) from public, anon;
grant execute on function register_player(text, text) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- get_my_player: who am I? null until the profile has been created (the app then asks for the name and email).
-- ─────────────────────────────────────────────────────────────────────────
create or replace function get_my_player()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object('id', p.id, 'fullName', p.full_name, 'phone', p.phone, 'email', p.email)
    from players p
   where p.id = auth.uid();
$$;
revoke all on function get_my_player() from public, anon;
grant execute on function get_my_player() to authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- get_player_dashboard: the Home page of a signed-in player.
--
-- Returns (all for the caller only):
--   fullName, phone, unreadNotifications, hasActiveMembership, hasActiveCoaching, hasBookingHistory, upcomingBookings
--       the same fields get_my_player_home() gives (the app's existing Home model)
--   memberships     ACTIVE memberships (not expired), every club: plan, club, batch name, days and time
--   coaching        ACTIVE coaching enrolments that have not ended: programme, club, coach, next session
--   guestBookings   { count, next } confirmed guest bookings that have not finished
--   schedule        the next 7 days across memberships, coaching and bookings, soonest first (up to 12)
--   courtsToday     today's items from the schedule
-- ─────────────────────────────────────────────────────────────────────────
create or replace function get_player_dashboard()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with me as (select auth.uid() as uid),
  pl as (select p.id, p.full_name, p.phone, p.email from players p, me where p.id = me.uid),
  my_members as (
    select m.id from members m, pl where normalize_phone(m.phone) = pl.phone
    union
    select m.id from members m, me where m.user_id = me.uid
  ),
  my_guests as (
    select g.id from guest_players g, pl where normalize_phone(g.phone) = pl.phone
  ),
  my_people as (
    select id from my_members
    union
    select uid from me where uid is not null
  ),
  -- bookings: made for me as a member, or as a guest (by guest record or by the phone typed on the booking)
  my_bookings as (
    select b.id, b.start_time, b.end_time, b.status::text as status, b.customer_type,
           f.name as venue_name, f.logo_url as venue_logo, c.name as court_name, s.name as sport_name
      from bookings b
      join facilities f on f.id = b.facility_id
      left join courts c on c.id = b.court_id
      left join sports s on s.id = c.sport_id
     where b.member_id in (select id from my_people)
        or b.guest_player_id in (select id from my_guests)
        or (b.customer_type = 'GUEST' and normalize_phone(b.guest_phone) = (select phone from pl))
  ),
  upcoming as (
    select * from my_bookings where status = 'confirmed' and end_time > now() order by start_time limit 5
  ),
  active_memberships as (
    select ms.id, coalesce(nullif(trim(ms.name), ''), mp.name, 'Membership') as plan_name, f.name as venue_name, ms.start_date, ms.end_date,
           bt.batch_name, bt.days_of_week, bt.start_time, bt.end_time, bt.court_name
      from memberships ms
      left join membership_plans mp on mp.id = ms.plan_id
      join facilities f on f.id = ms.facility_id
      left join lateral (
        select mb.name as batch_name, mb.days_of_week, mb.start_time, mb.end_time, c.name as court_name
          from membership_batch_members bm
          join membership_batches mb on mb.id = bm.batch_id and mb.is_active
          left join courts c on c.id = mb.court_id
         where bm.member_id = ms.member_id
           and (bm.membership_id = ms.id or bm.membership_id is null)
         order by (bm.membership_id = ms.id) desc, bm.created_at desc
         limit 1
      ) bt on true
     where ms.member_id in (select id from my_people)
       and ms.status::text = 'active' and ms.end_date >= current_date
  ),
  active_coaching as (
    select e.id, cp.name as program_name, f.name as venue_name, e.end_date,
           (select pr.full_name from coaches co join profiles pr on pr.id = co.user_id where co.id = e.coach_id) as coach_name,
           (select min(cs.start_at)
              from coaching_session_students st
              join coaching_sessions cs on cs.id = st.session_id
             where st.enrollment_id = e.id and st.status = 'ENROLLED'
               and cs.status in ('SCHEDULED', 'CONFIRMED', 'IN_PROGRESS') and cs.end_at > now()) as next_session,
           (select cs.end_at
              from coaching_session_students st
              join coaching_sessions cs on cs.id = st.session_id
             where st.enrollment_id = e.id and st.status = 'ENROLLED'
               and cs.status in ('SCHEDULED', 'CONFIRMED', 'IN_PROGRESS') and cs.end_at > now()
             order by cs.start_at limit 1) as next_session_end
      from coaching_enrollments e
      join coaching_programs cp on cp.id = e.program_id
      join facilities f on f.id = e.facility_id
     where e.member_id in (select id from my_people)
       and e.status = 'ACTIVE' and (e.end_date is null or e.end_date >= current_date)
  ),
  items as (
    select 'guest' as kind, case when mb.customer_type = 'GUEST' then 'Guest Booking' else 'Court Booking' end as title,
           mb.venue_name, mb.court_name, mb.start_time as start_at, mb.end_time as end_at, 'confirmed' as status
      from my_bookings mb
     where mb.status = 'confirmed' and mb.end_time > now() and mb.start_time < now() + interval '8 days'
    union all
    select 'membership', coalesce(mb.name, 'Membership'), f.name, c.name,
           (s.session_date + s.start_time) at time zone coalesce(f.timezone, 'Asia/Kolkata'),
           (s.session_date + s.end_time) at time zone coalesce(f.timezone, 'Asia/Kolkata'), 'confirmed'
      from membership_sessions s
      join membership_batches mb on mb.id = s.batch_id
      join membership_batch_members bm on bm.batch_id = s.batch_id and bm.member_id in (select id from my_people)
      join facilities f on f.id = s.facility_id
      left join courts c on c.id = s.court_id
     where s.session_date >= current_date and s.session_date < current_date + 8
       and ((s.session_date + s.end_time) at time zone coalesce(f.timezone, 'Asia/Kolkata')) > now()
    union all
    select 'coaching', cp.name, f.name, c.name, cs.start_at, cs.end_at, lower(cs.status)
      from coaching_session_students st
      join coaching_enrollments e on e.id = st.enrollment_id and e.member_id in (select id from my_people)
      join coaching_sessions cs on cs.id = st.session_id
      join coaching_programs cp on cp.id = cs.program_id
      join facilities f on f.id = cs.facility_id
      left join courts c on c.id = cs.court_id
     where st.status = 'ENROLLED' and cs.status in ('SCHEDULED', 'CONFIRMED', 'IN_PROGRESS')
       and cs.end_at > now() and cs.start_at < now() + interval '8 days'
  ),
  schedule as (select * from items order by start_at limit 12)
  select jsonb_build_object(
    'fullName', (select full_name from pl),
    'phone', (select phone from pl),
    'email', (select email from pl),
    'unreadNotifications', (select count(*) from notifications n, me where n.user_id = me.uid and n.read_at is null),
    'hasActiveMembership', exists (select 1 from active_memberships),
    'hasActiveCoaching', exists (select 1 from active_coaching),
    'hasBookingHistory', exists (select 1 from my_bookings),
    'upcomingBookings', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', u.id, 'startTime', u.start_time, 'endTime', u.end_time, 'status', u.status,
        'venueName', u.venue_name, 'venueLogo', u.venue_logo, 'courtName', u.court_name, 'sportName', u.sport_name
      ) order by u.start_time) from upcoming u), '[]'::jsonb),
    'memberships', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', a.id, 'planName', a.plan_name, 'venueName', a.venue_name, 'endDate', a.end_date,
        'batchName', a.batch_name, 'daysOfWeek', to_jsonb(a.days_of_week),
        'startTime', to_char(a.start_time, 'HH24:MI'), 'endTime', to_char(a.end_time, 'HH24:MI'), 'courtName', a.court_name
      ) order by a.end_date) from active_memberships a), '[]'::jsonb),
    'coaching', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', k.id, 'programName', k.program_name, 'venueName', k.venue_name, 'coachName', k.coach_name,
        'endDate', k.end_date, 'nextSession', k.next_session, 'nextSessionEnd', k.next_session_end
      ) order by k.next_session nulls last) from active_coaching k), '[]'::jsonb),
    'guestBookings', jsonb_build_object(
      'count', (select count(*) from my_bookings g where g.customer_type = 'GUEST' and g.status = 'confirmed' and g.end_time > now()),
      'next', (select jsonb_build_object('startTime', g.start_time, 'endTime', g.end_time, 'venueName', g.venue_name, 'courtName', g.court_name)
                 from my_bookings g
                where g.customer_type = 'GUEST' and g.status = 'confirmed' and g.end_time > now()
                order by g.start_time limit 1)),
    'schedule', coalesce((
      select jsonb_agg(jsonb_build_object(
        'kind', i.kind, 'title', i.title, 'venueName', i.venue_name, 'courtName', i.court_name,
        'startTime', i.start_at, 'endTime', i.end_at, 'status', i.status
      ) order by i.start_at) from schedule i), '[]'::jsonb),
    'courtsToday', coalesce((
      select jsonb_agg(jsonb_build_object(
        'kind', i.kind, 'title', i.title, 'venueName', i.venue_name, 'courtName', i.court_name,
        'startTime', i.start_at, 'endTime', i.end_at, 'status', i.status
      ) order by i.start_at)
        from schedule i
       where i.court_name is not null and (i.start_at at time zone 'Asia/Kolkata')::date = (now() at time zone 'Asia/Kolkata')::date), '[]'::jsonb)
  );
$$;
revoke all on function get_player_dashboard() from public, anon;
grant execute on function get_player_dashboard() to authenticated;
