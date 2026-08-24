-- ═══════════════════════════════════════════════════════════════════════════
-- Facility Members — architecture fix.
--
-- Root cause of the bug this migration fixes: 0001_init.sql modeled a
-- "member" as a row in `profiles` (i.e. a real Supabase Auth account), and
-- 0012_memberships.sql's /api/members route created one via
-- `admin.auth.admin.createUser()` for every new member. That conflated two
-- unrelated concepts: "a person who can log into GameAll" (owner/manager/
-- staff — a real auth account) and "a facility's customer/player record"
-- (a member — no login, no password, no auth account).
--
-- This migration introduces `members` as a real, facility-scoped customer
-- table with no required auth account, and repoints memberships/payments/
-- bookings at it instead of at `profiles`. It also backfills existing rows
-- so no history is lost:
--
--   - Every profile with role='member' that is actually referenced by a
--     membership/payment/booking gets one `members` row per facility it
--     appears in, with `user_id` set to that profile's id — preserving the
--     fact that this particular member *did* get an (unwanted) auth account
--     under the old flow, without deleting that auth.users row and without
--     losing the membership/payment/booking history attached to it.
--   - memberships.member_id / payments.member_id / bookings.member_id are
--     rewritten from the old profile id to the new members.id, then their
--     foreign key is repointed from profiles(id) to members(id).
--
-- `members.user_id` stays nullable and unused by normal member creation —
-- it exists only for a future, explicit "Invite to GameAll" flow that links
-- a member to a real login. No such flow is implemented here.
-- ═══════════════════════════════════════════════════════════════════════════

create table members (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references facilities (id) on delete cascade,
  full_name text not null,
  phone text not null,
  email text,
  date_of_birth date,
  gender text,
  notes text,
  status text not null default 'ACTIVE' check (status in ('ACTIVE', 'INACTIVE')),
  -- Optional future link to a real GameAll login — never set by normal
  -- member creation, only by an explicit future "Invite to GameAll" flow.
  user_id uuid references profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (facility_id, phone)
);
create index members_facility_id_idx on members (facility_id);
create index members_user_id_idx on members (user_id) where user_id is not null;

alter table members enable row level security;

create policy "members_select_members" on members for select
  using (is_facility_member(facility_id));
create policy "members_write_managers" on members for all
  using (has_facility_role(facility_id, array['owner', 'manager', 'staff']::facility_role[]))
  with check (has_facility_role(facility_id, array['owner', 'manager', 'staff']::facility_role[]));

-- ─────────────────────────────────────────────────────────────────────────
-- Backfill: one members row per (facility, legacy member profile) pair
-- actually referenced by existing data, preserving the profile id as
-- user_id so the historical (if unwanted) auth linkage is not silently
-- destroyed.
-- ─────────────────────────────────────────────────────────────────────────
insert into members (facility_id, full_name, phone, email, user_id, created_at)
select distinct
  x.facility_id,
  coalesce(nullif(trim(p.full_name), ''), p.email),
  -- members.phone is not-null; legacy profiles created via the old signup
  -- flow may have no phone captured, so fall back to a clearly-synthetic
  -- placeholder rather than leaving a real facility member unbookable.
  coalesce(nullif(trim(p.phone), ''), 'unknown-' || substr(p.id::text, 1, 8)),
  p.email,
  p.id,
  now()
from (
  select facility_id, member_id from memberships
  union
  select facility_id, member_id from payments
  union
  select facility_id, member_id from bookings where member_id is not null
) x
join profiles p on p.id = x.member_id
on conflict (facility_id, phone) do nothing;

-- Backfill safety net: if two legacy profiles collided on the synthetic
-- phone fallback above (extremely unlikely — 8 hex chars of a uuid), retry
-- any still-unmapped pair with the full id so nothing is silently dropped.
insert into members (facility_id, full_name, phone, email, user_id, created_at)
select distinct
  x.facility_id,
  coalesce(nullif(trim(p.full_name), ''), p.email),
  'unknown-' || p.id::text,
  p.email,
  p.id,
  now()
from (
  select facility_id, member_id from memberships
  union
  select facility_id, member_id from payments
  union
  select facility_id, member_id from bookings where member_id is not null
) x
join profiles p on p.id = x.member_id
where not exists (
  select 1 from members m where m.facility_id = x.facility_id and m.user_id = x.member_id
)
on conflict (facility_id, phone) do nothing;

