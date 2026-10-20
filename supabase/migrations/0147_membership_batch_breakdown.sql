-- ═══════════════════════════════════════════════════════════════════════════
-- Memberships report: members by sport, court / turf and booked timing.
--
-- One row per membership session batch (a court held at a time of day on certain weekdays for members) that ran during the
-- chosen dates, with how many members are in it:
--   members          people in the batch who are counted for the dates (a membership registered, or running, in them —
--                    the same people as "Total Members" on the report)
--   active_members   of those, people whose membership has not ended or been cancelled by the last day of the dates
--                    (or today, when that day is still to come)
--   court_members    distinct people across every timing on that court / turf
--   sport_members    distinct people across every court in that sport
-- so a person in two timings is counted once in the court and sport totals.
--
-- Under All Sports a last row, batch_id null and sport_name "Not assigned to a session", counts those same people who are
-- not in any batch at all, so nobody is left out of the picture. Sports (the top bar) narrow the batches; null = All Sports.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function get_membership_batch_breakdown(
  p_facility_id uuid,
  p_start_date date,
  p_end_date date,
  p_facility_sport_ids uuid[] default null
) returns table (
  facility_sport_id uuid,
  sport_name text,
  court_id uuid,
  court_name text,
  batch_id uuid,
  batch_name text,
  days_of_week smallint[],
  start_time time,
  end_time time,
  capacity integer,
  members bigint,
  active_members bigint,
  court_members bigint,
  sport_members bigint
)
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
  with rel as (
    select m.member_id, (m.status <> 'cancelled' and m.end_date >= asof) as covers
      from memberships m
     where m.facility_id = p_facility_id
       and (((m.created_at at time zone tz)::date between p_start_date and p_end_date)
            or (m.start_date <= p_end_date and m.end_date >= p_start_date))
  ), rel_member as (
    select r.member_id, bool_or(r.covers) as active from rel r group by r.member_id
  ), batches as (
    select mb.id as bid, mb.facility_sport_id as fsid, coalesce(fs.custom_sport_name, sp.name) as sname,
           mb.court_id as cid, c.name as cname, mb.name as bname, mb.days_of_week as dows,
           mb.start_time as st, mb.end_time as et, mb.capacity as cap
      from membership_batches mb
      join courts c on c.id = mb.court_id
      join facility_sports fs on fs.id = mb.facility_sport_id
      join sports sp on sp.id = fs.sport_id
     where mb.facility_id = p_facility_id
       and mb.status in ('ACTIVE', 'EXPIRED')
       and mb.start_date <= p_end_date
       and (mb.end_date is null or mb.end_date >= p_start_date)
       and (p_facility_sport_ids is null or mb.facility_sport_id = any (p_facility_sport_ids))
  ), roster as (
    select bm.batch_id as bid, bm.member_id, rm.active
      from membership_batch_members bm
      join batches b on b.bid = bm.batch_id
      join rel_member rm on rm.member_id = bm.member_id
  ), rows_ as (
    select b.fsid, b.sname, b.cid, b.cname, b.bid, b.bname, b.dows, b.st, b.et, b.cap,
           (select count(distinct r.member_id) from roster r where r.bid = b.bid)::bigint as m_all,
           (select count(distinct r.member_id) from roster r where r.bid = b.bid and r.active)::bigint as m_active,
           (select count(distinct r.member_id) from roster r join batches b2 on b2.bid = r.bid where b2.cid = b.cid)::bigint as m_court,
           (select count(distinct r.member_id) from roster r join batches b2 on b2.bid = r.bid where b2.fsid = b.fsid)::bigint as m_sport,
           0 as ord
      from batches b
    union all
    select null::uuid, 'Not assigned to a session'::text, null::uuid, null::text, null::uuid, null::text, null::smallint[],
           null::time, null::time, null::integer,
           (select count(*) from rel_member rm where not exists (select 1 from membership_batch_members bm where bm.member_id = rm.member_id))::bigint,
           (select count(*) from rel_member rm where rm.active and not exists (select 1 from membership_batch_members bm where bm.member_id = rm.member_id))::bigint,
           0::bigint, 0::bigint, 1
     where p_facility_sport_ids is null
       and exists (select 1 from rel_member rm where not exists (select 1 from membership_batch_members bm where bm.member_id = rm.member_id))
  )
  select x.fsid, x.sname, x.cid, x.cname, x.bid, x.bname, x.dows, x.st, x.et, x.cap, x.m_all, x.m_active, x.m_court, x.m_sport
    from rows_ x
   order by x.ord, x.sname, x.cname, x.st;
end;
$$;

grant execute on function get_membership_batch_breakdown(uuid, date, date, uuid[]) to authenticated;
