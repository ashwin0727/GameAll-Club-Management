-- ═══════════════════════════════════════════════════════════════════════════
-- Membership time slots — Phase 5.
--
-- The Phase 4 Create Membership page (0028) stored a cosmetic
-- time_slot_start/end on the membership row that reserved nothing. This wires
-- the membership's play window into `membership_batches` — the mechanism that
-- ALREADY blocks ad-hoc bookings (court_has_active_membership_window) and
-- renders a locked slot in the Bookings grid.
--
--   • facilities        += membership_access_days (the per-facility default
--                          day set the Create form pre-fills)
--   • membership_batches : plan_id becomes NULLable (self-contained
--                          memberships have no plan; the composite FK is
--                          MATCH SIMPLE so a NULL row is unchecked)
--   • set_facility_membership_access_days — owner/manager sets the default
--   • create_membership_full — after inserting the membership, optionally
--     join an existing batch (p_batch_id) or create one (p_new_batch) and
--     enrol the member via assign_batch_member (capacity-checked). The
--     cosmetic p_time_slot_start/end args are removed.
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────
-- Facility default membership access days
-- ─────────────────────────────────────────────────────────────────────────
alter table facilities
  add column if not exists membership_access_days smallint[] not null
    default array[0, 1, 2, 3, 4, 5, 6]::smallint[];

alter table facilities
  drop constraint if exists facilities_membership_access_days_check;
alter table facilities
  add constraint facilities_membership_access_days_check check (
    coalesce(array_length(membership_access_days, 1), 0) > 0
    and membership_access_days <@ array[0, 1, 2, 3, 4, 5, 6]::smallint[]
  );

-- ─────────────────────────────────────────────────────────────────────────
-- Self-contained memberships have no plan, so neither does their batch.
-- ─────────────────────────────────────────────────────────────────────────
alter table membership_batches alter column plan_id drop not null;

-- ─────────────────────────────────────────────────────────────────────────
-- set_facility_membership_access_days
-- ─────────────────────────────────────────────────────────────────────────
create or replace function set_facility_membership_access_days(
  p_facility_id uuid,
  p_days smallint[]
) returns facilities
language plpgsql
security definer
set search_path = public
as $$
declare
  result facilities;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager']::facility_role[]) then
    raise exception 'Not authorized to change membership settings.' using errcode = '42501';
  end if;
  if coalesce(array_length(p_days, 1), 0) = 0 then
    raise exception 'Select at least one access day.' using errcode = '23514';
  end if;
  if not (p_days <@ array[0, 1, 2, 3, 4, 5, 6]::smallint[]) then
    raise exception 'Invalid day value.' using errcode = '23514';
  end if;

  update facilities set membership_access_days = p_days
  where id = p_facility_id
  returning * into result;

  if result.id is null then
    raise exception 'Facility not found' using errcode = 'P0002';
  end if;
  return result;
end;
$$;

grant execute on function set_facility_membership_access_days(uuid, smallint[]) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- create_membership_full — batch-aware. Arg list changes (drops the two
-- cosmetic time-slot params, adds p_batch_id / p_new_batch), so drop+recreate.
-- ─────────────────────────────────────────────────────────────────────────
drop function if exists create_membership_full(
  uuid, text, text, text, date, text, text,
  text, text, integer, date, integer, time, time, text,
  integer, integer, numeric, text, text, text, uuid, text, text, integer
);

