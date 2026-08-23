-- ═══════════════════════════════════════════════════════════════════════════
-- Pricing & Rate Setup
--
--   facilities → pricing_plans (one ACTIVE plan per facility)
--                       ↓
--                 pricing_rules
--                       │
--                       ├── facility_sport_id (required) — sport-level rule
--                       └── playing_area_id (nullable) — playing-area override
--
-- Resolution priority: a rule with playing_area_id set beats a rule with it
-- null, for the same facility_sport_id. facility_id is denormalized onto
-- pricing_rules (matching 0001/0004's own convention) so RLS never needs
-- more than one membership lookup.
-- ═══════════════════════════════════════════════════════════════════════════

create table pricing_plans (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references facilities (id) on delete cascade,
  name text not null default 'Standard Pricing',
  currency text not null default 'INR',
  status text not null default 'ACTIVE' check (status in ('ACTIVE', 'INACTIVE')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
-- At most one ACTIVE plan per facility.
create unique index pricing_plans_facility_active_idx
  on pricing_plans (facility_id) where status = 'ACTIVE';

create table pricing_rules (
  id uuid primary key default gen_random_uuid(),
  pricing_plan_id uuid not null references pricing_plans (id) on delete cascade,
  facility_id uuid not null references facilities (id) on delete cascade,
  facility_sport_id uuid not null references facility_sports (id) on delete cascade,
  playing_area_id uuid references courts (id) on delete cascade,
  day_type text not null default 'ALL_DAYS' check (day_type in ('ALL_DAYS', 'WEEKDAYS', 'WEEKENDS')),
  covers_full_day boolean not null default true,
  start_time time,
  end_time time,
  amount_minor integer not null check (amount_minor > 0),
  currency text not null default 'INR',
  pricing_unit text not null default 'PER_HOUR'
    check (pricing_unit in ('PER_HOUR', 'PER_30_MINUTES', 'PER_SESSION', 'PER_MATCH')),
  priority integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pricing_rules_time_window_check check (
    (covers_full_day and start_time is null and end_time is null)
    or (not covers_full_day and start_time is not null and end_time is not null and start_time <> end_time)
  )
);
create index pricing_rules_plan_id_idx on pricing_rules (pricing_plan_id);
create index pricing_rules_facility_id_idx on pricing_rules (facility_id);
create index pricing_rules_facility_sport_id_idx on pricing_rules (facility_sport_id);
create index pricing_rules_playing_area_id_idx on pricing_rules (playing_area_id);

-- Prevents an exact duplicate rule (same scope, day type, and time window)
-- from being saved twice. NULLS in playing_area_id/start_time/end_time are
-- coalesced so "no override" collides correctly with another "no override".
create unique index pricing_rules_no_duplicates_idx on pricing_rules (
  facility_sport_id,
  coalesce(playing_area_id, '00000000-0000-0000-0000-000000000000'::uuid),
  day_type,
  coalesce(start_time, '00:00:00'::time),
  coalesce(end_time, '00:00:00'::time)
) where is_active;

alter table pricing_plans enable row level security;
alter table pricing_rules enable row level security;

create policy "pricing_plans_select_members" on pricing_plans for select
  using (is_facility_member(facility_id));
create policy "pricing_plans_write_managers" on pricing_plans for all
  using (has_facility_role(facility_id, array['owner', 'manager']::facility_role[]))
  with check (has_facility_role(facility_id, array['owner', 'manager']::facility_role[]));

create policy "pricing_rules_select_members" on pricing_rules for select
  using (is_facility_member(facility_id));
create policy "pricing_rules_write_managers" on pricing_rules for all
  using (has_facility_role(facility_id, array['owner', 'manager']::facility_role[]))
  with check (has_facility_role(facility_id, array['owner', 'manager']::facility_role[]));

-- ─────────────────────────────────────────────────────────────────────────
-- save_pricing_rules: get-or-create the facility's ACTIVE plan, then
-- replace its rules wholesale (delete + reinsert) in one transaction — the
-- same replace strategy 0004's save_operating_schedule uses, so repeated
-- saves never duplicate or leave orphaned rules. Rejects overlapping
-- time-bounded rules within the same (facility_sport_id, playing_area_id,
-- day_type) scope before committing.
-- ─────────────────────────────────────────────────────────────────────────
create function save_pricing_rules(
  p_facility_id uuid,
  p_plan_name text,
  p_rules jsonb
) returns pricing_plans
language plpgsql
as $$
declare
  plan pricing_plans;
  rule jsonb;
  scope_key text;
  prev_scope text;
  prev_start time;
  prev_end time;
  cur_start time;
  cur_end time;
  sorted_rules jsonb;
begin
  select * into plan from pricing_plans where facility_id = p_facility_id and status = 'ACTIVE';

  if plan.id is null then
    insert into pricing_plans (facility_id, name, currency)
    values (p_facility_id, coalesce(p_plan_name, 'Standard Pricing'), 'INR')
    returning * into plan;
  else
    update pricing_plans set updated_at = now() where id = plan.id returning * into plan;
  end if;

  -- Overlap check: within each (facility_sport_id, playing_area_id, day_type)
  -- scope, no two non-full-day windows may overlap.
  sorted_rules := (
    select jsonb_agg(r order by
      r ->> 'facilitySportId', coalesce(r ->> 'playingAreaId', ''), r ->> 'dayType', r ->> 'startTime')
    from jsonb_array_elements(p_rules) r
    where not coalesce((r ->> 'coversFullDay')::boolean, true)
  );

  prev_scope := null;
  for rule in select * from jsonb_array_elements(coalesce(sorted_rules, '[]'::jsonb))
  loop
    scope_key := (rule ->> 'facilitySportId') || '|' || coalesce(rule ->> 'playingAreaId', '') || '|' || (rule ->> 'dayType');
    cur_start := (rule ->> 'startTime')::time;
    cur_end := (rule ->> 'endTime')::time;

    if scope_key = prev_scope and cur_start < prev_end and prev_start < cur_end then
      raise exception 'Pricing periods cannot overlap.' using errcode = '23514';
    end if;

    prev_scope := scope_key;
    prev_start := cur_start;
    prev_end := cur_end;
  end loop;

  delete from pricing_rules where pricing_plan_id = plan.id;

  for rule in select * from jsonb_array_elements(p_rules)
  loop
    insert into pricing_rules (
      pricing_plan_id, facility_id, facility_sport_id, playing_area_id,
      day_type, covers_full_day, start_time, end_time,
      amount_minor, currency, pricing_unit, priority
    ) values (
      plan.id, p_facility_id,
      (rule ->> 'facilitySportId')::uuid,
      nullif(rule ->> 'playingAreaId', '')::uuid,
      coalesce(rule ->> 'dayType', 'ALL_DAYS'),
      coalesce((rule ->> 'coversFullDay')::boolean, true),
      nullif(rule ->> 'startTime', '')::time,
      nullif(rule ->> 'endTime', '')::time,
      (rule ->> 'amountMinor')::integer,
      coalesce(rule ->> 'currency', 'INR'),
      coalesce(rule ->> 'pricingUnit', 'PER_HOUR'),
      coalesce((rule ->> 'priority')::integer, case when rule ->> 'playingAreaId' is not null then 10 else 0 end)
    );
  end loop;

  return plan;
end;
$$;