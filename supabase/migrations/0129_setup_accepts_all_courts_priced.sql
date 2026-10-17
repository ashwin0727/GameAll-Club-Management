-- ═══════════════════════════════════════════════════════════════════════════
-- complete_facility_setup: a sport is priced when it has its own rate OR every one of its courts/turfs has one.
--
-- The Pricing step lets an owner skip a sport's default rate when every court of that sport is customized with its
-- own price (the default would apply to nothing). Finishing setup then failed with "Pricing is required for every
-- sport", because this function only looked for a sport-level rule. A sport whose courts are all individually
-- priced is fully priced, so it now passes.
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

  update facilities
  set onboarding_step = 'COMPLETED', onboarding_completed_at = now()
  where id = p_facility_id
  returning * into result;

  update profiles set onboarding_completed = true where id = auth.uid();

  return result;
end;
$$;
