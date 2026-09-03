-- ═══════════════════════════════════════════════════════════════════════════
-- Guest booking revenue was being reported as member booking revenue.
--
-- finance_transactions_view classified a payment from payment_orders.source_type
-- when the money came through the Razorpay flow, and otherwise fell back to:
--
--   case when p.membership_id is not null then 'MEMBERSHIP' else 'MEMBER_BOOKING' end
--
-- That fallback was written when every non-membership payment did go through
-- Razorpay. It no longer holds. A guest who pays at the venue is recorded by
-- record_guest_booking_payment, which writes a payments row with no
-- payment_order and no membership_id — so every pay-at-venue guest booking,
-- which is now the main way guests pay, was counted as member revenue. The
-- same applied to a released membership seat sold to a guest.
--
-- The booking itself already knows: bookings.customer_type is 'GUEST' or
-- 'MEMBER', and the view already joins it. Classification now asks.
--
-- The view computes live, so this reclassifies past payments as well as new
-- ones — the Revenue Breakdown will change the moment it is applied, and the
-- new figures are the correct ones.
--
-- Column names, types and order are unchanged, so the view can be replaced
-- in place and every function reading it keeps working.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace view finance_transactions_view with (security_invoker = true) as
select
  p.id,
  'TXN-' || upper(substr(p.id::text, 1, 8)) as reference,
  p.facility_id,
  p.created_at,
  p.paid_at,
  coalesce(p.paid_at, p.created_at) as effective_at,
  -- Razorpay's own classification wins when the payment went through that
  -- flow. Otherwise ask what the money was actually for, in order of
  -- certainty: a membership, then the booking's own customer type, then a
  -- released membership seat — which is only ever sold to a guest.
  coalesce(
    po.source_type::text,
    case
      when p.membership_id is not null then 'MEMBERSHIP'
      when b.customer_type = 'GUEST' then 'GUEST_BOOKING'
      when p.membership_session_booking_id is not null then 'GUEST_BOOKING'
      else 'MEMBER_BOOKING'
    end
  ) as source_type,
  coalesce(m.full_name, gp.name, b.guest_name) as customer_name,
  coalesce(m.phone, gp.phone, b.guest_phone) as customer_phone,
  p.booking_id,
  p.membership_id,
  p.payment_order_id,
  (p.amount_inr * 100)::bigint as amount_minor,
  coalesce(po.currency, fac.currency, 'INR') as currency,
  p.payment_method,
  p.status::text as status,
  p.razorpay_order_id,
  p.razorpay_payment_id,
  coalesce(rf.processed, 0)::bigint as refunded_minor,
  coalesce(rf.pending, 0)::bigint as pending_refund_minor,
  ((p.amount_inr * 100) - coalesce(rf.processed, 0))::bigint as net_minor
from payments p
left join payment_orders po on po.id = p.payment_order_id
left join facilities fac on fac.id = p.facility_id
left join bookings b on b.id = p.booking_id
left join members m on m.id = p.member_id
left join guest_players gp on gp.id = p.guest_player_id
left join lateral (
  select
    sum(r.amount_minor) filter (where r.status = 'PROCESSED') as processed,
    sum(r.amount_minor) filter (where r.status in ('REQUESTED', 'PROCESSING', 'PENDING')) as pending
  from refunds r
  where r.payment_order_id = p.payment_order_id
) rf on true;

grant select on finance_transactions_view to authenticated;
