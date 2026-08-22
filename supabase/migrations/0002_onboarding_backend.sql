-- ═══════════════════════════════════════════════════════════════════════════
-- Onboarding backend: Facility Details, Sports Setup, Courts & Turfs Setup
--
-- Extends the tables 0001_init.sql already created for these three completed
-- frontend steps. No app code writes to facilities/facility_sports/courts
-- yet (they were mock/localStorage-backed), so every change here is safe to
-- apply against an empty table — no backfill migration is required.
--
-- Explicitly out of scope: operating hours, pricing, bookings business logic.
-- The `bookings`/`memberships`/`payments`/`inventory_*` tables from 0001 are
-- untouched.
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────
-- Enums
-- ─────────────────────────────────────────────────────────────────────────
-- Mirrors the frontend's FacilityType union exactly (src/features/onboarding/types.ts):
-- five single-sport facility types plus MULTI_SPORT and OTHER (custom, freeform).
create type facility_type as enum (
  'BADMINTON', 'PICKLEBALL', 'CRICKET', 'FOOTBALL', 'TENNIS', 'MULTI_SPORT', 'OTHER'
);

-- Shared ACTIVE/INACTIVE toggle, reused by facilities and courts (playing areas).
create type entity_status as enum ('ACTIVE', 'INACTIVE');

create type onboarding_step as enum (
  'FACILITY_DETAILS', 'SPORTS', 'COURTS', 'OPERATING_HOURS', 'PRICING', 'COMPLETED'
);

create type area_type as enum ('INDOOR', 'OUTDOOR');

-- ─────────────────────────────────────────────────────────────────────────
-- updated_at trigger, shared by every table below
-- ─────────────────────────────────────────────────────────────────────────
create function set_updated_at() returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- facilities: grow to match the Facility Details page
-- ─────────────────────────────────────────────────────────────────────────
alter table facilities
  add column facility_type facility_type not null default 'MULTI_SPORT',
  add column custom_facility_type text,
  add column business_email text not null default '',
  add column business_phone text not null default '',
  add column address_line_1 text not null default '',
  add column address_line_2 text,
  add column area text not null default '',
  add column state text not null default '',
  add column country text,
  add column postal_code text not null default '',
  add column latitude numeric,
  add column longitude numeric,
  add column logo_url text,
  add column description text,
  add column status entity_status not null default 'ACTIVE',
  add column onboarding_step onboarding_step not null default 'FACILITY_DETAILS',
  add column updated_at timestamptz not null default now();

-- Defaults above exist only so the ALTER succeeds on a table that could
-- already have rows; every default is empty/placeholder and every real
-- write from the Facility Details form supplies a real value, so drop the
-- defaults immediately to force the application layer to always provide them.
alter table facilities
  alter column business_email drop default,
  alter column business_phone drop default,
  alter column address_line_1 drop default,
  alter column area drop default,
  alter column state drop default,
  alter column postal_code drop default,
  alter column facility_type drop default;

alter table facilities
  add constraint facilities_custom_type_check check (
    (facility_type = 'OTHER' and custom_facility_type is not null and trim(custom_facility_type) <> '')
    or (facility_type <> 'OTHER' and custom_facility_type is null)
  );

alter table facilities alter column country set default 'India';
update facilities set country = 'India' where country is null;
alter table facilities alter column country set not null;

create trigger facilities_set_updated_at
  before update on facilities
  for each row execute function set_updated_at();

-- ─────────────────────────────────────────────────────────────────────────
-- sports: add categorisation + a catch-all "Other" row for custom sports
-- ─────────────────────────────────────────────────────────────────────────
alter table sports
  add column category text,
  add column default_playing_area_label text,
  add column updated_at timestamptz not null default now();

update sports set default_playing_area_label = case
  when key in ('badminton', 'pickleball', 'tennis') then 'COURT'
  when key in ('cricket', 'football') then 'TURF'
  else default_playing_area_label
end;

