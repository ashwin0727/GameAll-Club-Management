-- Pricing redesign: price by sport or by court, specific days, a peak / off-peak tag per time slot, per-session pricing, and member /
-- coaching rates that are collected and stored.
--
--   * pricing_rules.day_type        gains SPECIFIC_DAYS (with days_of_week: the chosen days, 0 = Sunday .. 6 = Saturday)
--   * pricing_rules.rate_tier       PEAK | OFF_PEAK, a label on a time slot (no effect on the price)
--   * pricing_rules.audience        GENERAL (the booking price) | MEMBER | COACHING. Member and coaching rates are only stored for now:
--                                   booking prices (resolve_booking_price) use GENERAL rules alone.
--   * facilities.pricing_mode / different_weekend_pricing / member_pricing_enabled / coaching_pricing_enabled   the Pricing Settings
--   * resolve_booking_price         now understands specific days and PER_SESSION / PER_30_MINUTES rates
--   * courts.hourly_rate_inr        kept in step with the saved prices, so the Player app shows "From ₹X / hour"

-- ── rule columns ─────────────────────────────────────────────────────────
alter table pricing_rules
  add column if not exists days_of_week smallint[],
  add column if not exists rate_tier text,
  add column if not exists audience text not null default 'GENERAL';

do $$
declare
  con record;
begin
  for con in
    select conname from pg_constraint
     where conrelid = 'pricing_rules'::regclass and contype = 'c' and pg_get_constraintdef(oid) ilike '%day_type%in%'
  loop
    execute format('alter table pricing_rules drop constraint %I', con.conname);
  end loop;
end $$;

alter table pricing_rules drop constraint if exists pricing_rules_day_type_chk;
alter table pricing_rules
  add constraint pricing_rules_day_type_chk check (day_type in ('ALL_DAYS', 'WEEKDAYS', 'WEEKENDS', 'SPECIFIC_DAYS'));
alter table pricing_rules drop constraint if exists pricing_rules_specific_days_chk;
alter table pricing_rules add constraint pricing_rules_specific_days_chk check (
  (day_type = 'SPECIFIC_DAYS' and days_of_week is not null and cardinality(days_of_week) between 1 and 7)
  or (day_type <> 'SPECIFIC_DAYS' and days_of_week is null)
);
alter table pricing_rules drop constraint if exists pricing_rules_days_range_chk;
alter table pricing_rules add constraint pricing_rules_days_range_chk
  check (days_of_week is null or days_of_week <@ array[0, 1, 2, 3, 4, 5, 6]::smallint[]);
alter table pricing_rules drop constraint if exists pricing_rules_rate_tier_chk;
alter table pricing_rules add constraint pricing_rules_rate_tier_chk check (rate_tier is null or rate_tier in ('PEAK', 'OFF_PEAK'));
alter table pricing_rules drop constraint if exists pricing_rules_audience_chk;
alter table pricing_rules add constraint pricing_rules_audience_chk check (audience in ('GENERAL', 'MEMBER', 'COACHING'));

drop index if exists pricing_rules_no_duplicates_idx;
create unique index pricing_rules_no_duplicates_idx on pricing_rules (
  facility_sport_id,
  coalesce(playing_area_id, '00000000-0000-0000-0000-000000000000'::uuid),
  audience,
  day_type,
  coalesce(days_of_week, '{}'::smallint[]),
  coalesce(start_time, '00:00:00'::time),
  coalesce(end_time, '00:00:00'::time)
) where is_active;

-- ── the Pricing Settings ─────────────────────────────────────────────────
alter table facilities
  add column if not exists pricing_mode text not null default 'BY_SPORT',
  add column if not exists different_weekend_pricing boolean not null default true,
  add column if not exists member_pricing_enabled boolean not null default false,
  add column if not exists coaching_pricing_enabled boolean not null default false;
alter table facilities drop constraint if exists facilities_pricing_mode_chk;
alter table facilities add constraint facilities_pricing_mode_chk check (pricing_mode in ('BY_SPORT', 'BY_COURT'));

-- ── save: same replace-the-plan behaviour, with the new fields ───────────
create or replace function save_pricing_rules(
  p_facility_id uuid,
  p_plan_name text,
  p_rules jsonb
) returns pricing_plans
language plpgsql
as $$
declare
  plan pricing_plans;
  rule jsonb;
  tier text;
  audience text;
  days smallint[];
