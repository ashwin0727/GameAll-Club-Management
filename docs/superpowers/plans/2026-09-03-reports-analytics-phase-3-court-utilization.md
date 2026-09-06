# Reports & Analytics — Phase 3: Court Utilization — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans. Steps use `- [ ]`.

> **Status: implemented (2026-09-04), pending user verification + commit.** Notes:
> - `<Heatmap>` takes `HeatmapCell` imported from `../types` (no local `HeatCell`), per the self-review.
> - The overall-utilization figure is rendered as one template-string node (`` `${pct}%` ``) — `{pct}%` splits into two text nodes and breaks `findByText`. The test scopes its query with `{ selector: "p" }` because the by-sport table row can also read the same %.
> - **`next build` was NOT run** (new standing rule: no `next build` while `next dev` is up — see [[feedback-test-before-commit-and-no-next-build-in-dev-loop]]). Verified via `tsc --noEmit` (whole project) + `next lint` + `vitest` (75 reports tests render the full report incl. charts/heatmap) + dev-server has no compile errors.
> - Full suite this run: **604/604** (the pre-existing `courts-setup`/`onboarding` flakes happened to pass).

**Goal:** `/reports/court-utilization` — overall utilization, per-court and per-sport utilization (sortable, with supporting tables), a peak-hours chart, and a day×hour demand heatmap. All from the facility's real operating-hours model.

**Architecture:** `0057` adds the availability primitives — one window→(dow,hour,minutes) expander and two per-court "minutes by cell" functions (open hours, booked time) that read the *same* `operating_schedules`/`operating_days`/`operating_time_slots` tables with the *same* per-court-override→facility precedence as `booking_window_fits_operating_hours`. `0059` builds five report RPCs on top. `<CourtUtilizationReport>` follows the Phase 2 assembly pattern; a new shared `<Heatmap>` (labels + tooltip + intensity, never colour alone) lands for reuse.

**Tech Stack:** PostgreSQL (Supabase), Next.js 15 / React 19, TypeScript, Recharts, Vitest.

**Spec:** `docs/superpowers/specs/2026-09-03-reports-analytics-design.md` §12–16, §42, §51.

## Global Constraints

- Branch `feat/reports-analytics`. Phases 1–2 committed (`17bb3e1`, `5836b03`); `distDir` fix `7652e98`.
- **No parallel availability engine.** The new functions read only `operating_schedules` / `operating_days` / `operating_time_slots` (+ `courts`, `facilities` for tz), with **PLAYING_AREA-scope override first, then FACILITY scope** — identical precedence to `booking_window_fits_operating_hours` (`0007`). Day math identical to `summary.ts::operatingMinutesForDay`: closed → 0; 24h → 1440; else Σ slot `(end−start, +1440 if crosses_midnight or end≤start)`.
- **There is no maintenance / blocked-period table.** Bookable time = open time (spec §51 — "moot here, documented as such").
- **Booked time** = non-cancelled `bookings` (`status <> 'cancelled'`) + `membership_sessions` that have ≥1 `CONFIRMED` `membership_session_bookings` (the session occupies its court for its whole `[start_time, end_time)` on `session_date`). Matches `summary.ts::toUtilizationBookings`. Durations are **clipped to the selected range** (a booking straddling the boundary counts only its in-range minutes).
- **Utilization % = booked ÷ open, capped at 100**, `round(…, 1)`; `0` when open is `0`. Booked is **not** clipped to open hours (a booking outside operating hours still counts, then the cap applies) — matches `summary.ts::computeUtilizationPercent`.
- **`membership_batches` enforce `end_time > start_time`** (`0014`) so sessions never cross midnight — no special-casing needed for them. Operating-hours slots *can* cross midnight (`crosses_midnight`).
- Timezone: the facility's `timezone` (default `Asia/Kolkata`), for every local-calendar and hour-of-day computation.
- Migration file immutable — `0057` and `0059` are two new files; never edit earlier migrations.
- `database.types.ts` hand-maintained — add a `Functions` entry per client-called RPC (`0057` helpers are **not** client-called; only the five `0059` RPCs are).
- No SQL harness — `0057`/`0059` verified by the manual task (Task 7).
- Per phase: `npm run typecheck` (no *new* errors), `npx next lint --dir src`, `npx vitest run`. **No `next build` while `next dev` runs.**
- Commit only after verification + explicit user go-ahead.

---

## File Structure

| File | Responsibility |
|---|---|
| `supabase/migrations/0057_analytics_availability.sql` | **Create.** `analytics_window_cells`, `analytics_court_open_minutes_by_cell`, `analytics_court_booked_minutes_by_cell`. |
| `supabase/migrations/0059_analytics_utilization.sql` | **Create.** `get_overall_utilization`, `get_court_utilization`, `get_sport_utilization`, `get_peak_hours`, `get_demand_heatmap`. |
| `src/types/database.types.ts` | **Modify.** Five `Functions` entries (the `0059` RPCs). |
| `src/features/reports/types.ts` | **Modify.** `OverallUtilization`, `CourtUtilizationRow`, `SportUtilizationRow`, `PeakHourRow`, `HeatmapCell`. |
| `src/services/reports/reports.service.ts` | **Modify.** Five methods. |
| `src/services/reports/supabase-reports.service.ts` | **Modify.** Five RPC calls + mapping. |
| `src/services/reports/supabase-reports.service.test.ts` | **Modify.** Per-method contract tests. |
| `src/test/fakes/fake-reports-service.ts` | **Modify.** Five fields + param-less methods. |
| `src/features/reports/components/heatmap.tsx` | **Create.** `<Heatmap>` — day×hour grid, `title` tooltip per cell, intensity + a text label, `<table>` semantics. |
| `src/features/reports/components/heatmap.test.tsx` | **Create.** |
| `src/features/reports/components/peak-hours-chart.tsx` | **Create.** Recharts bar chart of demand % by hour. |
| `src/features/reports/components/court-utilization-report.tsx` | **Rewrite.** The assembled report. |
| `src/features/reports/components/court-utilization-report.test.tsx` | **Create.** |

