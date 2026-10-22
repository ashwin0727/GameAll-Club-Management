-- ═══════════════════════════════════════════════════════════════════════════
-- complete_facility_setup: a payout method is now part of setting a facility up.
--
-- Before an owner reaches the dashboard they must give GameAll somewhere to pay out what the facility collects (a bank
-- account or UPI ID, added on the new Payments step of onboarding). GameAll verifies it by hand afterwards; setup only
-- needs it to be present. Facilities that are already COMPLETED are unaffected — that case returns before this check.
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
  payout_count integer;
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
    -- no sport-level rate…
    and not exists (
      select 1 from pricing_rules pr
      join pricing_plans pp on pp.id = pr.pricing_plan_id
      where pp.facility_id = p_facility_id
        and pp.status = 'ACTIVE'
        and pr.facility_sport_id = fs.id
        and pr.playing_area_id is null
        and pr.is_active
    )
    -- …and not (it has courts and every one of them has its own rate)
    and not (
      exists (select 1 from courts c where c.facility_sport_id = fs.id and not c.archived)
      and not exists (
        select 1 from courts c
        where c.facility_sport_id = fs.id
          and not c.archived
          and not exists (
            select 1 from pricing_rules pr
            join pricing_plans pp on pp.id = pr.pricing_plan_id
            where pp.facility_id = p_facility_id
              and pp.status = 'ACTIVE'
              and pr.playing_area_id = c.id
              and pr.is_active
          )
      )
    );
  if unpriced_sport_count > 0 then
    raise exception 'Pricing is required for every sport.' using errcode = '23514';
  end if;

  select count(*) into payout_count from facility_payout_methods where facility_id = p_facility_id;
  if payout_count = 0 then
    raise exception 'A payout method is required.' using errcode = '23514';
  end if;

  update facilities
  set onboarding_step = 'COMPLETED', onboarding_completed_at = now()
  where id = p_facility_id
  returning * into result;

  update profiles set onboarding_completed = true where id = auth.uid();

  return result;
end;
$$;
