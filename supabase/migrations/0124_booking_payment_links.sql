-- ═══════════════════════════════════════════════════════════════════════════
-- Guest booking → "Pay Online" payment link.
--
-- Staff create a guest booking for a player who is NOT at the counter, so the checkout cannot open on the
-- staff member's screen. Instead a one-time Razorpay Payment Link is generated for the booking and shared
-- with the player, who pays on their own phone.
--
-- Everything money-related stays on the existing payment_orders rail:
--   * the amount is the booking's server-computed amount (create_payment_order) — never the client's;
--   * the link is attached to that payment order (razorpay_payment_link_id);
--   * when Razorpay reports the link paid (signed webhook), the payment is applied through the same
--     apply_payment_verification gate (amount / currency / duplicate-payment checks, finance row, and the
--     inline settle_payment that confirms the booking), so a link payment can never be settled any
--     differently from a checkout payment.
-- ═══════════════════════════════════════════════════════════════════════════

alter table payment_orders
  add column if not exists razorpay_payment_link_id text,
  add column if not exists payment_link_url text,
  add column if not exists payment_link_status text
    check (payment_link_status is null or payment_link_status in ('CREATED', 'PAID', 'CANCELLED', 'EXPIRED'));

-- A Razorpay link belongs to exactly one payment order.
create unique index if not exists payment_orders_razorpay_payment_link_id_idx
  on payment_orders (razorpay_payment_link_id) where razorpay_payment_link_id is not null;

-- ─────────────────────────────────────────────────────────────────────────
-- apply_booking_payment_link_event — called ONLY by the razorpay-webhook function (service role), after it
-- has verified Razorpay's signature. Returns false when the link is not one of ours (so the webhook can
-- hand it to the coaching handler), true when it handled it.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function apply_booking_payment_link_event(
  p_razorpay_payment_link_id text,
  p_event text,
  p_razorpay_order_id text default null,
  p_razorpay_payment_id text default null,
  p_amount_minor integer default null,
  p_currency text default null
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  row_ payment_orders;
begin
  select * into row_ from payment_orders where razorpay_payment_link_id = p_razorpay_payment_link_id for update;
  if row_.id is null then
    return false;
  end if;

  if p_event = 'paid' then
    if p_razorpay_order_id is null or p_razorpay_payment_id is null or p_amount_minor is null or p_currency is null then
      raise exception 'A paid payment link event needs the order, payment, amount and currency.' using errcode = '22023';
    end if;

    -- The link carries its own Razorpay order. Adopt it while the payment order is still open; never
    -- rewrite it once the order has been captured or settled.
    if row_.razorpay_order_id is distinct from p_razorpay_order_id then
      if row_.status in ('CREATED', 'ORDER_CREATED', 'PAYMENT_ATTEMPTED', 'PAYMENT_VERIFICATION_PENDING', 'PAYMENT_VERIFIED', 'AUTHORIZED') then
        update payment_orders set razorpay_order_id = p_razorpay_order_id where id = row_.id;
      else
        raise exception 'This payment order is already % and cannot take a different Razorpay order.', row_.status using errcode = '23514';
      end if;
    end if;

    -- Amount / currency / duplicate-payment checks, the finance row and settlement all happen in here.
    perform apply_payment_verification(row_.id, p_razorpay_order_id, p_razorpay_payment_id, 'CAPTURED', p_amount_minor, p_currency);

    update payment_orders set payment_link_status = 'PAID' where id = row_.id;
    return true;
  end if;

  if p_event in ('cancelled', 'expired') then
    -- A link that was already paid stays paid; this only closes one that never was.
    update payment_orders
      set payment_link_status = upper(p_event)
      where id = row_.id and coalesce(payment_link_status, 'CREATED') <> 'PAID';
    return true;
  end if;

  return true;
end;
$$;

revoke execute on function apply_booking_payment_link_event(text, text, text, text, integer, text) from public, anon, authenticated;
grant execute on function apply_booking_payment_link_event(text, text, text, text, integer, text) to service_role;
