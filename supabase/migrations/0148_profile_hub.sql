-- ═══════════════════════════════════════════════════════════════════════════
-- Profile hub: the owner's own page (plan, payout details, support, settings).
--
--   facility_subscriptions   GameAll's own plan for a facility. GameAll earns a
--                            membership fee, not a commission, so this is what a
--                            facility owner sees under "Active Membership Plan".
--                            Read-only to facility members; GameAll staff write it
--                            with the service role / SQL editor.
--   facility_payout_methods  Where the facility receives what it collects (bank
--                            account or UPI). Owners only.
--   support_tickets          Help & Support requests raised from the app.
--   profiles.notification_prefs  Per-user notification switches (Settings).
-- ═══════════════════════════════════════════════════════════════════════════

-- ─── GameAll plan for a facility ───────────────────────────────────────────
create table if not exists facility_subscriptions (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null unique references facilities (id) on delete cascade,
  plan_name text not null,
  price_minor integer not null check (price_minor >= 0),
  currency text not null default 'INR',
  billing_interval text not null default 'month' check (billing_interval in ('month', 'quarter', 'year')),
  status text not null default 'active' check (status in ('active', 'cancelled')),
  -- The last day the plan covers. Past this date the plan reads as inactive.
  valid_till date not null,
  features text[] not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table facility_subscriptions enable row level security;

drop policy if exists "facility_subscriptions_select_members" on facility_subscriptions;
create policy "facility_subscriptions_select_members" on facility_subscriptions for select
  using (is_facility_member(facility_id));

-- ─── Payout methods ────────────────────────────────────────────────────────
create table if not exists facility_payout_methods (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references facilities (id) on delete cascade,
  method_type text not null check (method_type in ('BANK', 'UPI')),
  account_holder_name text not null,
  bank_name text,
  account_number text,
  ifsc text,
  upi_id text,
  is_primary boolean not null default false,
  -- GameAll checks each method by hand before money is sent to it. Owners cannot set these: the trigger below
  -- forces PENDING and rejects any change to them from a signed-in user.
  verification_status text not null default 'PENDING' check (verification_status in ('PENDING', 'VERIFIED', 'REJECTED')),
  verified_at timestamptz,
  verification_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint payout_bank_fields check (
    method_type <> 'BANK' or (account_number is not null and ifsc is not null and bank_name is not null)
  ),
  constraint payout_upi_fields check (method_type <> 'UPI' or upi_id is not null)
);
create index if not exists facility_payout_methods_facility_idx on facility_payout_methods (facility_id);
-- One primary method per facility.
create unique index if not exists facility_payout_methods_one_primary
  on facility_payout_methods (facility_id) where is_primary;

alter table facility_payout_methods enable row level security;

drop policy if exists "payout_methods_owner_all" on facility_payout_methods;
create policy "payout_methods_owner_all" on facility_payout_methods for all
  using (has_facility_role(facility_id, array['owner']::facility_role[]))
  with check (has_facility_role(facility_id, array['owner']::facility_role[]));

-- Verification belongs to GameAll. A signed-in owner (auth.uid() is set) can add and edit a method, but it always
-- starts PENDING, and changing the account it points at sends it back to PENDING. GameAll verifies it from the SQL
-- editor / service role, where auth.uid() is null and this trigger steps aside.
create or replace function guard_payout_method_verification()
returns trigger
language plpgsql
as $$
begin
  if auth.uid() is null then
    if new.verification_status = 'VERIFIED' and new.verified_at is null then
      new.verified_at := now();
    end if;
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.verification_status := 'PENDING';
    new.verified_at := null;
    new.verification_note := null;
  else
    if new.verification_status is distinct from old.verification_status
       or new.verified_at is distinct from old.verified_at
       or new.verification_note is distinct from old.verification_note then
      raise exception 'Verification is managed by GameAll' using errcode = '42501';
    end if;
    if new.method_type is distinct from old.method_type
       or new.account_holder_name is distinct from old.account_holder_name
       or new.bank_name is distinct from old.bank_name
       or new.account_number is distinct from old.account_number
       or new.ifsc is distinct from old.ifsc
       or new.upi_id is distinct from old.upi_id then
      new.verification_status := 'PENDING';
      new.verified_at := null;
      new.verification_note := null;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists payout_method_verification_guard on facility_payout_methods;
create trigger payout_method_verification_guard
  before insert or update on facility_payout_methods
  for each row execute function guard_payout_method_verification();

-- Making a method primary demotes the others in the same statement, so the
-- partial unique index above is never violated mid-update.
create or replace function set_primary_payout_method(p_method_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_facility uuid;
begin
  select facility_id into v_facility from facility_payout_methods where id = p_method_id;
  if v_facility is null then
    raise exception 'Payout method not found' using errcode = 'P0002';
  end if;
  if not has_facility_role(v_facility, array['owner']::facility_role[]) then
    raise exception 'Not authorized' using errcode = '42501';
  end if;
  update facility_payout_methods set is_primary = false, updated_at = now()
   where facility_id = v_facility and is_primary and id <> p_method_id;
  update facility_payout_methods set is_primary = true, updated_at = now() where id = p_method_id;
end;
$$;
revoke all on function set_primary_payout_method(uuid) from public;
grant execute on function set_primary_payout_method(uuid) to authenticated;

-- ─── Support tickets ───────────────────────────────────────────────────────
create table if not exists support_tickets (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references facilities (id) on delete cascade,
  created_by uuid not null references profiles (id) on delete cascade default auth.uid(),
  category text not null default 'GENERAL'
    check (category in ('GENERAL', 'BILLING', 'BOOKINGS', 'PAYMENTS', 'TECHNICAL', 'OTHER')),
  subject text not null check (char_length(btrim(subject)) between 3 and 140),
  message text not null check (char_length(btrim(message)) between 10 and 4000),
  status text not null default 'OPEN' check (status in ('OPEN', 'IN_PROGRESS', 'RESOLVED', 'CLOSED')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists support_tickets_facility_idx on support_tickets (facility_id, created_at desc);

alter table support_tickets enable row level security;

drop policy if exists "support_tickets_select_members" on support_tickets;
create policy "support_tickets_select_members" on support_tickets for select
  using (is_facility_member(facility_id));

drop policy if exists "support_tickets_insert_members" on support_tickets;
create policy "support_tickets_insert_members" on support_tickets for insert
  with check (is_facility_member(facility_id) and created_by = auth.uid());

-- ─── Notification preferences ──────────────────────────────────────────────
alter table profiles add column if not exists notification_prefs jsonb not null default '{}'::jsonb;
