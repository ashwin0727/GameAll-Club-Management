-- ═══════════════════════════════════════════════════════════════════════════
-- Operating Hours
--
--   facilities → operating_schedules (scope: FACILITY, one per facility)
--   courts     → operating_schedules (scope: PLAYING_AREA, optional override)
--                        ↓
--                operating_days (0=Sunday..6=Saturday, matches JS Date#getDay)
--                        ↓
--                operating_time_slots
--
-- facility_id is denormalized onto every table here (matching 0001's own
-- stated convention) so RLS never needs more than one membership lookup.
-- ═══════════════════════════════════════════════════════════════════════════

create table operating_schedules (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references facilities (id) on delete cascade,
  scope_type text not null check (scope_type in ('FACILITY', 'PLAYING_AREA')),
  playing_area_id uuid references courts (id) on delete cascade,
  timezone text not null default 'Asia/Kolkata',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint operating_schedules_scope_check check (
    (scope_type = 'FACILITY' and playing_area_id is null)
    or (scope_type = 'PLAYING_AREA' and playing_area_id is not null)
  )
);
-- At most one FACILITY-scope schedule per facility, and at most one
-- schedule per playing area override — partial indexes because a plain
-- unique(facility_id, playing_area_id) would let NULL playing_area_id
-- repeat (Postgres treats NULLs as distinct in unique constraints).
create unique index operating_schedules_facility_scope_idx
  on operating_schedules (facility_id) where scope_type = 'FACILITY';
create unique index operating_schedules_playing_area_scope_idx
  on operating_schedules (playing_area_id) where scope_type = 'PLAYING_AREA';

create table operating_days (
  id uuid primary key default gen_random_uuid(),
  schedule_id uuid not null references operating_schedules (id) on delete cascade,
  facility_id uuid not null references facilities (id) on delete cascade,
  day_of_week smallint not null check (day_of_week between 0 and 6),
  is_closed boolean not null default false,
  is_24_hours boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (schedule_id, day_of_week)
);
create index operating_days_schedule_id_idx on operating_days (schedule_id);
create index operating_days_facility_id_idx on operating_days (facility_id);

create table operating_time_slots (
  id uuid primary key default gen_random_uuid(),
  operating_day_id uuid not null references operating_days (id) on delete cascade,
  facility_id uuid not null references facilities (id) on delete cascade,
  start_time time not null,
  end_time time not null,
  crosses_midnight boolean not null default false,
  display_order integer not null default 0,
  created_at timestamptz not null default now(),
  constraint operating_time_slots_distinct_check check (start_time <> end_time)
);
create index operating_time_slots_operating_day_id_idx on operating_time_slots (operating_day_id);
create index operating_time_slots_facility_id_idx on operating_time_slots (facility_id);

alter table operating_schedules enable row level security;
alter table operating_days enable row level security;
alter table operating_time_slots enable row level security;

create policy "operating_schedules_select_members" on operating_schedules for select
  using (is_facility_member(facility_id));
create policy "operating_schedules_write_managers" on operating_schedules for all
  using (has_facility_role(facility_id, array['owner', 'manager']::facility_role[]))
  with check (has_facility_role(facility_id, array['owner', 'manager']::facility_role[]));

create policy "operating_days_select_members" on operating_days for select
  using (is_facility_member(facility_id));
create policy "operating_days_write_managers" on operating_days for all
  using (has_facility_role(facility_id, array['owner', 'manager']::facility_role[]))
  with check (has_facility_role(facility_id, array['owner', 'manager']::facility_role[]));

create policy "operating_time_slots_select_members" on operating_time_slots for select
  using (is_facility_member(facility_id));
create policy "operating_time_slots_write_managers" on operating_time_slots for all
  using (has_facility_role(facility_id, array['owner', 'manager']::facility_role[]))
  with check (has_facility_role(facility_id, array['owner', 'manager']::facility_role[]));

-- ─────────────────────────────────────────────────────────────────────────
-- save_operating_schedule: get-or-create the schedule row, then replace its
-- days/slots wholesale (delete + reinsert) in one transaction. Avoids
-- duplicate slots on repeated saves and never leaves a partial write if
-- validation failed client-side before this was even called.
-- ─────────────────────────────────────────────────────────────────────────
create function save_operating_schedule(
  p_facility_id uuid,
  p_scope_type text,
  p_playing_area_id uuid,
  p_days jsonb
) returns operating_schedules
language plpgsql
as $$
declare
  result operating_schedules;
  day jsonb;
  slot jsonb;
  new_day_id uuid;
begin
  if p_scope_type = 'FACILITY' then
    select * into result from operating_schedules
      where facility_id = p_facility_id and scope_type = 'FACILITY';
  else
    select * into result from operating_schedules
      where playing_area_id = p_playing_area_id and scope_type = 'PLAYING_AREA';
  end if;

  if result.id is null then
    insert into operating_schedules (facility_id, scope_type, playing_area_id, timezone)
    values (
      p_facility_id, p_scope_type, p_playing_area_id,
      coalesce((select timezone from facilities where id = p_facility_id), 'Asia/Kolkata')
    )
    returning * into result;
  else
    update operating_schedules set updated_at = now() where id = result.id returning * into result;
  end if;

  delete from operating_days where schedule_id = result.id;

  for day in select * from jsonb_array_elements(p_days)
  loop
    insert into operating_days (schedule_id, facility_id, day_of_week, is_closed, is_24_hours)
    values (
      result.id, p_facility_id,
      (day ->> 'dayOfWeek')::smallint,
      coalesce((day ->> 'isClosed')::boolean, false),
      coalesce((day ->> 'is24Hours')::boolean, false)
    )
    returning id into new_day_id;

    for slot in select * from jsonb_array_elements(coalesce(day -> 'slots', '[]'::jsonb))
    loop
      insert into operating_time_slots (operating_day_id, facility_id, start_time, end_time, crosses_midnight, display_order)
      values (
        new_day_id, p_facility_id,
        (slot ->> 'startTime')::time, (slot ->> 'endTime')::time,
        coalesce((slot ->> 'crossesMidnight')::boolean, false),
        coalesce((slot ->> 'displayOrder')::integer, 0)
      );
    end loop;
  end loop;

  return result;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- delete_playing_area_override: removes a playing area's custom schedule,
-- returning it to inheriting the facility schedule.
-- ─────────────────────────────────────────────────────────────────────────
create function delete_playing_area_override(p_playing_area_id uuid) returns void
language sql
as $$
  delete from operating_schedules
  where playing_area_id = p_playing_area_id and scope_type = 'PLAYING_AREA';
$$;