begin
  select * into plan from pricing_plans where facility_id = p_facility_id and status = 'ACTIVE';

  if plan.id is null then
    insert into pricing_plans (facility_id, name, currency)
    values (p_facility_id, coalesce(p_plan_name, 'Standard Pricing'), 'INR')
    returning * into plan;
  else
    update pricing_plans set updated_at = now() where id = plan.id returning * into plan;
  end if;

  -- no two time windows may overlap for the same sport / court, audience and day group
  -- (specific-day groups only clash when they share a day)
  if exists (
    select 1
      from jsonb_array_elements(p_rules) with ordinality a(r, i)
      join jsonb_array_elements(p_rules) with ordinality b(r, j) on a.i < b.j
     where not coalesce((a.r ->> 'coversFullDay')::boolean, true)
       and not coalesce((b.r ->> 'coversFullDay')::boolean, true)
       and a.r ->> 'facilitySportId' = b.r ->> 'facilitySportId'
       and coalesce(a.r ->> 'playingAreaId', '') = coalesce(b.r ->> 'playingAreaId', '')
       and coalesce(a.r ->> 'audience', 'GENERAL') = coalesce(b.r ->> 'audience', 'GENERAL')
       and coalesce(a.r ->> 'dayType', 'ALL_DAYS') = coalesce(b.r ->> 'dayType', 'ALL_DAYS')
       and (
         coalesce(a.r ->> 'dayType', 'ALL_DAYS') <> 'SPECIFIC_DAYS'
         or exists (
           select 1 from jsonb_array_elements_text(a.r -> 'daysOfWeek') x
             join jsonb_array_elements_text(b.r -> 'daysOfWeek') y on x = y
         )
       )
       and (a.r ->> 'startTime')::time < (b.r ->> 'endTime')::time
       and (b.r ->> 'startTime')::time < (a.r ->> 'endTime')::time
  ) then
    raise exception 'Pricing periods cannot overlap.' using errcode = '23514';
  end if;

  delete from pricing_rules where pricing_plan_id = plan.id;

  for rule in select * from jsonb_array_elements(p_rules)
  loop
    tier := nullif(rule ->> 'rateTier', '');
    audience := coalesce(nullif(rule ->> 'audience', ''), 'GENERAL');
    days := null;
    if coalesce(rule ->> 'dayType', 'ALL_DAYS') = 'SPECIFIC_DAYS' then
      days := array(select jsonb_array_elements_text(rule -> 'daysOfWeek')::smallint order by 1);
    end if;

    insert into pricing_rules (
      pricing_plan_id, facility_id, facility_sport_id, playing_area_id,
      day_type, days_of_week, covers_full_day, start_time, end_time,
      amount_minor, currency, pricing_unit, priority, rate_tier, audience
    ) values (
      plan.id, p_facility_id,
      (rule ->> 'facilitySportId')::uuid,
      nullif(rule ->> 'playingAreaId', '')::uuid,
      coalesce(rule ->> 'dayType', 'ALL_DAYS'),
      days,
      coalesce((rule ->> 'coversFullDay')::boolean, true),
      nullif(rule ->> 'startTime', '')::time,
      nullif(rule ->> 'endTime', '')::time,
      (rule ->> 'amountMinor')::integer,
      coalesce(rule ->> 'currency', 'INR'),
      coalesce(rule ->> 'pricingUnit', 'PER_HOUR'),
      coalesce((rule ->> 'priority')::integer, case when rule ->> 'playingAreaId' is not null then 10 else 0 end),
      tier,
      audience
    );
  end loop;

  return plan;
end;
$$;

-- ── the booking price ────────────────────────────────────────────────────
-- As 0039, plus: only GENERAL rules set a booking price; a specific-days rule is the most specific day match; and the rate's unit counts
-- (per hour x hours, per 30 minutes x half hours, per session / match = the amount as is).
create or replace function resolve_booking_price(
  p_facility_sport_id uuid,
  p_court_id uuid,
  p_start timestamptz,
  p_end timestamptz,
  p_timezone text
) returns integer
language plpgsql
stable
as $$
declare
  local_start timestamp := p_start at time zone coalesce(p_timezone, 'Asia/Kolkata');
  local_end timestamp := p_end at time zone coalesce(p_timezone, 'Asia/Kolkata');
  dow smallint := extract(dow from local_start);
  is_weekend boolean := dow in (0, 6);
  start_min integer := extract(hour from local_start) * 60 + extract(minute from local_start);
  end_min integer := extract(hour from local_end) * 60 + extract(minute from local_end);
  duration_hours numeric := extract(epoch from (p_end - p_start)) / 3600.0;
  rule pricing_rules;
  rule_start_min integer;
  rule_end_min integer;
