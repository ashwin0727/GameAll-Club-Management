-- ═══════════════════════════════════════════════════════════════════════════
-- Per-hour membership-player capacity — Phase 3.
--
-- A `membership_batch` already models "this court, these week-days, this time
-- window, this many members" (5–6 AM, Court 1, capacity 6). What was missing:
--
--   1. assign_batch_member did NOT enforce that capacity — the roster could
--      grow past it. Now it does (counts current membership_batch_members).
--   2. no way for the Memberships / public sign-up UI to show "4 / 6" and
--      pick a slot. Adds list_assignable_batches (staff) and a matching
--      anon-safe read, plus an optional p_batch_id on
--      public_start_membership_signup so a self-registering player is placed
--      straight into a slot.
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────
-- assign_batch_member — now capacity-checked. Drop+recreate (body change on
-- a plpgsql function is a replace, but keep it explicit alongside the others).
-- ─────────────────────────────────────────────────────────────────────────
create or replace function assign_batch_member(p_batch_id uuid, p_member_id uuid, p_membership_id uuid default null)
returns membership_batch_members
language plpgsql
as $$
declare
  batch membership_batches;
  member members;
  enrolled integer;
  result membership_batch_members;
begin
  select * into batch from membership_batches where id = p_batch_id;
  if batch.id is null then
    raise exception 'Membership batch not found' using errcode = 'P0002';
  end if;

  select * into member from members where id = p_member_id and facility_id = batch.facility_id;
  if member.id is null then
    raise exception 'That member does not belong to this facility.' using errcode = '23503';
  end if;

  -- Already in this batch? Idempotent no-op — return the existing row.
  select * into result from membership_batch_members
    where batch_id = p_batch_id and member_id = p_member_id;
  if result.id is not null then
    return result;
  end if;

  select count(*) into enrolled from membership_batch_members where batch_id = p_batch_id;
  if enrolled >= batch.capacity then
    raise exception 'This time slot is full (% / % members).', enrolled, batch.capacity
      using errcode = '23514';
  end if;

  insert into membership_batch_members (batch_id, member_id, membership_id)
  values (p_batch_id, p_member_id, p_membership_id)
  returning * into result;

  return result;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- list_assignable_batches — every active batch for the facility with its
-- current roster count, so the UI can show "4 / 6" and disable full slots.
-- Optionally scoped to one plan.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function list_assignable_batches(p_facility_id uuid, p_plan_id uuid default null)
returns table (
  batch_id uuid,
  name text,
  plan_id uuid,
  court_id uuid,
  court_name text,
  facility_sport_id uuid,
  sport_name text,
  days_of_week integer[],
  start_time time,
  end_time time,
  capacity integer,
  enrolled_count integer,
  spare integer
)
language sql
stable
as $$
  select
    b.id,
    b.name,
    b.plan_id,
    b.court_id,
    c.name as court_name,
    b.facility_sport_id,
    coalesce(fs.custom_sport_name, s.name) as sport_name,
    b.days_of_week,
    b.start_time,
    b.end_time,
    b.capacity,
    coalesce(m.cnt, 0)::integer as enrolled_count,
    greatest(b.capacity - coalesce(m.cnt, 0), 0)::integer as spare
  from membership_batches b
  join courts c on c.id = b.court_id
  join facility_sports fs on fs.id = b.facility_sport_id
  join sports s on s.id = fs.sport_id
  left join (
    select batch_id, count(*)::integer as cnt
    from membership_batch_members
    group by batch_id
  ) m on m.batch_id = b.id
  where b.facility_id = p_facility_id
    and b.is_active
    and (p_plan_id is null or b.plan_id = p_plan_id)
  order by b.start_time, b.name;
$$;

grant execute on function list_assignable_batches(uuid, uuid) to authenticated;

