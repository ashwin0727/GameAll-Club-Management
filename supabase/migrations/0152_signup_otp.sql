-- Email OTP for account creation.
--
-- A new owner signs up with name + email + password, then must enter a 6-digit code emailed to them (via Resend, from
-- the `signup-otp` edge function) before the account's email is marked confirmed and they can reach onboarding.
--
-- Only a keyed hash of the code is stored (never the code itself), the table is reachable by the service role only
-- (RLS on, no policies, grants revoked), and every row is short-lived.

create table if not exists signup_otps (
  email         text primary key,
  code_hash     text not null,
  expires_at    timestamptz not null,
  attempts      int not null default 0,
  send_count    int not null default 1,
  window_start  timestamptz not null default now(),
  last_sent_at  timestamptz not null default now(),
  created_at    timestamptz not null default now()
);

alter table signup_otps enable row level security;
revoke all on signup_otps from anon, authenticated;

-- Looks up an auth user by email for the edge function (service role only): whether one exists and whether its email
-- is already confirmed. Avoids paging through auth.admin.listUsers.
create or replace function signup_otp_user_status(p_email text)
returns table (user_id uuid, confirmed boolean)
language sql
security definer
set search_path = public, auth
as $$
  select u.id, (u.email_confirmed_at is not null)
  from auth.users u
  where lower(u.email) = lower(p_email)
  limit 1;
$$;

revoke all on function signup_otp_user_status(text) from public, anon, authenticated;
grant execute on function signup_otp_user_status(text) to service_role;
