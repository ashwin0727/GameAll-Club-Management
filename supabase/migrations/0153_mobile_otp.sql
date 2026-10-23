-- Mobile-number OTP (SMS via 2Factor.in).
--
-- Two uses, one edge function (`mobile-otp`):
--   * signup   — a new owner must verify their mobile number (after the email code) before onboarding;
--   * booking  — a guest on the public /book page must verify their mobile before a booking is created.
--
-- As with the email OTP, only a keyed hash of the code is stored and every table here is service-role only, except that
-- an owner can READ their own verified-number row (it drives the "verify your mobile" gate and the Verified badge).

create table if not exists mobile_otps (
  phone         text not null,                 -- 10-digit Indian mobile, digits only
  purpose       text not null check (purpose in ('signup', 'booking')),
  code_hash     text not null,
  expires_at    timestamptz not null,
  attempts      int not null default 0,
  send_count    int not null default 1,
  window_start  timestamptz not null default now(),
  last_sent_at  timestamptz not null default now(),
  primary key (phone, purpose)
);

alter table mobile_otps enable row level security;
revoke all on mobile_otps from anon, authenticated;

-- One row per SMS sent, so a single client can't make us text arbitrary numbers (SMS pumping). IP is stored hashed.
create table if not exists mobile_otp_sends (
  id          bigint generated always as identity primary key,
  ip_hash     text not null,
  phone       text not null,
  created_at  timestamptz not null default now()
);

create index if not exists mobile_otp_sends_ip_idx on mobile_otp_sends (ip_hash, created_at desc);

alter table mobile_otp_sends enable row level security;
revoke all on mobile_otp_sends from anon, authenticated;

-- An owner's verified mobile number. Written only by the edge function (service role).
create table if not exists user_verified_phones (
  user_id      uuid primary key references auth.users (id) on delete cascade,
  phone        text not null,
  verified_at  timestamptz not null default now()
);

alter table user_verified_phones enable row level security;
revoke all on user_verified_phones from anon, authenticated;
grant select on user_verified_phones to authenticated;

drop policy if exists user_verified_phones_select_own on user_verified_phones;
create policy user_verified_phones_select_own on user_verified_phones
  for select to authenticated
  using (user_id = auth.uid());
