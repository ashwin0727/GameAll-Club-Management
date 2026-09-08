-- ═══════════════════════════════════════════════════════════════════════════
-- Fix: the Money screen's "Pending" tile ignores unpaid memberships
--
-- get_finance_summary (0046) computes the two pending figures like this:
--
--   outstanding_minor    = SUM(bookings.amount_minor) WHERE payment_status <> 'PAID'
--   pending_payment_count = COUNT(payment_orders in CREATED/…/AUTHORIZED)
--
-- Neither sees a membership taken with Payment = "Pending":
--   • create_membership_full writes a payments row with status = 'created'
--     and NO payment_orders row, so the count (which only looks at
--     payment_orders) stays 0.
--   • the amount only sums bookings, never memberships.
--
-- Meanwhile the tile links to the Pending Payments screen, whose
-- list_pending_payments (0052) DOES derive membership debt from
-- memberships.total_amount_inr vs. paid `payments`. So the tile said
-- "0 bookings / ₹0" while the screen it opened listed the member.
--
-- Align both figures with list_pending_payments: one obligation set —
-- bookings + memberships — counted/summed wherever paid < total. Facility
-- wide (not date-scoped), matching that screen's default view.
--
-- Genuine gateway *failures* still come from payment_orders (a failed
-- charge attempt is a real event, not an obligation) — unchanged.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function get_finance_summary(
  p_facility_id uuid,
  p_preset text default null,
  p_start_date date default null,
  p_end_date date default null
)
returns table (
  gross_revenue_minor bigint,
  refunds_minor bigint,
  expenses_minor bigint,
  net_revenue_minor bigint,
  outstanding_minor bigint,
  transaction_count bigint,
  successful_payment_count bigint,
  failed_payment_count bigint,
  pending_payment_count bigint,
  pending_refund_count bigint,
  settlement_exception_count bigint
)
language plpgsql
stable
as $$
declare
  range_ tstzrange;
  tz text;
  gross bigint;
  refunded bigint;
  spent bigint;
  outstanding bigint;
  pending bigint;
  succ bigint;
  failed bigint;
begin
  if not has_facility_role(p_facility_id, array['owner', 'manager', 'staff']::facility_role[]) then
    raise exception 'Not authorized for this facility.' using errcode = '42501';
  end if;
  range_ := resolve_finance_date_range(p_facility_id, p_preset, p_start_date, p_end_date);
  tz := coalesce((select f.timezone from facilities f where f.id = p_facility_id), 'Asia/Kolkata');

  select (coalesce(sum(p.amount_inr), 0) * 100)::bigint, count(*)::bigint
    into gross, succ
    from payments p
    where p.facility_id = p_facility_id and p.status = 'paid' and range_ @> coalesce(p.paid_at, p.created_at);

  select coalesce(sum(r.amount_minor), 0)::bigint
    into refunded
    from refunds r
    where r.facility_id = p_facility_id and r.status = 'PROCESSED'
      and r.processed_at is not null and range_ @> r.processed_at;

  -- Voided expenses are excluded from the arithmetic but remain on the books.
  select coalesce(sum(e.amount_minor), 0)::bigint
    into spent
    from expenses e
    where e.facility_id = p_facility_id and e.status = 'RECORDED'
      and range_ @> (e.spent_on::timestamp at time zone tz);

  -- Genuine gateway failures — a charge that was attempted and declined.
  select count(*) filter (where po.status = 'FAILED')
    into failed
    from payment_orders po
    where po.facility_id = p_facility_id and range_ @> po.created_at;

  -- Everything still owed, from every source, exactly as the Pending
  -- Payments screen derives it: cost minus what has actually been collected.
  with obligations as (
    select
      coalesce(b.amount_minor, 0)::bigint as total_minor,
      coalesce((
        select sum(p.amount_inr) * 100 from payments p
        where p.booking_id = b.id and p.status = 'paid'
      ), 0)::bigint as paid_minor
    from bookings b
    where b.facility_id = p_facility_id
      and b.status in ('pending', 'confirmed', 'completed')

    union all

    select
      (coalesce(ms.total_amount_inr, 0) * 100)::bigint,
      coalesce((
        select sum(p.amount_inr) * 100 from payments p
        where p.membership_id = ms.id and p.status = 'paid'
      ), 0)::bigint
    from memberships ms
    where ms.facility_id = p_facility_id
      and ms.status <> 'cancelled'
  ),
  owed as (
    select (o.total_minor - o.paid_minor) as amount
    from obligations o
    where o.total_minor > 0 and o.paid_minor < o.total_minor
  )
  select coalesce(sum(amount), 0)::bigint, count(*)::bigint
    into outstanding, pending
    from owed;

  return query select
    gross::bigint,
    refunded::bigint,
    spent::bigint,
    (gross - refunded - spent)::bigint,
    outstanding::bigint,
    (succ + failed + pending)::bigint,
    succ::bigint,
    failed::bigint,
    pending::bigint,
    (select count(*) from refunds r2 where r2.facility_id = p_facility_id and r2.status in ('REQUESTED', 'PROCESSING', 'PENDING'))::bigint,
    (select count(*) from settlement_exceptions se where se.facility_id = p_facility_id and se.status = 'OPEN')::bigint;
end;
$$;

grant execute on function get_finance_summary(uuid, text, date, date) to authenticated;
