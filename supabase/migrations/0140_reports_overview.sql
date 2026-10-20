-- ═══════════════════════════════════════════════════════════════════════════
-- Reports & Analytics overview: twelve headline figures, and a trend for each of them.
--
-- get_reports_overview        every card on the overview, for a date range and (optionally) the sports ticked in the
--                             top bar. One call, one definition of each figure.
-- get_reports_overview_trend  the chart behind a card: that figure, bucketed by day / week / month over the same dates.
--
-- What each figure means (null sports = All Sports = "Overall"; a list = "Selected"):
--   totalRevenue         payments received in the range, less refunds processed in it        (sport-scoped)
--   totalExpenses        recorded expenses in the range                                      (facility-wide)
--   netRevenue           totalRevenue - totalExpenses
--   guestBookings        guest court bookings in the range, every status (as the Guest Bookings report counts them)
--   members              memberships that are active now                                     (sport-scoped)
--   programs             coaching programs that are active now                               (sport-scoped)
--   coaches              coaches that are active now                                         (sport-scoped)
--   students             distinct students with an active enrollment now                     (sport-scoped)
--   guestBookingRevenue  payments received in the range for guest bookings                   (sport-scoped)
--   membershipRevenue    payments received in the range for memberships                      (sport-scoped)
--   coachingRevenue      payments received in the range for coaching                         (sport-scoped)
--   coachingExpenses     recorded expenses in the range filed under the "Coaching" category  (facility-wide)
--
-- Expenses are not tied to a sport, so they never narrow. Counts (members, programs, coaches, students) are "right now",
-- not "in the range"; revenue, expenses and guest bookings are in the range.
--
-- What a card's chart plots over time (the same figure, bucketed; for the "now" counts, how many were added):
--   members → new memberships started · programs → programs started · coaches → coaches joined · students → new enrollments
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
    'members', (
      select count(*) from memberships m
       where m.facility_id = p_facility_id and m.status = 'active' and membership_in_sports(m.id, p_facility_sport_ids)
    ),
    'programs', (
      select count(*) from coaching_programs cp
       where cp.facility_id = p_facility_id and cp.status = 'ACTIVE'
         and (p_facility_sport_ids is null or cp.facility_sport_id = any (p_facility_sport_ids))
    ),
    'coaches', (
      select count(*) from coaches c
       where c.facility_id = p_facility_id and c.status = 'ACTIVE'
         and (p_facility_sport_ids is null
              or exists (select 1 from coach_sports cs where cs.coach_id = c.id and cs.facility_sport_id = any (p_facility_sport_ids)))
    ),
    'students', (
      select count(distinct e.member_id) from coaching_enrollments e join coaching_programs cp on cp.id = e.program_id
       where e.facility_id = p_facility_id and e.status = 'ACTIVE'
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


create or replace function get_reports_overview_trend(
  p_facility_id uuid,
  p_metric text,
  p_start_date date,
  p_end_date date,
  p_granularity text default 'daily',
  p_facility_sport_ids uuid[] default null
) returns table (bucket_date date, value bigint)
language plpgsql
stable
as $$
declare
  range_ tstzrange;
  tz text;
  unit text;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  if p_granularity not in ('daily', 'weekly', 'monthly') then
    raise exception 'Unknown granularity: %', p_granularity using errcode = '22023';
  end if;
  unit := case p_granularity when 'daily' then 'day' when 'weekly' then 'week' else 'month' end;
  range_ := resolve_finance_date_range(p_facility_id, 'CUSTOM', p_start_date, p_end_date);
  tz := coalesce((select f.timezone from facilities f where f.id = p_facility_id), 'Asia/Kolkata');

  -- Money in, by what it was for (payments received, by day received).
  if p_metric in ('GUEST_BOOKING_REVENUE', 'MEMBERSHIP_REVENUE', 'COACHING_REVENUE') then
    return query
    select date_trunc(unit, v.effective_at at time zone tz)::date, coalesce(sum(v.amount_minor), 0)::bigint
      from finance_transactions_view v
     where v.facility_id = p_facility_id and v.status = 'paid' and range_ @> v.effective_at
       and v.source_type = case p_metric when 'GUEST_BOOKING_REVENUE' then 'GUEST_BOOKING' when 'MEMBERSHIP_REVENUE' then 'MEMBERSHIP' else 'COACHING' end
       and payment_in_sports(v.id, p_facility_sport_ids)
     group by 1 order by 1;

  -- Revenue = payments less refunds; net = revenue less expenses.
  elsif p_metric in ('REVENUE', 'NET') then
    return query
    with pay as (
      select date_trunc(unit, v.effective_at at time zone tz)::date as b, sum(v.amount_minor) as amt
        from finance_transactions_view v
       where v.facility_id = p_facility_id and v.status = 'paid' and range_ @> v.effective_at
         and payment_in_sports(v.id, p_facility_sport_ids)
       group by 1
    ), ref as (
      select date_trunc(unit, r.processed_at at time zone tz)::date as b, sum(r.amount_minor) as amt
        from refunds r
       where r.facility_id = p_facility_id and r.status = 'PROCESSED' and r.processed_at is not null and range_ @> r.processed_at
         and payment_order_in_sports(r.payment_order_id, p_facility_sport_ids)
       group by 1
    ), exp as (
      select date_trunc(unit, e.spent_on::timestamp)::date as b, sum(e.amount_minor) as amt
        from expenses e
       where e.facility_id = p_facility_id and e.status = 'RECORDED' and range_ @> (e.spent_on::timestamp at time zone tz)
       group by 1
    ), buckets as (
      select b from pay union select b from ref union select b from exp
    )
    select k.b,
           (coalesce(pay.amt, 0) - coalesce(ref.amt, 0) - case when p_metric = 'NET' then coalesce(exp.amt, 0) else 0 end)::bigint
      from buckets k
      left join pay on pay.b = k.b left join ref on ref.b = k.b left join exp on exp.b = k.b
     order by k.b;

  -- Expenses (facility-wide): all, or the "Coaching" category only.
  elsif p_metric in ('EXPENSES', 'COACHING_EXPENSES') then
    return query
    select date_trunc(unit, e.spent_on::timestamp)::date, coalesce(sum(e.amount_minor), 0)::bigint
      from expenses e join expense_categories c on c.id = e.category_id
     where e.facility_id = p_facility_id and e.status = 'RECORDED' and range_ @> (e.spent_on::timestamp at time zone tz)
       and (p_metric = 'EXPENSES' or lower(c.name) = 'coaching')
     group by 1 order by 1;

  elsif p_metric = 'GUEST_BOOKINGS' then
    return query
    select date_trunc(unit, b.start_time at time zone tz)::date, count(*)::bigint
      from bookings b
     where b.facility_id = p_facility_id and b.customer_type = 'GUEST' and range_ @> b.start_time
       and booking_in_sports(b.id, p_facility_sport_ids)
     group by 1 order by 1;

  -- "Now" counts, charted as how many were added in each bucket.
  elsif p_metric = 'MEMBERS' then
    return query
    select date_trunc(unit, m.start_date::timestamp)::date, count(*)::bigint
      from memberships m
     where m.facility_id = p_facility_id and m.status <> 'cancelled'
       and range_ @> (m.start_date::timestamp at time zone tz) and membership_in_sports(m.id, p_facility_sport_ids)
     group by 1 order by 1;

  elsif p_metric = 'PROGRAMS' then
    return query
    select date_trunc(unit, cp.start_date::timestamp)::date, count(*)::bigint
      from coaching_programs cp
     where cp.facility_id = p_facility_id and cp.start_date is not null and cp.status in ('ACTIVE', 'COMPLETED', 'PAUSED')
       and range_ @> (cp.start_date::timestamp at time zone tz)
       and (p_facility_sport_ids is null or cp.facility_sport_id = any (p_facility_sport_ids))
     group by 1 order by 1;

  elsif p_metric = 'COACHES' then
    return query
    select date_trunc(unit, coalesce(c.joined_on, (c.created_at at time zone tz)::date)::timestamp)::date, count(*)::bigint
      from coaches c
     where c.facility_id = p_facility_id and c.status in ('ACTIVE', 'ON_LEAVE')
       and range_ @> (coalesce(c.joined_on, (c.created_at at time zone tz)::date)::timestamp at time zone tz)
       and (p_facility_sport_ids is null
            or exists (select 1 from coach_sports cs where cs.coach_id = c.id and cs.facility_sport_id = any (p_facility_sport_ids)))
     group by 1 order by 1;

  elsif p_metric = 'STUDENTS' then
    return query
    select date_trunc(unit, e.start_date::timestamp)::date, count(*)::bigint
      from coaching_enrollments e join coaching_programs cp on cp.id = e.program_id
     where e.facility_id = p_facility_id and e.status <> 'CANCELLED'
       and range_ @> (e.start_date::timestamp at time zone tz)
       and (p_facility_sport_ids is null or cp.facility_sport_id = any (p_facility_sport_ids))
     group by 1 order by 1;

  else
    raise exception 'Unknown overview metric: %', p_metric using errcode = '22023';
  end if;
end;
$$;

grant execute on function get_reports_overview_trend(uuid, text, date, date, text, uuid[]) to authenticated;
