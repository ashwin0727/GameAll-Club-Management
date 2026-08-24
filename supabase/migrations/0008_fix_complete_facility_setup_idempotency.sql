-- ═══════════════════════════════════════════════════════════════════════════
-- Fix complete_facility_setup: the idempotent "already COMPLETED" early
-- return (0006) skipped the profiles.onboarding_completed write entirely.
--
-- That was harmless as long as every client only ever reached COMPLETED
-- through this RPC — but both the web Pricing step and the Flutter Pricing
-- step wrote facilities.onboarding_step = 'COMPLETED' directly (a client
-- bug fixed separately), which left profiles.onboarding_completed stuck at
-- false for any account onboarded before that fix. Those accounts get
-- redirected straight back into onboarding on every subsequent sign-in,
-- since the web login flow decides where to send the user by
-- profiles.onboarding_completed. Re-running this RPC for those accounts
-- must still repair the profile row, not just no-op.
-- ═══════════════════════════════════════════════════════════════════════════
create or replace function complete_facility_setup(p_facility_id uuid) returns facilities
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
    update profiles set onboarding_completed = true where id = auth.uid() and onboarding_completed = false;
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

-- One-time backfill: any facility already sitting at COMPLETED (via the
-- pre-fix client bypass) whose owner's profile never got flipped.
update profiles p
set onboarding_completed = true
where onboarding_completed = false
  and exists (
    select 1 from facilities f
    where f.owner_id = p.id and f.onboarding_step = 'COMPLETED'
  );