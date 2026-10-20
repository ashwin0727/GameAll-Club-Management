-- ═══════════════════════════════════════════════════════════════════════════
-- Memberships report: Total / Active / Inactive members as of the end of the chosen dates.
--
-- The report had no figure for "Total Members" or "Inactive Members", and its "Active Members" was today's count whatever
-- dates were chosen. These three now follow the dates: they are counted as of the LAST day of the range (or today, when
-- that day is still to come, so the current month reads "right now").
--
--   total_members     people who had a membership starting on or before the as-of day (cancelled ones included)
--   active_members    of those, people whose membership covers the as-of day and is not cancelled
--   inactive_members total - active: they joined, but their membership ended or was cancelled by then
--
-- Sports (the top bar) narrow all three by the sport each membership's member is enrolled in; null = All Sports.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function get_membership_member_counts(
  p_facility_id uuid,
  p_start_date date,
  p_end_date date,
  p_facility_sport_ids uuid[] default null
) returns table (as_of date, total_members bigint, active_members bigint, inactive_members bigint)
language plpgsql
stable
as $$
declare
  tz text;
  asof date;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  if p_start_date is null or p_end_date is null or p_end_date < p_start_date then
    raise exception 'A custom date range requires a valid start and end date.' using errcode = '22023';
  end if;
  tz := coalesce((select f.timezone from facilities f where f.id = p_facility_id), 'Asia/Kolkata');
  asof := least(p_end_date, (now() at time zone tz)::date);

  return query
  with scoped as (
    select m.member_id,
           (m.status <> 'cancelled' and m.end_date >= asof) as covers
      from memberships m
     where m.facility_id = p_facility_id
       and m.start_date <= asof
       and membership_in_sports(m.id, p_facility_sport_ids)
  ), people as (
    select member_id, bool_or(covers) as active from scoped group by member_id
  )
  select asof,
         count(*)::bigint,
         (count(*) filter (where active))::bigint,
         (count(*) filter (where not active))::bigint
    from people;
end;
$$;

grant execute on function get_membership_member_counts(uuid, date, date, uuid[]) to authenticated;