insert into sports (key, name, sort_order, default_playing_area_label)
values ('other', 'Other', 60, 'COURT')
on conflict (key) do nothing;

create trigger sports_set_updated_at
  before update on sports
  for each row execute function set_updated_at();

-- ─────────────────────────────────────────────────────────────────────────
-- facility_sports: surrogate id (frontend already treats this as a stable
-- FK — playing areas reference it), is_active for soft deactivation, and a
-- custom name slot for the "Other" sport.
-- ─────────────────────────────────────────────────────────────────────────
-- courts' old composite FK into facility_sports(facility_id, sport_id) must
-- go first — it depends on facility_sports_pkey, which we're about to drop,
-- and Postgres refuses to drop a PK that a live FK still references. The FK
-- is re-established below (against facility_sports.id) once courts gets its
-- own facility_sport_id column.
do $$
declare
  con record;
begin
  for con in
    select conname from pg_constraint
    where conrelid = 'courts'::regclass
      and contype = 'f'
      and confrelid = 'facility_sports'::regclass
  loop
    execute format('alter table courts drop constraint %I', con.conname);
  end loop;
end $$;

alter table facility_sports drop constraint facility_sports_pkey;

alter table facility_sports
  add column id uuid not null default gen_random_uuid(),
  add column is_active boolean not null default true,
  add column custom_sport_name text,
  add column updated_at timestamptz not null default now();

alter table facility_sports add primary key (id);
alter table facility_sports add constraint facility_sports_facility_sport_unique unique (facility_id, sport_id);

create trigger facility_sports_set_updated_at
  before update on facility_sports
  for each row execute function set_updated_at();

-- ─────────────────────────────────────────────────────────────────────────
-- courts (serves as "playing areas" in the app/UI layer): grow to match the
-- Courts & Turfs Setup page, and re-point its sport link at facility_sports
-- by surrogate id instead of the (facility_id, sport_id) composite.
-- ─────────────────────────────────────────────────────────────────────────
alter table courts
  add column facility_sport_id uuid references facility_sports (id) on delete cascade,
  add column area_type area_type not null default 'INDOOR',
  add column status entity_status not null default 'ACTIVE',
  add column booking_enabled boolean not null default true,
  add column archived boolean not null default false,
  add column display_order integer not null default 0,
  add column updated_at timestamptz not null default now();

alter table courts alter column facility_sport_id set not null;

alter table courts drop column is_active;

do $$
declare
  con record;
begin
  -- The old unique(facility_id, name) constraint — superseded by the
  -- per-facility_sport, case-insensitive partial index added below.
  for con in
    select conname from pg_constraint
    where conrelid = 'courts'::regclass
      and contype = 'u'
  loop
    execute format('alter table courts drop constraint %I', con.conname);
  end loop;
end $$;

-- Case-insensitive uniqueness scoped to facility_sport_id, per spec — an
-- archived row's name is excluded so a removed court/turf's name can be
-- reused without a soft-deleted ghost blocking it.
create unique index courts_facility_sport_name_idx
  on courts (facility_sport_id, lower(name))
  where not archived;

-- A court's facility_id/sport_id must agree with the facility_sport row it
-- points at — the integrity rule item #6 asks for, enforced at the database
-- layer so no service-layer bug can attach Facility A's court to Facility
-- B's facility_sport.
create function enforce_court_facility_sport_consistency() returns trigger
language plpgsql
as $$
declare
  fs facility_sports;
begin
  select * into fs from facility_sports where id = new.facility_sport_id;
  if fs is null then
    raise exception 'facility_sport % does not exist', new.facility_sport_id
      using errcode = '23503';
  end if;
  if fs.facility_id is distinct from new.facility_id then
    raise exception 'court facility_id must match its facility_sport''s facility_id'
      using errcode = '23514';
  end if;
  if fs.sport_id is distinct from new.sport_id then
    raise exception 'court sport_id must match its facility_sport''s sport_id'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