-- Anon-safe version for the public /join page: only batches with a free
-- seat, minimal columns, SECURITY DEFINER so anon never reads the table.
create or replace function get_public_signup_batches(p_facility_id uuid, p_plan_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'batchId', batch_id,
    'name', name,
    'courtName', court_name,
    'sportName', sport_name,
    'daysOfWeek', days_of_week,
    'startTime', start_time,
    'endTime', end_time,
    'capacity', capacity,
    'spare', spare
  ) order by start_time), '[]'::jsonb)
  from list_assignable_batches(p_facility_id, p_plan_id)
  where spare > 0;
$$;

grant execute on function get_public_signup_batches(uuid, uuid) to anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- public_start_membership_signup — replace to accept an optional slot and
-- place the self-registering player into it (capacity-checked by
-- assign_batch_member). Argument list changes, so drop+recreate.
-- ─────────────────────────────────────────────────────────────────────────
drop function if exists public_start_membership_signup(uuid, text, text, text, uuid);
drop function if exists public_start_membership_signup(uuid, text, text, text, uuid, uuid);

create function public_start_membership_signup(
  p_facility_id uuid,
  p_full_name text,
  p_phone text,
  p_email text,
  p_plan_id uuid,
  p_batch_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  plan membership_plans;
  batch membership_batches;
  v_member_id uuid;
  computed_end date;
  v_membership_id uuid;
begin
  if coalesce(trim(p_full_name), '') = '' or coalesce(trim(p_phone), '') = '' then
    raise exception 'Name and phone are required.' using errcode = '22023';
  end if;

  select * into plan from membership_plans
    where id = p_plan_id and facility_id = p_facility_id and is_active;
  if plan.id is null then
    raise exception 'Membership plan not available.' using errcode = '23503';
  end if;

  if p_batch_id is not null then
    select * into batch from membership_batches where id = p_batch_id and facility_id = p_facility_id and is_active;
    if batch.id is null then
      raise exception 'That time slot is not available.' using errcode = '23503';
    end if;
  end if;

  select id into v_member_id from members
    where facility_id = p_facility_id and phone = trim(p_phone);
  if v_member_id is null then
    insert into members (facility_id, full_name, phone, email)
    values (p_facility_id, trim(p_full_name), trim(p_phone), nullif(trim(p_email), ''))
    returning id into v_member_id;
  end if;

  computed_end := current_date + plan.duration_days;

  insert into memberships (facility_id, member_id, plan_id, status, start_date, end_date, created_by, monthly_price_inr)
  values (p_facility_id, v_member_id, p_plan_id,
          case when computed_end >= current_date then 'active' else 'expired' end,
          current_date, computed_end, null, plan.price_inr)
  returning id into v_membership_id;

  if p_batch_id is not null then
    perform assign_batch_member(p_batch_id, v_member_id, v_membership_id);
  end if;

  if plan.price_inr > 0 then
    insert into payments (facility_id, member_id, membership_id, amount_inr, status)
    values (p_facility_id, v_member_id, v_membership_id, plan.price_inr, 'created');
  end if;

  return jsonb_build_object(
    'membershipId', v_membership_id,
    'memberId', v_member_id,
    'amountInr', plan.price_inr
  );
end;
$$;

grant execute on function public_start_membership_signup(uuid, text, text, text, uuid, uuid) to anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- list_memberships — surface the member's assigned slot (if any) so the
-- Memberships table can show "Mon/Wed · 5–6 AM · Court 1". The OUT-parameter
-- set changes, so Postgres needs an explicit DROP before the recreate.
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
      mp.name as plan_name,
      coalesce(m.monthly_price_inr, mp.price_inr) as monthly_price_inr,
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
      b.name as batch_name,
      b.days_of_week as batch_days,
      b.start_time as batch_start,
      b.end_time as batch_end,
      bc.name as batch_court,
      m.created_at
    from memberships m
    join members mem on mem.id = m.member_id
    join membership_plans mp on mp.id = m.plan_id
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