begin
  for rule in
    select * from pricing_rules
    where facility_sport_id = p_facility_sport_id
      and is_active
      and audience = 'GENERAL'
      and (playing_area_id = p_court_id or playing_area_id is null)
      and (
        day_type = 'ALL_DAYS'
        or (day_type = 'WEEKENDS' and is_weekend)
        or (day_type = 'WEEKDAYS' and not is_weekend)
        or (day_type = 'SPECIFIC_DAYS' and dow = any (days_of_week))
      )
    order by
      (playing_area_id is not null) desc,
      covers_full_day asc,
      (case day_type when 'SPECIFIC_DAYS' then 2 when 'ALL_DAYS' then 0 else 1 end) desc,
      priority desc
  loop
    if not rule.covers_full_day then
      rule_start_min := extract(hour from rule.start_time) * 60 + extract(minute from rule.start_time);
      rule_end_min := extract(hour from rule.end_time) * 60 + extract(minute from rule.end_time);
      if rule_end_min <= rule_start_min then
        rule_end_min := rule_end_min + 24 * 60;
      end if;
      continue when not (start_min >= rule_start_min and end_min <= rule_end_min);
    end if;
    return case rule.pricing_unit
      when 'PER_SESSION' then rule.amount_minor
      when 'PER_MATCH' then rule.amount_minor
      when 'PER_30_MINUTES' then round(rule.amount_minor * duration_hours * 2)
      else round(rule.amount_minor * duration_hours)
    end;
  end loop;

  return null;
end;
$$;

-- ── courts.hourly_rate_inr follows the saved prices ──────────────────────
-- The Player app's "From ₹X / hour" reads this column. Each court gets its lowest general rate (its own rates when it has any, else its
-- sport's), in whole rupees; a per-30-minute rate counts double.
create or replace function sync_court_hourly_rates(p_facility_sport_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update courts c
     set hourly_rate_inr = coalesce((
       select round(coalesce(
         (select min(case r.pricing_unit when 'PER_30_MINUTES' then r.amount_minor * 2 else r.amount_minor end)
            from pricing_rules r
           where r.facility_sport_id = c.facility_sport_id and r.is_active and r.audience = 'GENERAL' and r.playing_area_id = c.id),
         (select min(case r.pricing_unit when 'PER_30_MINUTES' then r.amount_minor * 2 else r.amount_minor end)
            from pricing_rules r
           where r.facility_sport_id = c.facility_sport_id and r.is_active and r.audience = 'GENERAL' and r.playing_area_id is null)
       ) / 100.0)::integer
     ), 0)
   where c.facility_sport_id = p_facility_sport_id;
end;
$$;
revoke all on function sync_court_hourly_rates(uuid) from public, anon, authenticated;

create or replace function pricing_rules_sync_court_rates()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op in ('UPDATE', 'DELETE') then
    perform sync_court_hourly_rates(old.facility_sport_id);
  end if;
  if tg_op in ('INSERT', 'UPDATE') then
    perform sync_court_hourly_rates(new.facility_sport_id);
  end if;
  return null;
end;
$$;

drop trigger if exists pricing_rules_sync_court_rates on pricing_rules;
create trigger pricing_rules_sync_court_rates
  after insert or update or delete on pricing_rules
  for each row execute function pricing_rules_sync_court_rates();

-- a court added after the prices were set picks its rate up too
create or replace function courts_sync_own_rate()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform sync_court_hourly_rates(new.facility_sport_id);
  return null;
end;
$$;
drop trigger if exists courts_sync_own_rate on courts;
create trigger courts_sync_own_rate
  after insert on courts
  for each row execute function courts_sync_own_rate();

-- venues that already have prices
do $$
declare
  fs record;
begin
  for fs in select distinct facility_sport_id from pricing_rules where is_active loop
    perform sync_court_hourly_rates(fs.facility_sport_id);
  end loop;
end;
$$;
