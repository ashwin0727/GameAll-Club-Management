-- ═══════════════════════════════════════════════════════════════════════════
-- Look up one obligation, and stop inventing debts that were never owed.
--
-- Two changes to list_pending_payments:
--
-- 1. p_source_id, so the Record Payment page can load the single obligation
--    it is collecting against. That page is a real route — it survives a
--    reload and can be linked to — so it cannot rely on a row handed to it
--    by the list it came from. Adding a parameter to the same function keeps
--    one definition of what "outstanding" means; a second function would be
--    a second answer waiting to disagree.
--
-- 2. A booking can be created already marked paid (create_booking takes
--    p_payment_status), which leaves no payments row behind it. Computing
--    "paid" from payments alone therefore reported the full amount as
--    outstanding on a booking nobody owes anything for. The flag is now
--    honoured as settlement of record.
-- ═══════════════════════════════════════════════════════════════════════════

drop function if exists list_pending_payments(uuid, text, text, text, date, date, text, integer, integer);

create function list_pending_payments(
  p_facility_id uuid,
  p_search text default null,
  p_source_type text default null,
  p_status text default 'ALL_OUTSTANDING',
  p_from date default null,
  p_to date default null,
  p_sort text default 'DUE_DATE',
  p_limit integer default 20,
  p_offset integer default 0,
  -- When set, returns just this obligation whatever its status: the Record
  -- Payment page needs to render a settled one as settled, not as missing.
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
      -- A booking flagged PAID is settled even with no payments row behind
      -- it; otherwise take what was actually collected.
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
      ms.start_date
    from memberships ms
    left join members mem2 on mem2.id = ms.member_id
    left join membership_plans mp on mp.id = ms.plan_id
    where ms.facility_id = p_facility_id
      and ms.status <> 'cancelled'
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


-- get_pending_payments_summary calls the list, so it is recreated against
-- the new signature.
create or replace function get_pending_payments_summary(
  p_facility_id uuid,
  p_from date default null,
  p_to date default null
)
returns table (
  outstanding_minor bigint,
  pending_minor bigint,
  partially_paid_minor bigint,
  overdue_minor bigint,
  obligation_count bigint
)
language plpgsql
stable
as $$
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;

  return query
  with rows as (
    select * from list_pending_payments(
      p_facility_id, null, null, 'ALL_OUTSTANDING', p_from, p_to, 'DUE_DATE', 100000, 0, null
    )
  )
  select
    coalesce(sum(r.outstanding_minor), 0)::bigint,
    coalesce(sum(r.outstanding_minor) filter (where r.status = 'PENDING'), 0)::bigint,
    coalesce(sum(r.outstanding_minor) filter (where r.status = 'PARTIALLY_PAID'), 0)::bigint,
    coalesce(sum(r.outstanding_minor) filter (where r.status = 'OVERDUE'), 0)::bigint,
    count(*)::bigint
  from rows r;
end;
$$;

grant execute on function get_pending_payments_summary(uuid, date, date) to authenticated;
