-- ═══════════════════════════════════════════════════════════════════════════
-- Pending Payments: the due date of a recurring (AutoPay) obligation.
--
-- list_pending_payments reported `due_on` as the membership / enrollment START date. For an AutoPay that
-- has already collected its first charge that is wrong: the next payment is due at the end of the paid
-- period (current_end), and the stale start date also made the row show as OVERDUE the day after.
--
-- Recreated from 0085 (same signature and columns); the only change is the due_on of the MEMBERSHIP and
-- COACHING_ENROLLMENT branches. Both clients (web + Flutter) read this one value, so they stay in step, and
-- any future recurring source only needs the same coalesce here.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function list_pending_payments(
  p_facility_id uuid,
  p_search text default null,
  p_source_type text default null,
  p_status text default 'ALL_OUTSTANDING',
  p_from date default null,
  p_to date default null,
  p_sort text default 'DUE_DATE',
  p_limit integer default 20,
  p_offset integer default 0,
  p_source_id uuid default null
)
returns table (
  source_type text,
  source_id uuid,
  reference text,
  customer_name text,
  customer_phone text,
  description text,
  facility_name text,
  court_name text,
  starts_at timestamptz,
  ends_at timestamptz,
  total_minor bigint,
  paid_minor bigint,
  outstanding_minor bigint,
  status text,
  payment_method text,
  due_on date,
  total_count bigint
)
language plpgsql
stable
as $$
declare
  tz text;
  fac_name text;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  select coalesce(f.timezone, 'Asia/Kolkata'), f.name
    into tz, fac_name
    from facilities f where f.id = p_facility_id;

  return query
  with obligations as (
    select
      case when b.customer_type = 'GUEST' then 'GUEST_BOOKING' else 'BOOKING' end as source_type,
      b.id as source_id,
      'BOOK-' || upper(substr(replace(b.id::text, '-', ''), 1, 6)) as reference,
      coalesce(b.guest_name, mem.full_name, 'Guest') as customer_name,
      coalesce(b.guest_phone, mem.phone) as customer_phone,
      concat_ws(' • ', c.name, to_char(b.start_time at time zone tz, 'DD Mon • HH12:MI AM')) as description,
      fac_name as facility_name,
      c.name as court_name,
      b.start_time as starts_at,
      b.end_time as ends_at,
      coalesce(b.amount_minor, 0)::bigint as total_minor,
      greatest(
        coalesce((
          select sum(p.amount_inr) * 100 from payments p
          where p.booking_id = b.id and p.status = 'paid'
        ), 0),
        case when b.payment_status = 'PAID' then coalesce(b.amount_minor, 0) else 0 end
      )::bigint as paid_minor,
      b.payment_method,
      (b.start_time at time zone tz)::date as due_on
    from bookings b
    left join courts c on c.id = b.court_id
    left join members mem on mem.id = b.member_id
    where b.facility_id = p_facility_id
      and b.status in ('pending', 'confirmed', 'completed')

    union all

    select
      'MEMBERSHIP',
      ms.id,
      'MEM-' || upper(substr(replace(ms.id::text, '-', ''), 1, 6)),
      coalesce(mem2.full_name, 'Member'),
      mem2.phone,
      coalesce(ms.name, mp.name, 'Membership'),
      fac_name,
      null::text,
      null::timestamptz,
      null::timestamptz,
      (coalesce(ms.total_amount_inr, 0) * 100)::bigint,
      coalesce((
        select sum(p.amount_inr) * 100 from payments p
        where p.membership_id = ms.id and p.status = 'paid'
      ), 0)::bigint,
      null::text,
      -- A running AutoPay that has already collected a charge is next due on its current period's end, not on the
      -- day the membership started; otherwise the start date, as before.
      coalesce(
        (
          select s.current_end
          from membership_subscriptions s
          where s.membership_id = ms.id
            and s.status::text in ('created', 'authenticated', 'active', 'pending')
            and s.charge_count > 0
            and s.current_end is not null
        ),
        ms.start_date
      )
    from memberships ms
    left join members mem2 on mem2.id = ms.member_id
    left join membership_plans mp on mp.id = ms.plan_id
    where ms.facility_id = p_facility_id
      and ms.status <> 'cancelled'

    union all

    -- Coaching enrollments. Cancelled ones are not owed; a zero-priced
    -- (membership-included) enrollment falls out at `total_minor > 0`.
    select
      'COACHING_ENROLLMENT',
      e.id,
      'COACH-' || upper(substr(replace(e.id::text, '-', ''), 1, 6)),
      coalesce(mem3.full_name, 'Member'),
      mem3.phone,
      concat_ws(' • ', cp.name, 'from ' || to_char(e.start_date, 'DD Mon')),
      fac_name,
      null::text,
      null::timestamptz,
      null::timestamptz,
      coalesce(e.price_minor, 0)::bigint,
      coalesce((
        select sum(p.amount_inr) * 100 from payments p
        where p.coaching_enrollment_id = e.id and p.status = 'paid'
      ), 0)::bigint,
      null::text,
      -- Same rule for a monthly coaching subscription: once the first charge is collected, the next due date is
      -- the subscription's current period end (e.g. paid 18 Oct -> next due 17 Nov), not the enrollment start.
      coalesce(
        (
          select b.current_end
          from coaching_enrollment_billing b
          where b.enrollment_id = e.id
            and b.kind = 'SUBSCRIPTION'
            and b.status in ('CREATED', 'AUTHENTICATED', 'ACTIVE', 'PENDING')
            and b.charge_count > 0
            and b.current_end is not null
        ),
        e.start_date
      )
    from coaching_enrollments e
    left join members mem3 on mem3.id = e.member_id
    left join coaching_programs cp on cp.id = e.program_id
    where e.facility_id = p_facility_id
      and e.status <> 'CANCELLED'
  ),
  scored as (
    select
      o.*,
      (o.total_minor - o.paid_minor) as outstanding_minor,
      case
        when o.paid_minor >= o.total_minor then 'PAID'
        when o.paid_minor > 0 then 'PARTIALLY_PAID'
        else 'PENDING'
      end as settle_status
    from obligations o
    where o.total_minor > 0
  ),
  filtered as (
    select
      s.*,
      (s.settle_status <> 'PAID' and s.due_on < (now() at time zone tz)::date) as is_overdue
    from scored s
    where
      (p_source_id is not null and s.source_id = p_source_id)
      or (
        p_source_id is null
        and case coalesce(p_status, 'ALL_OUTSTANDING')
          when 'PAID' then s.settle_status = 'PAID'
          when 'PENDING' then s.settle_status = 'PENDING'
          when 'PARTIALLY_PAID' then s.settle_status = 'PARTIALLY_PAID'
          when 'OVERDUE' then s.settle_status <> 'PAID' and s.due_on < (now() at time zone tz)::date
          else s.settle_status <> 'PAID'
        end
        and (p_source_type is null or s.source_type = p_source_type)
        and (p_from is null or s.due_on >= p_from)
        and (p_to is null or s.due_on <= p_to)
        and (
          p_search is null or trim(p_search) = ''
          or s.customer_name ilike '%' || trim(p_search) || '%'
          or s.customer_phone ilike '%' || trim(p_search) || '%'
          or s.reference ilike '%' || trim(p_search) || '%'
          or s.description ilike '%' || trim(p_search) || '%'
        )
      )
  )
  select
    f.source_type,
    f.source_id,
    f.reference,
    f.customer_name,
    f.customer_phone,
    f.description,
    f.facility_name,
    f.court_name,
    f.starts_at,
    f.ends_at,
    f.total_minor,
    f.paid_minor,
    f.outstanding_minor,
    case when f.is_overdue then 'OVERDUE' else f.settle_status end,
    f.payment_method,
    f.due_on,
    count(*) over () as total_count
  from filtered f
  order by
    case when p_sort = 'AMOUNT' then f.outstanding_minor end desc nulls last,
    case when p_sort = 'CUSTOMER' then f.customer_name end asc nulls last,
    case when p_sort = 'NEWEST' then f.due_on end desc nulls last,
    f.due_on asc
  limit greatest(p_limit, 1) offset greatest(p_offset, 0);
end;
$$;

grant execute on function list_pending_payments(uuid, text, text, text, date, date, text, integer, integer, uuid) to authenticated;
