-- ═══════════════════════════════════════════════════════════════════════════
-- Razorpay Checkout — Phase 3 (database).
--
--   record_payment_attempt — stores the raw, UNVERIFIED result the client
--   gets back from Razorpay Checkout (web) / the Razorpay Flutter SDK
--   (mobile) after the customer pays or the attempt fails. This is
--   deliberately the entire extent of Phase 3's server-side work: it does
--   NOT verify the payment signature, does NOT call Razorpay, and does NOT
--   confirm a booking or activate a membership. It only advances
--   payment_orders.status to PAYMENT_ATTEMPTED (success callback) or FAILED
--   (failure callback), so a later phase's webhook/signature verification
--   has something concrete to verify against.
--
--   A plain user cancellation (closing the Checkout modal without Razorpay
--   ever reporting success or failure) intentionally calls neither branch —
--   the order is left at ORDER_CREATED so create_payment_order's existing
--   dedup logic lets the same order be retried.
-- ═══════════════════════════════════════════════════════════════════════════

create function record_payment_attempt(
  p_payment_order_id uuid,
  p_status payment_order_status,
  p_razorpay_payment_id text default null,
  p_razorpay_signature text default null
) returns payment_orders
language plpgsql
as $$
declare
  result payment_orders;
begin
  if p_status not in ('PAYMENT_ATTEMPTED', 'FAILED') then
    raise exception 'record_payment_attempt only accepts PAYMENT_ATTEMPTED or FAILED.' using errcode = '23514';
  end if;

  update payment_orders
    set status = p_status,
        razorpay_payment_id = coalesce(p_razorpay_payment_id, razorpay_payment_id),
        razorpay_signature = coalesce(p_razorpay_signature, razorpay_signature)
    where id = p_payment_order_id
      and status in ('CREATED', 'ORDER_CREATED', 'PAYMENT_ATTEMPTED', 'FAILED')
    returning * into result;

  if result.id is null then
    raise exception 'That payment order cannot be updated (not found, or already past the attempt stage).' using errcode = '23514';
  end if;

  return result;
end;
$$;

grant execute on function record_payment_attempt(uuid, payment_order_status, text, text) to authenticated;