create trigger courts_enforce_facility_sport_consistency
  before insert or update on courts
  for each row execute function enforce_court_facility_sport_consistency();

create index courts_facility_sport_id_idx on courts (facility_sport_id);
create index courts_sport_id_idx on courts (sport_id);
create index courts_status_idx on courts (status);

create trigger courts_set_updated_at
  before update on courts
  for each row execute function set_updated_at();

-- Extra indexes item #9 calls out that 0001 doesn't already have.
create index facility_sports_sport_id_idx on facility_sports (sport_id);

-- ─────────────────────────────────────────────────────────────────────────
-- RPCs: multi-row/multi-table writes that must succeed or fail as one unit
-- ─────────────────────────────────────────────────────────────────────────

-- Creates a facility and, in the same transaction, the owner's facility_users
-- row (without which facilities_select_members/update_owner would lock the
-- creator out of the facility they just made). Runs as the caller (security
-- invoker, the default) so both inserts are still governed by RLS —
-- facilities_insert_self_owned requires owner_id = auth.uid(), and
-- facility_users' self-claim branch requires the facilities row it's
-- claiming to already exist, which it does by the time this statement runs.
create function create_facility_with_owner(
  p_name text,
  p_facility_type facility_type,
  p_custom_facility_type text,
  p_business_email text,
  p_business_phone text,
  p_address_line_1 text,
  p_address_line_2 text,
  p_area text,
  p_city text,
  p_state text,
  p_country text,
  p_postal_code text,
  p_latitude numeric,
  p_longitude numeric,
  p_timezone text,
  p_logo_url text,
  p_description text
) returns facilities
language plpgsql
as $$
declare
  result facilities;
  facility_slug text;
begin
  facility_slug := lower(regexp_replace(p_name, '[^a-zA-Z0-9]+', '-', 'g')) || '-' || substr(gen_random_uuid()::text, 1, 8);

  insert into facilities (
    name, slug, owner_id, facility_type, custom_facility_type,
    business_email, business_phone,
    address_line_1, address_line_2, area, city, state, country, postal_code,
    latitude, longitude, timezone, logo_url, description
  ) values (
    p_name, facility_slug, auth.uid(), p_facility_type, p_custom_facility_type,
    p_business_email, p_business_phone,
    p_address_line_1, p_address_line_2, p_area, p_city, p_state,
    coalesce(p_country, 'India'), p_postal_code,
    p_latitude, p_longitude, coalesce(p_timezone, 'Asia/Kolkata'), p_logo_url, p_description
  ) returning * into result;

  insert into facility_users (facility_id, user_id, role)
  values (result.id, auth.uid(), 'owner');

  return result;
end;
$$;

-- Replaces a facility's sport selection in one transaction: reactivates or
-- inserts every selected sport (preserving id/created_at for one already
-- selected — the exact bug class fixed in the mock layer, see git history
-- on mock-sport-service.ts), and deactivates (never deletes) any sport that
-- was selected before but isn't anymore, so playing areas that reference it
-- are never silently orphaned.
create function sync_facility_sports(
  p_facility_id uuid,
  p_sport_ids uuid[],
  p_custom_sport_name text default null
) returns setof facility_sports
language plpgsql
as $$
declare
  other_sport_id uuid;
begin
  select id into other_sport_id from sports where key = 'other';

  insert into facility_sports (facility_id, sport_id, is_active, custom_sport_name)
  select p_facility_id, s, true,
         case when s = other_sport_id then p_custom_sport_name else null end
  from unnest(p_sport_ids) as s
  on conflict (facility_id, sport_id) do update
    set is_active = true,
        custom_sport_name = excluded.custom_sport_name;

  update facility_sports
  set is_active = false
  where facility_id = p_facility_id
    and is_active = true
    and sport_id <> all(p_sport_ids);

  return query
    select * from facility_sports
    where facility_id = p_facility_id and is_active = true;
end;
$$;