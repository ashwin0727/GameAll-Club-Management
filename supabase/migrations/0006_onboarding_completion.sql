-- ═══════════════════════════════════════════════════════════════════════════
-- Onboarding Completion / Setup Summary
--
-- No new onboarding-state field: facilities.onboarding_step (0002) is
-- already the authoritative state and already has a COMPLETED value. This
-- migration only adds the completion timestamp and the RPC that flips both
-- facilities.onboarding_step and profiles.onboarding_completed atomically,
-- re-validating server-side so a client bug can never mark a facility
-- COMPLETED while mandatory configuration is missing.
-- ═══════════════════════════════════════════════════════════════════════════

alter table facilities add column onboarding_completed_at timestamptz;

-- ─────────────────────────────────────────────────────────────────────────
-- complete_facility_setup: verifies the same requirements the app already
-- checks (>=1 active sport, >=1 playing area, a facility operating
-- schedule, and a sport-level pricing rule for every active facility_sport)
-- before marking the facility COMPLETED and the caller's profile
-- onboarding_completed. Idempotent: calling it again once already
-- COMPLETED just returns the current row without re-validating or writing.
-- ─────────────────────────────────────────────────────────────────────────
create function complete_facility_setup(p_facility_id uuid) returns facilities
language plpgsql
as $$
declare
  result facilities;
  sport_count integer;
  area_count integer;
  schedule_count integer;
  unpriced_sport_count integer;
begin
  select * into result from facilities where id = p_facility_id;
  if result.id is null then
    raise exception 'Facility not found' using errcode = 'P0002';
  end if;

  if result.onboarding_step = 'COMPLETED' then
    return result;
  end if;

  select count(*) into sport_count from facility_sports where facility_id = p_facility_id and is_active;
  if sport_count = 0 then
    raise exception 'At least one sport is required.' using errcode = '23514';
  end if;

  select count(*) into area_count from courts where facility_id = p_facility_id and not archived;
  if area_count = 0 then
    raise exception 'At least one playing area is required.' using errcode = '23514';
  end if;

  select count(*) into schedule_count from operating_schedules
    where facility_id = p_facility_id and scope_type = 'FACILITY';
  if schedule_count = 0 then
    raise exception 'Operating hours are required.' using errcode = '23514';
  end if;

  select count(*) into unpriced_sport_count
  from facility_sports fs
  where fs.facility_id = p_facility_id
    and fs.is_active
    and not exists (
      select 1 from pricing_rules pr
      join pricing_plans pp on pp.id = pr.pricing_plan_id
      where pp.facility_id = p_facility_id
        and pp.status = 'ACTIVE'
        and pr.facility_sport_id = fs.id
        and pr.playing_area_id is null
        and pr.is_active
    );
  if unpriced_sport_count > 0 then
    raise exception 'Pricing is required for every sport.' using errcode = '23514';
  end if;

  update facilities
  set onboarding_step = 'COMPLETED', onboarding_completed_at = now()
  where id = p_facility_id
  returning * into result;

  update profiles set onboarding_completed = true where id = auth.uid();

  return result;
end;
$$;