-- ─────────────────────────────────────────────────────────────────────────
-- Repoint memberships/payments/bookings at the new members table.
--
-- The old `member_id = auth.uid()` self-access policies are dropped BEFORE
-- their column is touched (Postgres refuses to drop a column that a policy
-- still depends on) and recreated AFTER the rename, pointed through
-- members.user_id instead — which stays correct today (nothing sets
-- user_id yet, so these clauses are simply inert) and becomes meaningful
-- again the moment a future "Invite to GameAll" flow links an account.
-- ─────────────────────────────────────────────────────────────────────────
drop policy "memberships_select_own_or_staff" on memberships;
alter table memberships add column member_ref_id uuid;
update memberships mem
set member_ref_id = m.id
from members m
where m.facility_id = mem.facility_id and m.user_id = mem.member_id;
alter table memberships drop constraint memberships_member_id_fkey;
alter table memberships drop column member_id;
alter table memberships rename column member_ref_id to member_id;
alter table memberships alter column member_id set not null;
alter table memberships add constraint memberships_member_id_fkey
  foreign key (member_id) references members (id) on delete cascade;
create index memberships_member_id_idx on memberships (member_id);
create policy "memberships_select_own_or_staff" on memberships for select
  using (
    is_facility_member(facility_id)
    or exists (select 1 from members m where m.id = memberships.member_id and m.user_id = auth.uid())
  );

drop policy "payments_select_own_or_staff" on payments;
alter table payments add column member_ref_id uuid;
update payments pay
set member_ref_id = m.id
from members m
where m.facility_id = pay.facility_id and m.user_id = pay.member_id;
alter table payments drop constraint payments_member_id_fkey;
alter table payments drop column member_id;
alter table payments rename column member_ref_id to member_id;
alter table payments alter column member_id set not null;
alter table payments add constraint payments_member_id_fkey
  foreign key (member_id) references members (id) on delete cascade;
create index payments_member_id_idx on payments (member_id);
create policy "payments_select_own_or_staff" on payments for select
  using (
    is_facility_member(facility_id)
    or exists (select 1 from members m where m.id = payments.member_id and m.user_id = auth.uid())
  );

drop policy "bookings_select_own_or_staff" on bookings;
drop policy "bookings_insert_own_or_staff" on bookings;
drop policy "bookings_update_own_or_staff" on bookings;
alter table bookings add column member_ref_id uuid;
update bookings b
set member_ref_id = m.id
from members m
where m.facility_id = b.facility_id and m.user_id = b.member_id and b.member_id is not null;
alter table bookings drop constraint bookings_member_id_fkey;
-- Dropping member_id also drops bookings_customer_check (0007), since it's
-- a check constraint defined against that column — re-added verbatim below.
alter table bookings drop column member_id;
alter table bookings rename column member_ref_id to member_id;
alter table bookings add constraint bookings_member_id_fkey
  foreign key (member_id) references members (id) on delete cascade;
create index bookings_member_id_idx on bookings (member_id);
alter table bookings add constraint bookings_customer_check check (
  (customer_type = 'MEMBER' and member_id is not null and guest_name is null and guest_phone is null)
  or (customer_type = 'GUEST' and member_id is null and guest_name is not null and trim(guest_name) <> '')
);
create policy "bookings_select_own_or_staff" on bookings for select
  using (
    is_facility_member(facility_id)
    or exists (select 1 from members m where m.id = bookings.member_id and m.user_id = auth.uid())
  );
create policy "bookings_insert_own_or_staff" on bookings for insert
  with check (
    has_facility_role(facility_id, array['owner', 'manager', 'staff']::facility_role[])
    or exists (select 1 from members m where m.id = bookings.member_id and m.user_id = auth.uid())
  );
create policy "bookings_update_own_or_staff" on bookings for update
  using (
    has_facility_role(facility_id, array['owner', 'manager', 'staff']::facility_role[])
    or exists (select 1 from members m where m.id = bookings.member_id and m.user_id = auth.uid())
  );