create function create_membership_full(
  p_facility_id uuid,
  p_full_name text,
  p_phone text,
  p_email text,
  p_date_of_birth date,
  p_gender text,
  p_address text,
  p_name text,
  p_membership_type text,
  p_max_family_members integer,
  p_start_date date,
  p_duration_days integer,
  p_description text,
  p_membership_fee_inr integer,
  p_registration_fee_inr integer,
  p_gst_percent numeric,
  p_payment_mode text,
  p_payment_methods text,
  p_payment_reference text,
  p_referral_member_id uuid,
  p_discovery_source text,
  p_notes text,
  p_monthly_price_inr integer default null,
  p_batch_id uuid default null,
  p_new_batch jsonb default null
) returns memberships
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member_id uuid;
  computed_end date;
  fee integer := greatest(coalesce(p_membership_fee_inr, 0), 0);
  reg integer := greatest(coalesce(p_registration_fee_inr, 0), 0);
  gst numeric := greatest(coalesce(p_gst_percent, 0), 0);
  gst_amount integer;
  total integer;
  result memberships;
  v_batch_id uuid;
  v_court courts;
  v_days smallint[];
  v_start time;
  v_end time;
  v_capacity integer;
  v_batch_name text;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  if trim(coalesce(p_full_name, '')) = '' or trim(coalesce(p_phone, '')) = '' then
    raise exception 'Member name and phone are required.' using errcode = '23514';
  end if;
  if coalesce(p_duration_days, 0) <= 0 then
    raise exception 'Choose a membership duration.' using errcode = '23514';
  end if;
  if p_batch_id is not null and p_new_batch is not null then
    raise exception 'Pick one time slot, not both.' using errcode = '23514';
  end if;

  -- Get-or-create the member by (facility, phone).
  select id into v_member_id from members
    where facility_id = p_facility_id and phone = trim(p_phone);
  if v_member_id is null then
    insert into members (facility_id, full_name, phone, email, date_of_birth, gender, address)
    values (p_facility_id, trim(p_full_name), trim(p_phone), nullif(trim(p_email), ''),
            p_date_of_birth, nullif(trim(p_gender), ''), nullif(trim(p_address), ''))
    returning id into v_member_id;
  else
    update members set
      email = coalesce(email, nullif(trim(p_email), '')),
      date_of_birth = coalesce(date_of_birth, p_date_of_birth),
      gender = coalesce(gender, nullif(trim(p_gender), '')),
      address = coalesce(address, nullif(trim(p_address), ''))
    where id = v_member_id;
  end if;

  computed_end := p_start_date + p_duration_days;
  gst_amount := round(fee * gst / 100.0);
  total := fee + gst_amount + reg;

  insert into memberships (
    facility_id, member_id, plan_id, status, start_date, end_date, created_by,
    name, membership_type, max_family_members, duration_days,
    description,
    membership_fee_inr, registration_fee_inr, gst_percent, total_amount_inr,
    monthly_price_inr, payment_reference, referral_member_id, discovery_source, notes
  )
  values (
    p_facility_id, v_member_id, null,
    (case when computed_end >= current_date then 'active' else 'expired' end)::membership_status,
    p_start_date, computed_end, auth.uid(),
    nullif(trim(p_name), ''),
    coalesce(nullif(trim(p_membership_type), ''), 'INDIVIDUAL'),
    greatest(coalesce(p_max_family_members, 1), 1),
    p_duration_days,
    nullif(trim(p_description), ''),
    fee, reg, gst, total,
    coalesce(p_monthly_price_inr, fee),
    nullif(trim(p_payment_reference), ''), p_referral_member_id, nullif(trim(p_discovery_source), ''),
    nullif(trim(p_notes), '')
  )
  returning * into result;

  if upper(coalesce(p_payment_mode, 'PENDING')) <> 'FREE' and total > 0 then
    insert into payments (facility_id, member_id, membership_id, amount_inr, status, payment_method)
    values (
      p_facility_id, v_member_id, result.id, total,
      case when upper(p_payment_mode) = 'PAID' then 'paid'::payment_status else 'created'::payment_status end,
      nullif(trim(p_payment_methods), '')
    );
  end if;

  -- ── Reserved court time slot ──────────────────────────────────────────
  if p_new_batch is not null then
    select array_agg(value::smallint) into v_days
      from jsonb_array_elements_text(p_new_batch->'daysOfWeek');
    v_start := (p_new_batch->>'startTime')::time;
    v_end := (p_new_batch->>'endTime')::time;
    v_capacity := (p_new_batch->>'capacity')::integer;

    if v_start is null or v_end is null then
      raise exception 'Time slot start and end are required.' using errcode = '23514';
    end if;
    if coalesce(array_length(v_days, 1), 0) = 0 or not (v_days <@ array[0, 1, 2, 3, 4, 5, 6]::smallint[]) then
      raise exception 'Select at least one valid access day for the time slot.' using errcode = '23514';
    end if;
    if v_end <= v_start then
      raise exception 'Time slot end must be after the start.' using errcode = '23514';
    end if;
    if coalesce(v_capacity, 0) < 1 then
      raise exception 'Time slot capacity must be at least 1.' using errcode = '23514';
    end if;

    select * into v_court from courts
      where id = (p_new_batch->>'courtId')::uuid
        and facility_id = p_facility_id
        and facility_sport_id = (p_new_batch->>'facilitySportId')::uuid;
    if v_court.id is null then
      raise exception 'That court does not belong to this facility/sport.' using errcode = '23503';
    end if;

    v_batch_name := coalesce(
      nullif(trim(p_new_batch->>'name'), ''),
      coalesce(nullif(trim(p_name), ''), 'Membership') || ' · '
        || to_char(v_start, 'FMHH12:MI') || '–' || to_char(v_end, 'FMHH12:MI AM')
    );

    insert into membership_batches (
      facility_id, plan_id, facility_sport_id, court_id, name,
      days_of_week, start_time, end_time, capacity, is_active
    ) values (
      p_facility_id, null, v_court.facility_sport_id, v_court.id, v_batch_name,
      v_days, v_start, v_end, v_capacity, true
    ) returning id into v_batch_id;
  elsif p_batch_id is not null then
    if not exists (
      select 1 from membership_batches
      where id = p_batch_id and facility_id = p_facility_id and is_active
    ) then
      raise exception 'That time slot is not available.' using errcode = '23503';
    end if;
    v_batch_id := p_batch_id;
  end if;

  if v_batch_id is not null then
    perform assign_batch_member(v_batch_id, v_member_id, result.id);
  end if;

  return result;
end;
$$;

grant execute on function create_membership_full(
  uuid, text, text, text, date, text, text,
  text, text, integer, date, integer, text,
  integer, integer, numeric, text, text, text, uuid, text, text, integer,
  uuid, jsonb
) to authenticated;