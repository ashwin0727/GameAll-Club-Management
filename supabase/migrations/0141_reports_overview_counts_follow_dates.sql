-- ═══════════════════════════════════════════════════════════════════════════
-- Reports & Analytics overview: Members, Program, Coach and Students follow the chosen dates.
--
-- 0140 counted those four "right now", so changing the dates changed nothing on those cards. They now count who/what was
-- in place during the dates picked:
--   members    people whose membership ran at any point in the dates (cancelled ones left out)
--   programs   programs running at any point in the dates
--   coaches    coaches who had joined by the last day of the dates (not inactive)
--   students   people enrolled at any point in the dates
-- Everything else in get_reports_overview is unchanged; get_reports_overview_trend is untouched (it already
-- followed the dates). Same signature as 0140.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function get_reports_overview(
  p_facility_id uuid,
  p_start_date date,
  p_end_date date,
  p_facility_sport_ids uuid[] default null
) returns jsonb
language plpgsql
stable
as $$
declare
  range_ tstzrange;
  tz text;
  gross bigint;
  refunded bigint;
  spent bigint;
  coaching_spent bigint;
  rev jsonb;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  range_ := resolve_finance_date_range(p_facility_id, 'CUSTOM', p_start_date, p_end_date);
  tz := coalesce((select f.timezone from facilities f where f.id = p_facility_id), 'Asia/Kolkata');

  select (coalesce(sum(p.amount_inr), 0) * 100)::bigint into gross
    from payments p
   where p.facility_id = p_facility_id and p.status = 'paid'
     and range_ @> coalesce(p.paid_at, p.created_at)
     and payment_in_sports(p.id, p_facility_sport_ids);

  select coalesce(sum(r.amount_minor), 0)::bigint into refunded
    from refunds r
   where r.facility_id = p_facility_id and r.status = 'PROCESSED'
     and r.processed_at is not null and range_ @> r.processed_at
     and payment_order_in_sports(r.payment_order_id, p_facility_sport_ids);

  select coalesce(sum(e.amount_minor), 0)::bigint,
         coalesce(sum(e.amount_minor) filter (where lower(c.name) = 'coaching'), 0)::bigint
    into spent, coaching_spent
    from expenses e join expense_categories c on c.id = e.category_id
   where e.facility_id = p_facility_id and e.status = 'RECORDED'
     and range_ @> (e.spent_on::timestamp at time zone tz);

  select jsonb_build_object(
           'guest', coalesce(sum(v.amount_minor) filter (where v.source_type = 'GUEST_BOOKING'), 0),
           'membership', coalesce(sum(v.amount_minor) filter (where v.source_type = 'MEMBERSHIP'), 0),
           'coaching', coalesce(sum(v.amount_minor) filter (where v.source_type = 'COACHING'), 0))
    into rev
    from finance_transactions_view v
   where v.facility_id = p_facility_id and v.status = 'paid' and range_ @> v.effective_at
     and payment_in_sports(v.id, p_facility_sport_ids);

  return jsonb_build_object(
    'totalRevenueMinor', gross - refunded,
    'totalExpensesMinor', spent,
    'netRevenueMinor', gross - refunded - spent,
    'guestBookings', (
      select count(*) from bookings b
       where b.facility_id = p_facility_id and b.customer_type = 'GUEST' and range_ @> b.start_time
         and booking_in_sports(b.id, p_facility_sport_ids)
    ),
    -- Members: people whose membership ran at any point in the dates (it started by the last day and had not ended
    -- before the first day), cancelled ones left out.
    'members', (
      select count(distinct m.member_id) from memberships m
       where m.facility_id = p_facility_id and m.status <> 'cancelled'
         and m.start_date <= p_end_date and m.end_date >= p_start_date
         and membership_in_sports(m.id, p_facility_sport_ids)
    ),
    -- Programs: those that were running at any point in the dates.
    'programs', (
      select count(*) from coaching_programs cp
       where cp.facility_id = p_facility_id and cp.status in ('ACTIVE', 'COMPLETED', 'PAUSED')
         and coalesce(cp.start_date, (cp.created_at at time zone tz)::date) <= p_end_date
         and coalesce(cp.end_date, p_end_date) >= p_start_date
         and (p_facility_sport_ids is null or cp.facility_sport_id = any (p_facility_sport_ids))
    ),
    -- Coaches: those who had joined by the last day of the dates (and are not marked inactive).
    'coaches', (
      select count(*) from coaches c
       where c.facility_id = p_facility_id and c.status in ('ACTIVE', 'ON_LEAVE')
         and coalesce(c.joined_on, (c.created_at at time zone tz)::date) <= p_end_date
         and (p_facility_sport_ids is null
              or exists (select 1 from coach_sports cs where cs.coach_id = c.id and cs.facility_sport_id = any (p_facility_sport_ids)))
    ),
    -- Students: people enrolled at any point in the dates (started by the last day; not stopped or finished before the first).
    'students', (
      select count(distinct e.member_id) from coaching_enrollments e join coaching_programs cp on cp.id = e.program_id
       where e.facility_id = p_facility_id
         and e.start_date <= p_end_date
         and coalesce(e.cancelled_at at time zone tz, e.end_date, p_end_date)::date >= p_start_date
         and (p_facility_sport_ids is null or cp.facility_sport_id = any (p_facility_sport_ids))
    ),
    'guestBookingRevenueMinor', (rev ->> 'guest')::bigint,
    'membershipRevenueMinor', (rev ->> 'membership')::bigint,
    'coachingRevenueMinor', (rev ->> 'coaching')::bigint,
    'coachingExpensesMinor', coaching_spent
  );
end;
$$;

grant execute on function get_reports_overview(uuid, date, date, uuid[]) to authenticated;
