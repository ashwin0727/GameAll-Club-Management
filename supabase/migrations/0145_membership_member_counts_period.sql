-- ═══════════════════════════════════════════════════════════════════════════
-- Memberships report: member counts are for the dates chosen, not "everyone ever".
--
-- 0143 counted Total Members as everyone who had joined by the end of the range — so whatever dates were picked, the card
-- showed the whole history. They are now taken from the memberships that were running DURING the dates:
--
--   total_members     people with a membership that overlapped the dates (it started by the last day and had not ended
--                     before the first day); cancelled ones included
--   active_members    of those, people whose membership was still running (and not cancelled) on the last day of the dates
--                     — or today, when that day is still to come
--   inactive_members  the rest: their membership ended, or was cancelled, within the dates
--
-- The window is [first day, last day] with the last day held at today, so a membership that has not started yet is never
-- counted. Sports (the top bar) narrow all three; null = All Sports. Same signature and columns as 0143.
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
       and m.end_date >= p_start_date
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
