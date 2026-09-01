-- ═══════════════════════════════════════════════════════════════════════════
-- resolve_booking_price — a more specific pricing rule must win over the
-- broad "all days" base at the same priority. Onboarding saves every
-- default period at priority 0, so an "all days ₹300" base and a
-- "weekends 6-9pm ₹350" override tied on priority and the base leaked
-- through. Order now: court override → time-windowed before full-day →
-- day-scoped (WEEKENDS/WEEKDAYS) before ALL_DAYS → priority.
-- Mirrors resolvePrice() in src/features/pricing/validation.ts.
-- ═══════════════════════════════════════════════════════════════════════════

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
      and (playing_area_id = p_court_id or playing_area_id is null)
      and (day_type = 'ALL_DAYS' or (day_type = 'WEEKENDS') = is_weekend)
    order by
      (playing_area_id is not null) desc,
      covers_full_day asc,
      (day_type <> 'ALL_DAYS') desc,
      priority desc
  loop
    if rule.covers_full_day then
      return round(rule.amount_minor * duration_hours);
    end if;
    rule_start_min := extract(hour from rule.start_time) * 60 + extract(minute from rule.start_time);
    rule_end_min := extract(hour from rule.end_time) * 60 + extract(minute from rule.end_time);
    if rule_end_min <= rule_start_min then
      rule_end_min := rule_end_min + 24 * 60;
    end if;
    if start_min >= rule_start_min and end_min <= rule_end_min then
      return round(rule.amount_minor * duration_hours);
    end if;
  end loop;

  return null;
end;
$$;