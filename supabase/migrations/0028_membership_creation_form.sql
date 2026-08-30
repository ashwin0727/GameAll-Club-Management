-- ═══════════════════════════════════════════════════════════════════════════
-- Membership creation form — Phase 4.
--
-- The Create Membership screen becomes a full page and captures a
-- self-contained membership (its own name / type / duration / fee / GST /
-- time slot) rather than always pointing at a membership_plan. So:
--
--   • members       += address
--   • memberships    : plan_id becomes NULLable; adds name, membership_type,
--                      max_family_members, duration_days, time_slot_start/end,
--                      description, membership_fee_inr, registration_fee_inr,
--                      gst_percent, total_amount_inr, payment_reference,
--                      referral_member_id, discovery_source, notes
--   • create_membership_full — one write path: get-or-create the member,
--     insert the membership, compute the charge total, record the payment.
--   • list_memberships — falls back to the membership's own name / fee when
--     there's no plan.
-- ═══════════════════════════════════════════════════════════════════════════

alter table members add column if not exists address text;

alter table memberships alter column plan_id drop not null;

alter table memberships
  add column if not exists name text,
  add column if not exists membership_type text not null default 'INDIVIDUAL'
    check (membership_type in ('INDIVIDUAL', 'FAMILY', 'CORPORATE')),
  add column if not exists max_family_members integer not null default 1 check (max_family_members >= 1),
  add column if not exists duration_days integer,
  add column if not exists time_slot_start time,
  add column if not exists time_slot_end time,
  add column if not exists description text,
  add column if not exists membership_fee_inr integer,
  add column if not exists registration_fee_inr integer not null default 0,
  add column if not exists gst_percent numeric(5, 2) not null default 0,
  add column if not exists total_amount_inr integer,
  add column if not exists payment_reference text,
  add column if not exists referral_member_id uuid references members (id) on delete set null,
  add column if not exists discovery_source text;

-- notes may already exist from an earlier iteration; add defensively.
alter table memberships add column if not exists notes text;

-- ─────────────────────────────────────────────────────────────────────────
-- create_membership_full
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
  p_time_slot_start time,
  p_time_slot_end time,
  p_description text,
  p_membership_fee_inr integer,
  p_registration_fee_inr integer,
  p_gst_percent numeric,
  p_payment_mode text,          -- 'PAID' | 'PENDING' | 'FREE'
  p_payment_methods text,       -- comma-joined accepted methods
  p_payment_reference text,
  p_referral_member_id uuid,
  p_discovery_source text,
  p_notes text,
  p_monthly_price_inr integer default null
) returns memberships
language plpgsql
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
begin
  if trim(coalesce(p_full_name, '')) = '' or trim(coalesce(p_phone, '')) = '' then
    raise exception 'Member name and phone are required.' using errcode = '23514';
  end if;
  if coalesce(p_duration_days, 0) <= 0 then
    raise exception 'Choose a membership duration.' using errcode = '23514';
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
    -- Backfill blanks only — never overwrite existing member data.
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
    time_slot_start, time_slot_end, description,
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
    p_time_slot_start, p_time_slot_end, nullif(trim(p_description), ''),
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

  return result;
end;
$$;

grant execute on function create_membership_full(
  uuid, text, text, text, date, text, text,
  text, text, integer, date, integer, time, time, text,
  integer, integer, numeric, text, text, text, uuid, text, text, integer
) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- list_memberships — plan is now optional; fall back to the membership's own
-- name / fee / time slot. OUT columns unchanged from 0027 EXCEPT the slot
-- comes from the membership itself when there's no batch, so recreate.
-- ─────────────────────────────────────────────────────────────────────────
drop function if exists list_memberships(uuid, text, text, uuid, text, integer, integer);

create function list_memberships(
  p_facility_id uuid,
  p_search text default null,
  p_status text default null,
  p_plan_id uuid default null,
  p_sort text default 'newest',
  p_limit integer default 10,
  p_offset integer default 0
) returns table (
  membership_id uuid,
  member_id uuid,
  member_name text,
  member_phone text,
  member_email text,
  plan_id uuid,
  plan_name text,
  monthly_price_inr integer,
  display_status text,
  start_date date,
  end_date date,
  days_left integer,
  created_by uuid,
  created_by_name text,
  batch_name text,
  batch_days integer[],
  batch_start time,
  batch_end time,
  batch_court text,
  total_count bigint
)
language sql
stable
as $$
  with base as (
    select
      m.id as membership_id,
      m.member_id,
      mem.full_name as member_name,
      mem.phone as member_phone,
      mem.email as member_email,
      m.plan_id,
      coalesce(m.name, mp.name, 'Membership') as plan_name,
      coalesce(m.monthly_price_inr, m.membership_fee_inr, mp.price_inr, 0) as monthly_price_inr,
      case
        when m.status = 'cancelled' then 'cancelled'
        when m.end_date < current_date then 'expired'
        when m.end_date <= current_date + 30 then 'expiring_soon'
        else 'active'
      end as display_status,
      m.start_date,
      m.end_date,
      (m.end_date - current_date) as days_left,
      m.created_by,
      p.full_name as created_by_name,
      coalesce(b.name, case when m.time_slot_start is not null then 'Time slot' end) as batch_name,
      b.days_of_week as batch_days,
      coalesce(b.start_time, m.time_slot_start) as batch_start,
      coalesce(b.end_time, m.time_slot_end) as batch_end,
      bc.name as batch_court,
      m.created_at
    from memberships m
    join members mem on mem.id = m.member_id
    left join membership_plans mp on mp.id = m.plan_id
    left join profiles p on p.id = m.created_by
    left join lateral (
      select bm.batch_id
      from membership_batch_members bm
      where bm.membership_id = m.id
      order by bm.created_at
      limit 1
    ) bml on true
    left join membership_batches b on b.id = bml.batch_id
    left join courts bc on bc.id = b.court_id
    where m.facility_id = p_facility_id
      and (
        p_search is null
        or mem.full_name ilike '%' || p_search || '%'
        or mem.phone ilike '%' || p_search || '%'
        or coalesce(mem.email, '') ilike '%' || p_search || '%'
      )
      and (p_plan_id is null or m.plan_id = p_plan_id)
  ),
  filtered as (
    select * from base where p_status is null or display_status = p_status
  )
  select
    membership_id, member_id, member_name, member_phone, member_email,
    plan_id, plan_name, monthly_price_inr, display_status,
    start_date, end_date, days_left, created_by, created_by_name,
    batch_name, batch_days, batch_start, batch_end, batch_court,
    count(*) over () as total_count
  from filtered
  order by
    case when p_sort = 'oldest' then created_at end asc nulls last,
    case when p_sort = 'expiry_asc' then end_date end asc nulls last,
    case when p_sort = 'expiry_desc' then end_date end desc nulls last,
    case when p_sort = 'name' then member_name end asc nulls last,
    created_at desc
  limit greatest(p_limit, 1)
  offset greatest(p_offset, 0);
$$;

grant execute on function list_memberships(uuid, text, text, uuid, text, integer, integer) to authenticated;