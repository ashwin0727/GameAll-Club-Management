-- ═══════════════════════════════════════════════════════════════════════════
-- Revenue by Sport counts everything a sport earned, not only court bookings.
--
-- get_revenue_by_sport only counted payments for court bookings and released membership slots. A membership, a coaching
-- program's fees and so on were left out, and the web page filled the gap by adding a made-up "Memberships" row beside the
-- sports — which is not a sport. A membership belongs to the sport its member is enrolled in (their batch), a coaching
-- fee to the program's sport, a booking to its court's sport (payment_in_sports, from 0137).
--
-- Each sport's revenue is now every payment received in the range that belongs to it. Payments that belong to no sport — a
-- membership whose member was never put in a batch, an older renewal that is no longer linked to one — are shown on their
-- own last row, "Not linked to a sport", so the rows add up to total revenue and nothing is hidden or pinned on the wrong sport.
-- That row only appears under All Sports with no court chosen (a sport or court filter has nothing "unlinked" to show).
--
-- Same arguments and result columns as 0138 (facility_sport_id is null on the last row).
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function get_revenue_by_sport(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_facility_sport_id uuid default null,
  p_court_id uuid default null,
  p_facility_sport_ids uuid[] default null
) returns table (
  facility_sport_id uuid,
  sport_name text,
  revenue_minor bigint
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
  with received as (
    select p.id, p.amount_inr
      from payments p
     where p.facility_id = p_facility_id
       and p.status = 'paid'
       and range_ @> coalesce(p.paid_at, p.created_at)
       -- a court filter keeps only what was paid for that court (its bookings, or a membership slot held on it)
       and (p_court_id is null
            or exists (select 1 from bookings b where b.id = p.booking_id and b.court_id = p_court_id)
            or exists (select 1 from membership_session_bookings msb join membership_sessions ms on ms.id = msb.session_id
                        where msb.id = p.membership_session_booking_id and ms.court_id = p_court_id))
  ), per_sport as (
    select fs.id as fsid,
           coalesce(fs.custom_sport_name, sp.name) as nm,
           (coalesce((select sum(r.amount_inr) from received r where payment_in_sports(r.id, array[fs.id])), 0) * 100)::bigint as amt,
           0 as ord
      from facility_sports fs
      join sports sp on sp.id = fs.sport_id
     where fs.facility_id = p_facility_id
       and fs.is_active
       and (p_facility_sport_id is null or fs.id = p_facility_sport_id)
       and (p_facility_sport_ids is null or fs.id = any (p_facility_sport_ids))
  ), unlinked as (
    select null::uuid as fsid,
           'Not linked to a sport'::text as nm,
           (coalesce(sum(r.amount_inr), 0) * 100)::bigint as amt,
           1 as ord
      from received r
     where p_facility_sport_id is null and p_facility_sport_ids is null and p_court_id is null
       and not exists (select 1 from facility_sports f2
                        where f2.facility_id = p_facility_id and f2.is_active and payment_in_sports(r.id, array[f2.id]))
  ), all_rows as (
    select * from per_sport
    union all
    select * from unlinked where amt > 0
  )
  select a.fsid, a.nm, a.amt
    from all_rows a
   order by a.ord, a.amt desc, a.nm;
end;
$$;

grant execute on function get_revenue_by_sport(uuid, text, date, date, uuid, uuid, uuid[]) to authenticated;
