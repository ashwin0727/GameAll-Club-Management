-- ═══════════════════════════════════════════════════════════════════════════
-- Reports & Analytics — Phase 4: Revenue by sport / court.
--
-- The only revenue cuts Finance does not already expose. Court-attributable
-- paid revenue only: a payment is attributed to a sport/court through its
-- booking's court, or through its released-seat session's court. Membership
-- payments (no booking, no session) are NOT attributed here — the UI shows
-- membership revenue as its own line from get_revenue_breakdown.
--
-- Paid base identical to get_finance_summary:
--   payments.status = 'paid' AND range @> coalesce(paid_at, created_at)
-- so with no sport/court filter these totals reconcile to gross revenue
-- (minus the unattributed membership + other slice).
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function get_revenue_by_sport(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_facility_sport_id uuid default null,
  p_court_id uuid default null
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
  with rev as (
    select
      coalesce(bc.facility_sport_id, ms.facility_sport_id) as fs_id,
      (p.amount_inr * 100)::bigint as amount_minor
    from payments p
    left join bookings b on b.id = p.booking_id
    left join courts bc on bc.id = b.court_id
    left join membership_session_bookings msb on msb.id = p.membership_session_booking_id
    left join membership_sessions ms on ms.id = msb.session_id
    where p.facility_id = p_facility_id
      and p.status = 'paid'
      and range_ @> coalesce(p.paid_at, p.created_at)
      and coalesce(bc.facility_sport_id, ms.facility_sport_id) is not null
      and (p_court_id is null or coalesce(b.court_id, ms.court_id) = p_court_id)
  )
  select
    fs.id,
    coalesce(fs.custom_sport_name, sp.name),
    coalesce(sum(rev.amount_minor), 0)::bigint
  from facility_sports fs
  join sports sp on sp.id = fs.sport_id
  left join rev on rev.fs_id = fs.id
  where fs.facility_id = p_facility_id
    and fs.is_active
    and (p_facility_sport_id is null or fs.id = p_facility_sport_id)
  group by fs.id, coalesce(fs.custom_sport_name, sp.name)
  order by coalesce(sum(rev.amount_minor), 0) desc, 2;
end;
$$;

grant execute on function get_revenue_by_sport(uuid, text, date, date, uuid, uuid) to authenticated;


create or replace function get_revenue_by_court(
  p_facility_id uuid,
  p_preset text default 'THIS_MONTH',
  p_start_date date default null,
  p_end_date date default null,
  p_facility_sport_id uuid default null,
  p_court_id uuid default null
) returns table (
  court_id uuid,
  court_name text,
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
  with rev as (
    select
      coalesce(b.court_id, ms.court_id) as court_id,
      (p.amount_inr * 100)::bigint as amount_minor
    from payments p
    left join bookings b on b.id = p.booking_id
    left join membership_session_bookings msb on msb.id = p.membership_session_booking_id
    left join membership_sessions ms on ms.id = msb.session_id
    where p.facility_id = p_facility_id
      and p.status = 'paid'
      and range_ @> coalesce(p.paid_at, p.created_at)
      and coalesce(b.court_id, ms.court_id) is not null
  )
  select
    c.id,
    c.name,
    c.facility_sport_id,
    coalesce(fs.custom_sport_name, sp.name),
    coalesce(sum(rev.amount_minor), 0)::bigint
  from courts c
  join facility_sports fs on fs.id = c.facility_sport_id
  join sports sp on sp.id = fs.sport_id
  left join rev on rev.court_id = c.id
  where c.facility_id = p_facility_id
    and not c.archived
    and (p_facility_sport_id is null or c.facility_sport_id = p_facility_sport_id)
    and (p_court_id is null or c.id = p_court_id)
  group by c.id, c.name, c.facility_sport_id, coalesce(fs.custom_sport_name, sp.name)
  order by coalesce(sum(rev.amount_minor), 0) desc, c.name;
end;
$$;

grant execute on function get_revenue_by_court(uuid, text, date, date, uuid, uuid) to authenticated;