---

## Task 1: Migration `0057` — availability primitives

**Files:** Create `supabase/migrations/0057_analytics_availability.sql`

**Interfaces — Produces:**
- `analytics_window_cells(p_start timestamptz, p_end timestamptz, p_tz text)` → `table (dow smallint, hour smallint, minutes numeric)` — splits `[p_start, p_end)` into per-local-(day-of-week, hour-of-day) minute contributions. `language sql stable`.
- `analytics_court_open_minutes_by_cell(p_court_id uuid, p_range tstzrange)` → `table (dow smallint, hour smallint, minutes numeric)` — open (bookable) minutes for one court over `p_range`, override→facility precedence, clipped to `p_range`. `language plpgsql stable`.
- `analytics_court_booked_minutes_by_cell(p_court_id uuid, p_range tstzrange)` → `table (dow smallint, hour smallint, minutes numeric)` — non-cancelled bookings + used membership sessions on the court, each window clipped to `p_range` and expanded via `analytics_window_cells`. `language plpgsql stable`.

These are internal helpers — **no `grant execute`** beyond the default, and **no `has_facility_role` check** (they are called only from `0059`'s RPCs, which check). They take no facility id; RLS on the underlying tables is not in play because `0059` runs `stable` (invoker) and pre-checks the role.

- [ ] **Step 1: Write the migration**

```sql
-- ═══════════════════════════════════════════════════════════════════════════
-- Reports & Analytics — Phase 3a: availability primitives.
--
-- The range-aggregate companions to booking_window_fits_operating_hours
-- (0007). Same tables, same precedence (PLAYING_AREA override, else
-- FACILITY), same day math as summary.ts::operatingMinutesForDay. There is
-- no maintenance/blocked model in GameAll, so open time == bookable time.
--
-- Every figure is "minutes", bucketed by local (day-of-week, hour-of-day)
-- so one primitive feeds court/sport utilisation, peak hours AND the
-- demand heatmap. Internal — called only from 0059's RPCs, which do the
-- has_facility_role check.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function analytics_window_cells(
  p_start timestamptz,
  p_end timestamptz,
  p_tz text
) returns table (dow smallint, hour smallint, minutes numeric)
language sql
stable
as $$
  with b as (
    select
      (p_start at time zone coalesce(p_tz, 'Asia/Kolkata')) as ls,
      (p_end   at time zone coalesce(p_tz, 'Asia/Kolkata')) as le
  ),
  hrs as (
    select generate_series(date_trunc('hour', b.ls), b.le - interval '1 microsecond', interval '1 hour') as h,
           b.ls, b.le
    from b
    where b.le > b.ls
  )
  select
    extract(dow  from h)::smallint,
    extract(hour from h)::smallint,
    (extract(epoch from (least(le, h + interval '1 hour') - greatest(ls, h))) / 60.0)::numeric
  from hrs
  where least(le, h + interval '1 hour') > greatest(ls, h);
$$;


create or replace function analytics_court_open_minutes_by_cell(
  p_court_id uuid,
  p_range tstzrange
) returns table (dow smallint, hour smallint, minutes numeric)
language plpgsql
stable
as $$
declare
  v_facility uuid;
  tz text;
  v_schedule uuid;
  start_d date;
  end_d date;
  d date;
  dow_ smallint;
  day_rec operating_days;
  slot operating_time_slots;
  win_start timestamptz;
  win_end timestamptz;
begin
  select c.facility_id into v_facility from courts c where c.id = p_court_id;
  if v_facility is null then return; end if;
  select coalesce(f.timezone, 'Asia/Kolkata') into tz from facilities f where f.id = v_facility;

  select os.id into v_schedule from operating_schedules os
    where os.playing_area_id = p_court_id and os.scope_type = 'PLAYING_AREA';
  if v_schedule is null then
    select os.id into v_schedule from operating_schedules os
      where os.facility_id = v_facility and os.scope_type = 'FACILITY';
  end if;
  if v_schedule is null then return; end if;

  start_d := (lower(p_range) at time zone tz)::date;
  end_d := ((upper(p_range) - interval '1 microsecond') at time zone tz)::date;

  for d in select generate_series(start_d, end_d, interval '1 day')::date loop
    dow_ := extract(dow from d)::smallint;
    select * into day_rec from operating_days od where od.schedule_id = v_schedule and od.day_of_week = dow_;
    if day_rec.id is null or day_rec.is_closed then continue; end if;

    if day_rec.is_24_hours then
      win_start := greatest(d::timestamp at time zone tz, lower(p_range));
      win_end := least((d + 1)::timestamp at time zone tz, upper(p_range));
      if win_end > win_start then
        return query select w.dow, w.hour, w.minutes from analytics_window_cells(win_start, win_end, tz) w;
      end if;
      continue;
    end if;

    for slot in select * from operating_time_slots ots where ots.operating_day_id = day_rec.id loop
      win_start := (d::timestamp + slot.start_time) at time zone tz;
      if slot.crosses_midnight or slot.end_time <= slot.start_time then
        win_end := ((d + 1)::timestamp + slot.end_time) at time zone tz;
      else
        win_end := (d::timestamp + slot.end_time) at time zone tz;
      end if;
      win_start := greatest(win_start, lower(p_range));
      win_end := least(win_end, upper(p_range));
      if win_end > win_start then
        return query select w.dow, w.hour, w.minutes from analytics_window_cells(win_start, win_end, tz) w;
      end if;
    end loop;
  end loop;
end;
$$;


create or replace function analytics_court_booked_minutes_by_cell(
  p_court_id uuid,
  p_range tstzrange
) returns table (dow smallint, hour smallint, minutes numeric)
language plpgsql
stable
as $$
declare
  v_facility uuid;
  tz text;
  rec record;
  win_start timestamptz;
  win_end timestamptz;
begin
  select c.facility_id into v_facility from courts c where c.id = p_court_id;
  if v_facility is null then return; end if;
  select coalesce(f.timezone, 'Asia/Kolkata') into tz from facilities f where f.id = v_facility;

  -- Ad-hoc bookings — any non-cancelled row overlapping the range.
  for rec in
    select b.start_time as s, b.end_time as e
    from bookings b
    where b.court_id = p_court_id
      and b.status <> 'cancelled'
      and tstzrange(b.start_time, b.end_time) && p_range
  loop
    win_start := greatest(rec.s, lower(p_range));
    win_end := least(rec.e, upper(p_range));
    if win_end > win_start then
      return query select w.dow, w.hour, w.minutes from analytics_window_cells(win_start, win_end, tz) w;
    end if;
  end loop;

  -- Membership sessions that were actually used (>= 1 confirmed slot).
  for rec in
    select
      (ms.session_date::timestamp + ms.start_time) at time zone tz as s,
      (ms.session_date::timestamp + ms.end_time)   at time zone tz as e
    from membership_sessions ms
    where ms.court_id = p_court_id
      and exists (
        select 1 from membership_session_bookings msb
        where msb.session_id = ms.id and msb.status = 'CONFIRMED'
      )
  loop
    if not (tstzrange(rec.s, rec.e) && p_range) then continue; end if;
    win_start := greatest(rec.s, lower(p_range));
    win_end := least(rec.e, upper(p_range));
    if win_end > win_start then
      return query select w.dow, w.hour, w.minutes from analytics_window_cells(win_start, win_end, tz) w;
    end if;
  end loop;
end;
$$;
```

- [ ] **Step 2: Parse-sanity**

Run: `node -e "const s=require('fs').readFileSync('supabase/migrations/0057_analytics_availability.sql','utf8'); for (const f of ['analytics_window_cells','analytics_court_open_minutes_by_cell','analytics_court_booked_minutes_by_cell']) if(!s.includes('function '+f)) throw new Error('missing '+f); console.log('ok')"`

---

## Task 2: Migration `0059` — utilization RPCs

**Files:** Create `supabase/migrations/0059_analytics_utilization.sql`

**Interfaces — Produces** (all: `p_facility_id, p_preset, p_start_date, p_end_date, p_facility_sport_id, p_court_id`; `has_facility_role` → `42501`; dates via `resolve_finance_date_range`; `grant execute … to authenticated`):
- `get_overall_utilization(…)` → `table (open_minutes bigint, booked_minutes bigint, utilization_pct numeric)`
- `get_court_utilization(…)` → `table (court_id uuid, court_name text, facility_sport_id uuid, sport_name text, open_minutes integer, booked_minutes integer, utilization_pct numeric)` — one row per non-archived court in scope, ordered by name (client re-sorts).
- `get_sport_utilization(…)` → `table (facility_sport_id uuid, sport_name text, open_minutes bigint, booked_minutes bigint, utilization_pct numeric)` — one row per active facility sport in scope.
- `get_peak_hours(…)` → `table (hour smallint, open_minutes integer, booked_minutes integer, demand_pct numeric)` — only hours with `open_minutes > 0`, ordered by hour.
- `get_demand_heatmap(…)` → `table (dow smallint, hour smallint, open_minutes integer, booked_minutes integer, demand_pct numeric)` — only cells with `open_minutes > 0`.

- [ ] **Step 1: Write the migration**

```sql
-- ═══════════════════════════════════════════════════════════════════════════
-- Reports & Analytics — Phase 3b: Court Utilization.
--
-- booked ÷ open, per the availability primitives in 0057. "open" is the
-- facility's operating hours (no maintenance model); "booked" is
-- non-cancelled bookings + membership sessions with >=1 confirmed slot,
-- clipped to the selected range. Utilisation is capped at 100% (a booking
-- outside operating hours still counts as booked time — matches
-- summary.ts::computeUtilizationPercent).
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function get_court_utilization(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_facility_sport_id uuid default null,
  p_court_id uuid default null
) returns table (
  court_id uuid,
  court_name text,
  facility_sport_id uuid,
  sport_name text,
  open_minutes integer,
  booked_minutes integer,
  utilization_pct numeric
)
language plpgsql
stable
as $$
declare
  range_ tstzrange;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  range_ := resolve_finance_date_range(p_facility_id, p_preset, p_start_date, p_end_date);

  return query
  select
    c.id,
    c.name,
    c.facility_sport_id,
    coalesce(fs.custom_sport_name, sp.name),
    round(o.open_min)::integer,
    round(b.booked_min)::integer,
    case when o.open_min > 0
      then least(100, round((b.booked_min / o.open_min) * 100, 1))
      else 0 end
  from courts c
  join facility_sports fs on fs.id = c.facility_sport_id
  join sports sp on sp.id = fs.sport_id
  cross join lateral (
    select coalesce(sum(minutes), 0) as open_min from analytics_court_open_minutes_by_cell(c.id, range_)
  ) o
  cross join lateral (
    select coalesce(sum(minutes), 0) as booked_min from analytics_court_booked_minutes_by_cell(c.id, range_)
  ) b
  where c.facility_id = p_facility_id
    and not c.archived
    and (p_facility_sport_id is null or c.facility_sport_id = p_facility_sport_id)
    and (p_court_id is null or c.id = p_court_id)
  order by c.name;
end;
$$;

grant execute on function get_court_utilization(uuid, text, date, date, uuid, uuid) to authenticated;


create or replace function get_sport_utilization(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_facility_sport_id uuid default null,
  p_court_id uuid default null
) returns table (
  facility_sport_id uuid,
  sport_name text,
  open_minutes bigint,
  booked_minutes bigint,
  utilization_pct numeric
)
language plpgsql
stable
as $$
declare
  range_ tstzrange;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  range_ := resolve_finance_date_range(p_facility_id, p_preset, p_start_date, p_end_date);

  return query
  with per_court as (
    select
      c.facility_sport_id,
      coalesce(fs.custom_sport_name, sp.name) as sport_name,
      (select coalesce(sum(minutes), 0) from analytics_court_open_minutes_by_cell(c.id, range_)) as open_min,
      (select coalesce(sum(minutes), 0) from analytics_court_booked_minutes_by_cell(c.id, range_)) as booked_min
    from courts c
    join facility_sports fs on fs.id = c.facility_sport_id
    join sports sp on sp.id = fs.sport_id
    where c.facility_id = p_facility_id
      and not c.archived
      and (p_facility_sport_id is null or c.facility_sport_id = p_facility_sport_id)
      and (p_court_id is null or c.id = p_court_id)
  )
  select
    pc.facility_sport_id,
    pc.sport_name,
    round(sum(pc.open_min))::bigint,
    round(sum(pc.booked_min))::bigint,
    case when sum(pc.open_min) > 0
      then least(100, round((sum(pc.booked_min) / sum(pc.open_min)) * 100, 1))
      else 0 end
  from per_court pc
  group by pc.facility_sport_id, pc.sport_name
  order by pc.sport_name;
end;
$$;

grant execute on function get_sport_utilization(uuid, text, date, date, uuid, uuid) to authenticated;


create or replace function get_overall_utilization(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_facility_sport_id uuid default null,
  p_court_id uuid default null
) returns table (
  open_minutes bigint,
  booked_minutes bigint,
  utilization_pct numeric
)
language plpgsql
stable
as $$
declare
  range_ tstzrange;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  range_ := resolve_finance_date_range(p_facility_id, p_preset, p_start_date, p_end_date);

  return query
  with per_court as (
    select
      (select coalesce(sum(minutes), 0) from analytics_court_open_minutes_by_cell(c.id, range_)) as open_min,
      (select coalesce(sum(minutes), 0) from analytics_court_booked_minutes_by_cell(c.id, range_)) as booked_min
    from courts c
    where c.facility_id = p_facility_id
      and not c.archived
      and (p_facility_sport_id is null or c.facility_sport_id = p_facility_sport_id)
      and (p_court_id is null or c.id = p_court_id)
  )
  select
    round(coalesce(sum(open_min), 0))::bigint,
    round(coalesce(sum(booked_min), 0))::bigint,
    case when coalesce(sum(open_min), 0) > 0
      then least(100, round((sum(booked_min) / sum(open_min)) * 100, 1))
      else 0 end
  from per_court;
end;
$$;

grant execute on function get_overall_utilization(uuid, text, date, date, uuid, uuid) to authenticated;


create or replace function get_peak_hours(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_facility_sport_id uuid default null,
  p_court_id uuid default null
) returns table (
  hour smallint,
  open_minutes integer,
  booked_minutes integer,
  demand_pct numeric
)
language plpgsql
stable
as $$
declare
  range_ tstzrange;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  range_ := resolve_finance_date_range(p_facility_id, p_preset, p_start_date, p_end_date);

  return query
  with scope as (
    select c.id
    from courts c
    where c.facility_id = p_facility_id
      and not c.archived
      and (p_facility_sport_id is null or c.facility_sport_id = p_facility_sport_id)
      and (p_court_id is null or c.id = p_court_id)
  ),
  open_c as (
    select w.hour, sum(w.minutes) as m
    from scope cross join lateral analytics_court_open_minutes_by_cell(scope.id, range_) w
    group by w.hour
  ),
  book_c as (
    select w.hour, sum(w.minutes) as m
    from scope cross join lateral analytics_court_booked_minutes_by_cell(scope.id, range_) w
    group by w.hour
  )
  select
    o.hour,
    round(o.m)::integer,
    round(coalesce(b.m, 0))::integer,
    least(100, round((coalesce(b.m, 0) / o.m) * 100, 1))
  from open_c o
  left join book_c b on b.hour = o.hour
  where o.m > 0
  order by o.hour;
end;
$$;

grant execute on function get_peak_hours(uuid, text, date, date, uuid, uuid) to authenticated;


create or replace function get_demand_heatmap(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_facility_sport_id uuid default null,
  p_court_id uuid default null
) returns table (
  dow smallint,
  hour smallint,
  open_minutes integer,
  booked_minutes integer,
  demand_pct numeric
)
language plpgsql
stable
as $$
declare
  range_ tstzrange;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  range_ := resolve_finance_date_range(p_facility_id, p_preset, p_start_date, p_end_date);

  return query
  with scope as (
    select c.id
    from courts c
    where c.facility_id = p_facility_id
      and not c.archived
      and (p_facility_sport_id is null or c.facility_sport_id = p_facility_sport_id)
      and (p_court_id is null or c.id = p_court_id)
  ),
  open_c as (
    select w.dow, w.hour, sum(w.minutes) as m
    from scope cross join lateral analytics_court_open_minutes_by_cell(scope.id, range_) w
    group by w.dow, w.hour
  ),
  book_c as (
    select w.dow, w.hour, sum(w.minutes) as m
    from scope cross join lateral analytics_court_booked_minutes_by_cell(scope.id, range_) w
    group by w.dow, w.hour
  )
  select
    o.dow,
    o.hour,
    round(o.m)::integer,
    round(coalesce(b.m, 0))::integer,
    least(100, round((coalesce(b.m, 0) / o.m) * 100, 1))
  from open_c o
  left join book_c b on b.dow = o.dow and b.hour = o.hour
  where o.m > 0
  order by o.dow, o.hour;
end;
$$;

grant execute on function get_demand_heatmap(uuid, text, date, date, uuid, uuid) to authenticated;
```

- [ ] **Step 2: Parse-sanity** — the five function names present.

---

## Task 3: types + `database.types.ts` + service + fake

**Files:** modify `src/features/reports/types.ts`, `src/types/database.types.ts`, `src/services/reports/*`, `src/test/fakes/fake-reports-service.ts`

- [ ] **Step 1: `types.ts`** — append:

```ts
// ─── Phase 3: Court Utilization ──────────────────────────────────────────

export interface OverallUtilization {
  openMinutes: number;
  bookedMinutes: number;
  utilizationPct: number;
}

export interface CourtUtilizationRow {
  courtId: string;
  courtName: string;
  facilitySportId: string;
  sportName: string;
  openMinutes: number;
  bookedMinutes: number;
  utilizationPct: number;
}

export interface SportUtilizationRow {
  facilitySportId: string;
  sportName: string;
  openMinutes: number;
  bookedMinutes: number;
  utilizationPct: number;
}

export interface PeakHourRow {
  hour: number;
  openMinutes: number;
  bookedMinutes: number;
  demandPct: number;
}

export interface HeatmapCell {
  dow: number;
  hour: number;
  openMinutes: number;
  bookedMinutes: number;
  demandPct: number;
}
```

- [ ] **Step 2: `database.types.ts`** — five entries after `get_booking_source_split`, each with `Args: { p_facility_id: string; p_preset?: string; p_start_date?: string | null; p_end_date?: string | null; p_facility_sport_id?: string | null; p_court_id?: string | null }` and:
  - `get_overall_utilization` Returns `{ open_minutes: number; booked_minutes: number; utilization_pct: number }[]`
  - `get_court_utilization` Returns `{ court_id: string; court_name: string; facility_sport_id: string; sport_name: string; open_minutes: number; booked_minutes: number; utilization_pct: number }[]`
  - `get_sport_utilization` Returns `{ facility_sport_id: string; sport_name: string; open_minutes: number; booked_minutes: number; utilization_pct: number }[]`
  - `get_peak_hours` Returns `{ hour: number; open_minutes: number; booked_minutes: number; demand_pct: number }[]`
  - `get_demand_heatmap` Returns `{ dow: number; hour: number; open_minutes: number; booked_minutes: number; demand_pct: number }[]`

- [ ] **Step 3: `reports.service.ts`** — add to the interface:

```ts
  getOverallUtilization(filter: AnalyticsFilter): Promise<OverallUtilization>;
  getCourtUtilization(filter: AnalyticsFilter): Promise<CourtUtilizationRow[]>;
  getSportUtilization(filter: AnalyticsFilter): Promise<SportUtilizationRow[]>;
  getPeakHours(filter: AnalyticsFilter): Promise<PeakHourRow[]>;
  getDemandHeatmap(filter: AnalyticsFilter): Promise<HeatmapCell[]>;
```

- [ ] **Step 4: `supabase-reports.service.ts`** — five methods, each `this.supabase.rpc("<name>", this.baseArgs(filter))`, snake→camel map (`open_minutes`→`openMinutes` etc.), `getOverallUtilization` reads `data?.[0]` and throws `mapError` if absent. Same `mapError` (already handles `Not authorized`→`REPORTS_ACCESS_DENIED`).

- [ ] **Step 5: `supabase-reports.service.test.ts`** — add a `describe` block per method: assert RPC name + `baseArgs` shape (incl. `p_facility_sport_id` when the filter carries a sport) + row mapping. One `REPORTS_ACCESS_DENIED` case is enough (shared `mapError` is already covered).

Example:

```ts
describe("SupabaseReportsService.getCourtUtilization", () => {
  it("calls get_court_utilization and maps rows", async () => {
    const rpc = vi.fn(async () => ({
      data: [{ court_id: "c1", court_name: "Court 1", facility_sport_id: "fs1", sport_name: "Badminton", open_minutes: 600, booked_minutes: 420, utilization_pct: 70 }],
      error: null,
    }));
    const service = new SupabaseReportsService({ rpc } as never);
    const rows = await service.getCourtUtilization({ facilityId: "fac-1", preset: "THIS_MONTH" });
    expect(rpc).toHaveBeenCalledWith("get_court_utilization", expect.objectContaining({ p_facility_id: "fac-1" }));
    expect(rows).toEqual([{ courtId: "c1", courtName: "Court 1", facilitySportId: "fs1", sportName: "Badminton", openMinutes: 600, bookedMinutes: 420, utilizationPct: 70 }]);
  });
});

describe("SupabaseReportsService.getOverallUtilization", () => {
  it("reads the single row", async () => {
    const rpc = vi.fn(async () => ({ data: [{ open_minutes: 1000, booked_minutes: 680, utilization_pct: 68 }], error: null }));
    const service = new SupabaseReportsService({ rpc } as never);
    expect(await service.getOverallUtilization({ facilityId: "fac-1", preset: "THIS_MONTH" })).toEqual({
      openMinutes: 1000, bookedMinutes: 680, utilizationPct: 68,
    });
  });
});
```

- [ ] **Step 6: `fake-reports-service.ts`** — add fields (`overallUtilization: OverallUtilization = { openMinutes: 0, bookedMinutes: 0, utilizationPct: 0 }`, `courtUtilization: CourtUtilizationRow[] = []`, `sportUtilization: SportUtilizationRow[] = []`, `peakHours: PeakHourRow[] = []`, `demandHeatmap: HeatmapCell[] = []`) and five param-less methods returning them (throwing `this.error` first).

- [ ] **Step 7:** `npx vitest run src/services/reports` + `npm run typecheck`.

---

## Task 4: `<Heatmap>` + `<PeakHoursChart>`

**Files:** create `heatmap.tsx` (+test), `peak-hours-chart.tsx`

**Interfaces — Produces:**
- `<Heatmap cells={HeatmapCell[]} />` — a `<table>` with a `<caption className="sr-only">`, day rows (Sun–Sat, `scope="row"`) × hour columns (only hours present in `cells`). Each cell: background opacity ∝ `demandPct`, **text content = the rounded `demandPct`** (never colour alone, spec §16/§54), `title={"<Day> <hour>:00 — <pct>% demand"}`. Hours with no data across all days are omitted.
- `<PeakHoursChart rows={PeakHourRow[]} />` — Recharts `BarChart`, `dataKey="demandPct"`, bar `#5B6CFF`, X = hour (`formatHour(h)` → "5 PM"), Y = `%` (`domain={[0, 100]}`), themed tooltip showing `"<hour>: <pct>% (<booked>/<open> min)"`, `role="img"` + `aria-label="Peak booking hours"`. Empty → muted "No booking activity in this period."

- [ ] **Step 1: `heatmap.test.tsx`**

```tsx
import { describe, expect, it } from "vitest";
import { render, screen } from "@testing-library/react";
import { Heatmap } from "./heatmap";

const cells = [
  { dow: 1, hour: 18, openMinutes: 60, bookedMinutes: 54, demandPct: 90 },
  { dow: 2, hour: 18, openMinutes: 60, bookedMinutes: 30, demandPct: 50 },
];

describe("Heatmap", () => {
  it("renders an accessible grid with the percentage as text (not colour alone)", () => {
    render(<Heatmap cells={cells} />);
    expect(screen.getByRole("table", { name: /demand/i })).toBeInTheDocument();
    expect(screen.getByText("90")).toBeInTheDocument();
    expect(screen.getByRole("rowheader", { name: "Mon" })).toBeInTheDocument();
  });

  it("labels each cell with a descriptive title", () => {
    render(<Heatmap cells={cells} />);
    expect(screen.getByTitle(/Mon 18:00 — 90% demand/)).toBeInTheDocument();
  });

  it("shows an empty message with no cells", () => {
    render(<Heatmap cells={[]} />);
    expect(screen.getByText(/no demand data/i)).toBeInTheDocument();
  });
});
```

- [ ] **Step 2: `heatmap.tsx`**

```tsx
"use client";

const DAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

function formatHour(h: number): string {
  const hour12 = h % 12 === 0 ? 12 : h % 12;
  return `${hour12}${h < 12 ? "am" : "pm"}`;
}

export interface HeatCell {
  dow: number;
  hour: number;
  openMinutes: number;
  bookedMinutes: number;
  demandPct: number;
}

/**
 * Day-of-week × hour-of-day demand grid (spec §16). Encoded three ways so it
 * never relies on colour: cell background opacity, the number printed in the
 * cell, and a descriptive `title`. Only hours that appear in `cells` are
 * shown as columns.
 */
export function Heatmap({ cells }: { cells: HeatCell[] }) {
  if (cells.length === 0) {
    return <p className="py-8 text-center text-sm text-muted-foreground">No demand data for this period.</p>;
  }

  const hours = [...new Set(cells.map((c) => c.hour))].sort((a, b) => a - b);
  const byKey = new Map(cells.map((c) => [`${c.dow}-${c.hour}`, c]));

  return (
    <div className="overflow-x-auto">
      <table className="w-full border-separate border-spacing-0.5 text-center text-xs">
        <caption className="sr-only">Booking demand by day of week and hour of day</caption>
        <thead>
          <tr>
            <th scope="col" className="p-1 text-left font-medium text-muted-foreground"> </th>
            {hours.map((h) => (
              <th key={h} scope="col" className="p-1 font-medium text-muted-foreground">
                {formatHour(h)}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {DAYS.map((day, dow) => (
            <tr key={day}>
              <th scope="row" className="p-1 text-left font-medium text-muted-foreground">
                {day}
              </th>
              {hours.map((h) => {
                const cell = byKey.get(`${dow}-${h}`);
                const pct = cell ? Math.round(cell.demandPct) : null;
                return (
                  <td
                    key={h}
                    className="rounded p-1 tabular-nums"
                    style={{
                      backgroundColor: pct === null ? "var(--muted)" : `rgba(0, 240, 138, ${0.08 + (pct / 100) * 0.8})`,
                      color: pct !== null && pct >= 55 ? "var(--background)" : "var(--foreground)",
                    }}
                    title={
                      cell
                        ? `${day} ${String(h).padStart(2, "0")}:00 — ${pct}% demand (${Math.round(
                            cell.bookedMinutes,
                          )}/${Math.round(cell.openMinutes)} min)`
                        : `${day} ${String(h).padStart(2, "0")}:00 — closed`
                    }
                  >
                    {pct ?? "·"}
                  </td>
                );
              })}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
```

- [ ] **Step 3: run heatmap test — passes.**

- [ ] **Step 4: `peak-hours-chart.tsx`** — Recharts `BarChart` per the interface. Model on `booking-trend-chart.tsx` (same container/axis/tooltip styling); `<Bar dataKey="demandPct" fill="#5B6CFF" radius={[3,3,0,0]} />`, `<YAxis domain={[0,100]} tickFormatter={(v)=>`${v}%`} width={40} />`, `<XAxis dataKey="hour" tickFormatter={formatHourLabel} />` where `formatHourLabel(h)` → `"5 PM"`.

- [ ] **Step 5:** `npx vitest run src/features/reports/components/heatmap.test.tsx` + `npm run typecheck`.

---

## Task 5: `<CourtUtilizationReport>`

**Files:** rewrite `court-utilization-report.tsx`; create `court-utilization-report.test.tsx`

**Behaviour** — mirrors `booking-report.tsx`:
- `useAnalyticsFilter` → `load()` = `Promise.all([getOverallUtilization, getCourtUtilization, getSportUtilization, getPeakHours, getDemandHeatmap])`. No previous-period call this phase.
- `status`: `loading` → `error` on any rejection (`onRetry`) → `empty` when `overall.openMinutes === 0` (facility has no operating hours / no courts) → else `ready`.
- **Overall**: one prominent `<Card>` — big `utilizationPct%` + a full-width bar (`ReportBarList` with a single item, or a plain div) + `"<booked> of <open> bookable hours"` caption (`formatHours(minutes)` = `(minutes/60).toFixed(1) + " h"`).
- **By court** `<Card>`: a sort control (`Select`: "Highest first" / "Lowest first" / "Name"), `<ReportBarList>` (bar colour `#00F08A`, `caption` = `"<pct>% · <booked>/<open> h"`) + `<DataTable caption="Court utilization" columns=[Court, Available (h), Booked (h), Utilization]>` with `href` → `/reports/court-utilization?…&court=<id>` (drill-down, spec §28). Sort is client-side over the fetched rows.
- **By sport** `<Card>`: `<ReportBarList>` + `<DataTable>` (href → `…&sport=<fsId>`).
- **Peak hours** `<Card>`: `<PeakHoursChart>` + `<DataTable caption="Peak hours" columns=[Hour, Demand, Booked (min), Open (min)]>`.
- **Heatmap** `<Card>`: `<Heatmap>`.
- `onExportCsv`: `toCsv` of the by-court rows + by-sport rows + peak-hour rows (sectioned), filename `court-utilization-<facilityId>-<preset>.csv`.

- [ ] **Step 1: `court-utilization-report.test.tsx`**

```tsx
import { describe, expect, it } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { CourtUtilizationReport } from "./court-utilization-report";
import { installFakeReportsFilterDeps } from "@/test/fakes/fake-reports-filter-deps";
import { installFakeReportsService } from "@/test/fakes/fake-reports-service";

const SLOW = { timeout: 4000 } as const;

function setup() {
  installFakeReportsFilterDeps();
  return installFakeReportsService();
}

describe("CourtUtilizationReport", () => {
  it("shows the empty state when the facility has no bookable hours", async () => {
    setup();
    render(<CourtUtilizationReport />);
    expect(await screen.findByText(/no court activity/i, {}, SLOW)).toBeInTheDocument();
  });

  it("renders the overall figure, the court table and the heatmap when there is data", async () => {
    const reports = setup();
    reports.overallUtilization = { openMinutes: 6000, bookedMinutes: 4080, utilizationPct: 68 };
    reports.courtUtilization = [
      { courtId: "c1", courtName: "Court 1", facilitySportId: "fs1", sportName: "Badminton", openMinutes: 3000, bookedMinutes: 2460, utilizationPct: 82 },
      { courtId: "c2", courtName: "Court 2", facilitySportId: "fs1", sportName: "Badminton", openMinutes: 3000, bookedMinutes: 1620, utilizationPct: 54 },
    ];
    reports.sportUtilization = [
      { facilitySportId: "fs1", sportName: "Badminton", openMinutes: 6000, bookedMinutes: 4080, utilizationPct: 68 },
    ];
    reports.peakHours = [{ hour: 18, openMinutes: 300, bookedMinutes: 270, demandPct: 90 }];
    reports.demandHeatmap = [{ dow: 1, hour: 18, openMinutes: 60, bookedMinutes: 54, demandPct: 90 }];

    render(<CourtUtilizationReport />);

    expect(await screen.findByText("68%", {}, SLOW)).toBeInTheDocument();
    expect(screen.getByRole("table", { name: /court utilization/i })).toBeInTheDocument();
    expect(screen.getByRole("table", { name: /demand by day/i })).toBeInTheDocument();
  });

  it("re-sorts the court list lowest-first", async () => {
    const reports = setup();
    reports.overallUtilization = { openMinutes: 6000, bookedMinutes: 4080, utilizationPct: 68 };
    reports.courtUtilization = [
      { courtId: "c1", courtName: "Court 1", facilitySportId: "fs1", sportName: "Badminton", openMinutes: 3000, bookedMinutes: 2460, utilizationPct: 82 },
      { courtId: "c2", courtName: "Court 2", facilitySportId: "fs1", sportName: "Badminton", openMinutes: 3000, bookedMinutes: 1620, utilizationPct: 54 },
    ];
    render(<CourtUtilizationReport />);
    await screen.findByText("68%", {}, SLOW);

    await userEvent.click(screen.getByRole("combobox", { name: /sort/i }));
    await userEvent.click(await screen.findByRole("option", { name: /lowest/i }));

    const rows = screen.getAllByRole("row");
    // header + Court 2 (54%) before Court 1 (82%) in the by-court table
    const bodyText = rows.map((r) => r.textContent).join("|");
    expect(bodyText.indexOf("Court 2")).toBeLessThan(bodyText.indexOf("Court 1"));
  });
});
```

- [ ] **Step 2: run — fails.**

- [ ] **Step 3: write `court-utilization-report.tsx`** per Behaviour. Reuse `Delta`? No deltas this phase. `formatHours(min)` helper local. Sort state via `useState<"high"|"low"|"name">("high")`, applied with `[...courtUtilization].sort(...)`.

- [ ] **Step 4: run — passes.**

- [ ] **Step 5:** `npx vitest run src/features/reports src/services/reports` + `npm run typecheck` + `npx next lint --dir src`.

- [ ] **Step 6: full suite** — `npx vitest run`; confirm only the known pre-existing `courts-setup`/`facility-details` flakes fail, nothing in `reports`.

---

## Task 6: manual DB verification (reviewer, against linked Supabase)

Apply `0056` + `0057` + `0058` + `0059`. Using a facility with a known operating schedule (e.g. Mon–Sun 06:00–23:00 = 17 h/day) and one court:

```sql
-- one week, one court, one 1-hour booking on Monday 18:00–19:00, not cancelled
select * from get_overall_utilization('<fac>', 'CUSTOM', '<mon>', '<sun>', null, null);
-- open_minutes = 17*60*7*<court count>; booked_minutes = 60; utilization_pct = round(60/open*100,1)

select * from get_court_utilization('<fac>', 'CUSTOM', '<mon>', '<sun>', null, null);
-- the booked court: booked_minutes 60; others 0

select * from get_peak_hours('<fac>', 'CUSTOM', '<mon>', '<sun>', null, null);
-- hour 18 has booked_minutes 60, demand_pct = round(60 / (60*7) *100,1) ≈ 14.3; hours the facility is closed do NOT appear

select * from get_demand_heatmap('<fac>', 'CUSTOM', '<mon>', '<sun>', null, null);
-- (dow 1, hour 18): booked 60, open 60, demand_pct 100

-- membership session usage
-- create an active batch on a court/day, book one member slot for a date in range → that session's
-- full window counts as booked in get_court_utilization for that court.

-- facility isolation
select * from get_court_utilization('<other-facility>', 'THIS_MONTH', null, null, null, null);
-- raises "Not authorized"
```

Confirm §51: with the court's operating hours at 10 h and 7 h booked, utilization = 70%. (No maintenance model, so nothing to exclude.)

---

## Self-Review

**Spec coverage:** §12 overall utilization from the existing operating-hours model → `get_overall_utilization` + `0057` (documented precedence, no parallel engine). §13 by-court, sortable → `get_court_utilization` + client sort. §14 by-sport → `get_sport_utilization`. §15 peak hours, closed hours excluded → `get_peak_hours` `where o.m > 0`. §16 heatmap, not colour-alone → `<Heatmap>` (opacity + number + title). §28 drill-down → `DataTable href` on court + sport. §42 tables under charts → every `<Card>` pairs chart/bars with a `DataTable`. §51 → manual task confirms 70%, maintenance moot.

**Placeholder scan:** Task 5 Step 3 says "write per Behaviour" rather than pasting the full 200-line component — every sub-part (`Promise.all` load, status derivation, `ReportShell` wiring, `DataTable`/`ReportBarList`/chart usage, sort state) is either specified here or identical to `booking-report.tsx` from Phase 2. Acceptable.

**Type consistency:** `open_minutes`/`booked_minutes`/`utilization_pct` (SQL) ↔ `openMinutes`/`bookedMinutes`/`utilizationPct` (TS) mapping is uniform across all five RPCs, the service, the fake and the component. `HeatmapCell` (types.ts) vs `HeatCell` (heatmap.tsx local) — **rename `HeatCell` → import `HeatmapCell` from `../types`** to avoid divergence. `demand_pct` → `demandPct`, `dow` stays `dow`, `hour` stays `hour`.
