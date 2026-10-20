-- ═══════════════════════════════════════════════════════════════════════════
-- Memberships report: people REGISTERED in the dates count, not only those whose membership had already started.
--
-- 0145 counted a member only if their membership had started by today and overlapped the dates. A member registered this
-- month whose membership starts later (or whose start date is after today) was missed — the page showed 2 members while
-- the same page's payment and plan figures, which count memberships created in the dates, showed 4.
--
-- A person is now counted for the dates when either
--     * their membership was created (registered) in the dates, or
--     * a membership of theirs was running at some point in the dates.
--   total_members     those people (cancelled ones included)
--   active_members    of those, people with a membership that is not cancelled and has not ended by the last day of the
--                     dates (or today, when that day is still to come) — so an upcoming membership counts as active
--   inactive_members  the rest: ended before then, or cancelled
--
-- Sports (the top bar) narrow all three; null = All Sports. Same signature and columns as 0143 / 0145.
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
       and (
             ((m.created_at at time zone tz)::date between p_start_date and p_end_date)
          or (m.start_date <= p_end_date and m.end_date >= p_start_date)
       )
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