-- ─────────────────────────────────────────────────────────────────────────
-- create_member / update_member: the write path for a facility customer
-- record — mirrors find_or_create_guest/update_guest exactly, except
-- duplicate phone numbers are a hard error (unique constraint, 23505)
-- rather than a silent merge, matching the "Member already exists" UX the
-- app surfaces (the caller does its own pre-check by phone to offer "View
-- Existing Member" before even attempting the insert).
-- ─────────────────────────────────────────────────────────────────────────
create function create_member(
  p_facility_id uuid,
  p_full_name text,
  p_phone text,
  p_email text default null,
  p_date_of_birth date default null,
  p_gender text default null,
  p_notes text default null
) returns members
language plpgsql
as $$
declare
  result members;
begin
  if trim(coalesce(p_full_name, '')) = '' then
    raise exception 'Member name is required.' using errcode = '23514';
  end if;
  if trim(coalesce(p_phone, '')) = '' then
    raise exception 'Member mobile number is required.' using errcode = '23514';
  end if;

  insert into members (facility_id, full_name, phone, email, date_of_birth, gender, notes)
  values (p_facility_id, trim(p_full_name), trim(p_phone), p_email, p_date_of_birth, p_gender, p_notes)
  returning * into result;

  return result;
end;
$$;

grant execute on function create_member(uuid, text, text, text, date, text, text) to authenticated;

create function update_member(
  p_member_id uuid,
  p_full_name text,
  p_phone text,
  p_email text,
  p_date_of_birth date,
  p_gender text,
  p_notes text,
  p_status text default null
) returns members
language plpgsql
as $$
declare
  result members;
begin
  if trim(coalesce(p_full_name, '')) = '' then
    raise exception 'Member name is required.' using errcode = '23514';
  end if;
  if trim(coalesce(p_phone, '')) = '' then
    raise exception 'Member mobile number is required.' using errcode = '23514';
  end if;

  update members
  set full_name = trim(p_full_name),
      phone = trim(p_phone),
      email = p_email,
      date_of_birth = p_date_of_birth,
      gender = p_gender,
      notes = p_notes,
      status = coalesce(p_status, status),
      updated_at = now()
  where id = p_member_id
  returning * into result;

  if result.id is null then
    raise exception 'Member not found' using errcode = 'P0002';
  end if;

  return result;
end;
$$;

grant execute on function update_member(uuid, text, text, text, date, text, text, text) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- search_facility_members: now driven by `members` (every facility
-- customer, membership or not — a member can exist without ever being
-- assigned a plan) with the member's most recent membership left-joined in.
-- create_membership/cancel_membership/get_member_stats need no body change,
-- since they were already driven purely by the member_id column (now a
-- members.id, transparently).
-- ─────────────────────────────────────────────────────────────────────────
create or replace function search_facility_members(
  p_facility_id uuid,
  p_query text default null,
  p_limit integer default 50,
  p_offset integer default 0
) returns table (
  member_id uuid,
  full_name text,
  phone text,
  email text,
  membership_id uuid,
  plan_id uuid,
  plan_name text,
  start_date date,
  end_date date,
  status membership_status
)
language sql
stable
as $$
  with latest as (
    select distinct on (member_id) *
    from memberships
    where facility_id = p_facility_id
    order by member_id, end_date desc
  )
  select m.id, m.full_name, m.phone, m.email,
         l.id, l.plan_id, mp.name, l.start_date, l.end_date, l.status
  from members m
  left join latest l on l.member_id = m.id
  left join membership_plans mp on mp.id = l.plan_id
  where m.facility_id = p_facility_id
    and (
      p_query is null or trim(p_query) = ''
      or m.full_name ilike '%' || p_query || '%'
      or m.phone ilike '%' || p_query || '%'
      or m.email ilike '%' || p_query || '%'
    )
  order by l.end_date desc nulls last, m.full_name
  limit p_limit offset p_offset;
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- search_members: powers the Booking → Member search
-- (a member doesn't need an active membership to be searchable/bookable —
-- membership only gates the Members list's status filter, not booking
-- eligibility). Facility-scoped, unlike the old profiles-based search this
-- replaces (which searched every member on the platform).
-- ─────────────────────────────────────────────────────────────────────────
create function search_members(p_facility_id uuid, p_query text) returns table (
  id uuid,
  full_name text,
  phone text,
  email text
)
language sql
stable
as $$
  select id, full_name, phone, email
  from members
  where facility_id = p_facility_id
    and status = 'ACTIVE'
    and (full_name ilike '%' || p_query || '%' or phone ilike '%' || p_query || '%' or email ilike '%' || p_query || '%')
  order by full_name
  limit 10;
$$;

grant execute on function search_members(uuid, text) to authenticated;