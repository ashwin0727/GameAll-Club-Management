-- Player app: sign in with a phone number WITHOUT a one-time code (switchable), and tell a returning number from a new one.
--
-- While text/voice codes are paused, the edge function `player-login` signs a player in from their phone number alone. It needs two
-- things from the database, both for that function only (service role; nobody else can call them):
--
--   player_login_lookup(phone)  does an account already exist for this number, is there a player profile, and what do the clubs
--                               already know (a name, and how many member / guest records carry this number)?
--   player_login_attempts       one row per attempt, so the function can refuse a flood from one address (a number guesser).
--
-- NOTE: without a code, anyone who types a number sees that number's memberships, coaching and bookings. The function's secret
-- PLAYER_OTP_REQUIRED=true switches the code step back on with no app change.

create table if not exists player_login_attempts (
  id bigint generated always as identity primary key,
  ip_hash text not null,
  phone text,
  created_at timestamptz not null default now()
);
create index if not exists player_login_attempts_ip_idx on player_login_attempts (ip_hash, created_at desc);
alter table player_login_attempts enable row level security;  -- no policies: service role only
revoke all on player_login_attempts from anon, authenticated;

create or replace function player_login_lookup(p_phone text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with n as (select normalize_phone(p_phone) as phone),
  account as (
    select u.id from auth.users u, n
     where n.phone is not null and normalize_phone(u.phone) = n.phone
     order by u.created_at limit 1
  ),
  club_people as (
    select m.full_name, m.created_at from members m, n where normalize_phone(m.phone) = n.phone
    union all
    select g.name, g.created_at from guest_players g, n where normalize_phone(g.phone) = n.phone
  )
  select jsonb_build_object(
    'userId', (select id from account),
    'hasPlayer', exists (select 1 from players p, n where p.phone = n.phone),
    'knownName', (select cp.full_name from club_people cp
                   where nullif(trim(cp.full_name), '') is not null and cp.full_name !~ '^unknown-'
                   order by cp.created_at desc limit 1),
    'clubRecords', (select count(*) from club_people)
  );
$$;
revoke all on function player_login_lookup(text) from public, anon, authenticated;
grant execute on function player_login_lookup(text) to service_role;

-- Old attempts are only useful for an hour: forget them whenever a new batch arrives.
create or replace function player_login_record_attempt(p_ip_hash text, p_phone text)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  recent int;
begin
  delete from player_login_attempts where created_at < now() - interval '2 hours';
  insert into player_login_attempts (ip_hash, phone) values (p_ip_hash, p_phone);
  select count(*) into recent from player_login_attempts where ip_hash = p_ip_hash and created_at > now() - interval '1 hour';
  return recent;
end;
$$;
revoke all on function player_login_record_attempt(text, text) from public, anon, authenticated;
grant execute on function player_login_record_attempt(text, text) to service_role;
